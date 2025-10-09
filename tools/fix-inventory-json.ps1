<#
Fix Inventory JSON inside an HTML file

Usage:
  pwsh .\tools\fix-inventory-json.ps1 -HtmlPath ".\docs\inventario_interactivo_offline.html"

What it does:
 - Creates a backup of the HTML (same name + .bak timestamp)
 - Finds all <script id="inventory-data" type="application/json">...</script> blocks
 - If the JSON inside is invalid, tries to extract a JS array (var rows = [...]) or the first [...] block
 - Removes git conflict markers (<<<<<<<, =======, >>>>>>>)
 - Attempts a few safe fixes: remove JS comments, remove trailing commas, normalize quotes
 - Parses the array and maps properties: path->ruta, drive->unidad, size->tamano, last->fecha, name->nombre
 - If nombre/null, computes it from ruta (filename)
 - Writes a single cleaned <script id="inventory-data" type="application/json">[ ... ]</script>
 - Removes any other duplicate script#inventory-data and moves any removed `var rows = [...]` into a separate
   <script type="text/javascript" data-moved-rows="true">...</script> placed after the inventory-data tag

Notes:
 - The script is conservative and will create a backup before changing anything.
 - If parsing still fails it will not overwrite the original; instead it writes a .failed.json with the last
   attempted JSON text and exits with non-zero code.
<#
Fix Inventory JSON inside an HTML file

Usage:
  pwsh .\tools\fix-inventory-json.ps1 -HtmlPath ".\docs\inventario_interactivo_offline.html"

This script is conservative: it creates a backup, tries multiple safe cleanup steps and
only overwrites the original HTML when it successfully parses and normalizes the inventory array.

It will move any leftover `var rows = [...]` blocks into a separate <script> after the
canonical inventory-data script instead of deleting them, and it writes a .failed.json.txt
when parsing attempts fail.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$HtmlPath = ".\docs\inventario_interactivo_offline.html"
)

function Backup-File {
    param([string]$Path)
    $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $bak = "$Path.bak.$ts"
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    return $bak
}

function Remove-GitConflictMarkers {
    param([string]$Text)
    return $Text -replace '(?m)^<<<<<<<.*$','' -replace '(?m)^=======.*$','' -replace '(?m)^>>>>>>>.*$',''
}

function ExtractFirstArray {
    param([string]$Text)
    $start = $Text.IndexOf('[')
    if ($start -lt 0) { return $null }
    $depth = 0
    for ($i = $start; $i -lt $Text.Length; $i++) {
        switch ($Text[$i]) { '[' { $depth++ } ']' { $depth-- } }
        if ($depth -eq 0) { return $Text.Substring($start, $i - $start + 1) }
    }
    return $null
}

function TryFixJsonText {
    param([string]$JsonText)
    if (-not $JsonText) { return $null }
    $t = $JsonText
    $t = [regex]::Replace($t, '(?s)/\*.*?\*/', '')
    $t = [regex]::Replace($t, '(?m)//.*$','')
    $t = Remove-GitConflictMarkers -Text $t
    $t = [regex]::Replace($t, '(?m)^[\s\S]*\$top\=[^\r\n]*$','')
    $t = [regex]::Replace($t, ',\s*(\]|\})','$1')
    if (($t -split "'").Count -gt ($t -split '"').Count) { $t = $t -replace "'", '"' }
    return $t
}

function ParseJsonSafely {
    param([string]$Text)
    try { return ConvertFrom-Json -InputObject $Text -ErrorAction Stop } catch { return $null }
}

if (-not (Test-Path -LiteralPath $HtmlPath)) { Write-Error "HTML file not found: $HtmlPath"; exit 2 }

$orig = Get-Content -LiteralPath $HtmlPath -Raw
Write-Host "Backing up original to..."
$bak = Backup-File -Path $HtmlPath
Write-Host "  $bak"

# Find the script blocks
$rx = '(?si)<script\b[^>]*\bid\s*=\s*"inventory-data"[^>]*>(.*?)</script>'
$scriptMatches = [regex]::Matches($orig, $rx)

$foundArrayText = $null
$movedRowsText = $null

if ($scriptMatches.Count -gt 0) {
    foreach ($m in $scriptMatches) {
        $inner = $m.Groups[1].Value.Trim()
        if ($inner.Length -gt 0) { $candidate = $inner; break } else { $candidate = $inner }
    }
    if ($candidate -match '\bvar\s+rows\s*=\s*\[') {
        $mvar = [regex]::Match($candidate, '(?s)var\s+rows\s*=\s*(\[[\s\S]*?\])\s*;?')
        if ($mvar.Success) { $foundArrayText = $mvar.Groups[1].Value }
    }
    if (-not $foundArrayText) {
        if ($candidate.TrimStart().StartsWith('[')) { $foundArrayText = ExtractFirstArray -Text $candidate } else {
            $mvar2 = [regex]::Match($orig, '(?s)var\s+rows\s*=\s*(\[[\s\S]*?\])\s*;?')
            if ($mvar2.Success) { $foundArrayText = $mvar2.Groups[1].Value }
        }
    }
} else {
    $mvar2 = [regex]::Match($orig, '(?s)var\s+rows\s*=\s*(\[[\s\S]*?\])\s*;?')
    if ($mvar2.Success) { $foundArrayText = $mvar2.Groups[1].Value }
}

if ($foundArrayText) {
    $attempt = $foundArrayText
    $fixed = TryFixJsonText -JsonText $attempt
    $parsed = ParseJsonSafely -Text $fixed

    if (-not $parsed) {
        $arr = ExtractFirstArray -Text $fixed
        if ($arr) {
            $fixed2 = TryFixJsonText -JsonText $arr
            $parsed = ParseJsonSafely -Text $fixed2
            if ($parsed) { $fixed = $fixed2 }
        }
    }

    if (-not $parsed) {
        $fixed3 = $fixed -replace "'", '"'
        $fixed3 = [regex]::Replace($fixed3, ',\s*(\]|\})','$1')
        $parsed = ParseJsonSafely -Text $fixed3
        if ($parsed) { $fixed = $fixed3 }
    }

    if (-not $parsed) {
        $failPath = "$HtmlPath.failed.json.txt"
        Set-Content -LiteralPath $failPath -Value $fixed -Encoding UTF8
        Write-Error "Could not parse JSON array after attempts. Saved last attempt to: $failPath"
        exit 3
    }

    $newRows = @()
    foreach ($r in $parsed) {
        $obj = [ordered]@{}
        foreach ($p in $r.PSObject.Properties) {
            $lname = $p.Name.ToLowerInvariant()
            $val = $p.Value
            switch ($lname) {
                'path' { $obj['ruta'] = $val }
                'drive' { $obj['unidad'] = $val }
                'size' { $obj['tamano'] = $val }
                'last' { $obj['fecha'] = $val }
                'name' { $obj['nombre'] = $val }
                'nombre' { $obj['nombre'] = $val }
                default { $obj[$p.Name] = $val }
            }
        }
        if (-not $obj.ContainsKey('nombre') -or -not $obj['nombre']) {
            if ($obj.ContainsKey('ruta') -and $obj['ruta']) {
                try { $fname = [System.IO.Path]::GetFileName($obj['ruta']) } catch { $parts = ($obj['ruta'] -split '[\\/]'); $fname = $parts[-1] }
                $obj['nombre'] = $fname
            }
        }
        $newRows += [PSCustomObject]$obj
    }

    $jsonOut = ConvertTo-Json $newRows -Depth 10

    # Remove existing inventory-data scripts
    $out = [regex]::Replace($orig, $rx, '')

    # Move any var rows blocks
    $varMatch = [regex]::Match($out, '(?s)(var\s+rows\s*=\s*\[[\s\S]*?\])\s*;?')
    if ($varMatch.Success) { $movedRowsText = $varMatch.Groups[1].Value.Trim(); $out = $out -replace [regex]::Escape($varMatch.Groups[0].Value), '' }

    $wrapperStart = @'
<script id="inventory-data" type="application/json">
'@
    $wrapperEnd = @'
</script>
'@
    # Compose script tag using the static wrapper here-strings and the JSON output.
    $scriptTag = $wrapperStart + "`r`n" + $jsonOut + "`r`n" + $wrapperEnd

    $insertPos = 0
    if ($scriptMatches.Count -gt 0) { $insertPos = $scriptMatches[0].Index }
    $newHtml = $out.Substring(0, $insertPos) + $scriptTag + $out.Substring($insertPos)

    if ($movedRowsText) {
        # Use a double-quoted here-string so $movedRowsText is interpolated safely.
        $jsTag = @"
<script type=\"text/javascript\" data-moved-rows=\"true\">
// moved original var rows block for safety
$movedRowsText
</script>
"@
        # Insert the moved-rows script immediately after the newly added inventory-data script.
        $newHtml = $newHtml -replace [regex]::Escape($scriptTag), $scriptTag + $jsTag
    }

    Set-Content -LiteralPath $HtmlPath -Value $newHtml -Encoding UTF8
    Write-Host "Fixed inventory-data in: $HtmlPath"
    Write-Host "Rows output: $($newRows.Count)  (backup at $bak)"
    exit 0
} else {
    Write-Error "No array or <script id=\"inventory-data\"> block found nor var rows=... in the HTML. Nothing changed."
    exit 4
}
