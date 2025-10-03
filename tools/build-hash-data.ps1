[CmdletBinding()]
param(
    [string]$RepoRoot = "$PSScriptRoot/..",
    [string]$IndexPath = "index_by_hash.csv",
    [string]$OutputCsv = "docs/hash_data.csv",
    [string[]]$Drives = @('H','I','J')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Resolve-InRepo {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $resolvedRoot }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $resolvedRoot $Path)
}


$indexFull = Resolve-InRepo $IndexPath
if (-not (Test-Path -LiteralPath $indexFull)) {
    throw "No se encontro $indexFull"
}

$outputFull = Resolve-InRepo $OutputCsv
$outputDir = Split-Path -Parent $outputFull
if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$driveFilter = $null
if ($Drives -and $Drives.Count -gt 0) {
    $driveFilter = [System.Collections.Generic.HashSet[string]]::new([string[]]($Drives | ForEach-Object { $_.ToUpperInvariant() }))
}

function Get-DriveFromPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if ($Path.Length -ge 2 -and $Path[1] -eq ':') {
        return $Path[0].ToString().ToUpperInvariant()
    }
    return ''
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if (-not $Object) { return '' }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return '' }
    $value = $prop.Value
    if ($null -eq $value) { return '' }
    return [string]$value
}

function To-LongPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $norm = [System.IO.Path]::GetFullPath($Path)
    if ($norm.StartsWith('\\\\?\\')) { return $norm }
    if ($norm.StartsWith('\\\\')) { return "\\\\?\\UNC\\" + $norm.Substring(2) }
    return "\\\\?\\" + $norm
}

$rows = Import-Csv -LiteralPath $indexFull
$results = New-Object System.Collections.Generic.List[object]
$rehashCount = 0
$missingCount = 0

foreach ($row in $rows) {
    $path = (Get-PropertyValue $row 'Path').Trim()
    if (-not $path) { continue }

    $drive = (Get-PropertyValue $row 'Drive').Trim()
    if (-not $drive) { $drive = Get-DriveFromPath $path }
    $drive = $drive.ToUpperInvariant()
    if ($driveFilter -and -not $driveFilter.Contains($drive)) { continue }

    $hash = (Get-PropertyValue $row 'Hash').Trim()
    $lengthRaw = (Get-PropertyValue $row 'Length').Trim()
    $extension = (Get-PropertyValue $row 'Extension').Trim()
    $error = ''

    [int64]$length = 0
    if (-not [int64]::TryParse($lengthRaw, [ref]$length)) {
        $parsed = $false
        foreach ($cultureName in @('es-ES','en-US','en-GB')) {
            try {
                $culture = [System.Globalization.CultureInfo]::GetCultureInfo($cultureName)
                if ([int64]::TryParse($lengthRaw, [System.Globalization.NumberStyles]::Integer, $culture, [ref]$length)) {
                    $parsed = $true
                    break
                }
            } catch {}
        }
        if (-not $parsed) {
            try { $length = ([System.IO.FileInfo]$path).Length } catch {}
        }
    }

    if (-not $extension) {
        try { $extension = [System.IO.Path]::GetExtension($path) } catch { $extension = '' }
    }

    if (-not $hash) {
        try {
            $longPath = To-LongPath $path
            if (Test-Path -LiteralPath $longPath) {
                $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $longPath).Hash
                $rehashCount++
            } else {
                $error = 'NOT_FOUND'
                $missingCount++
            }
        } catch {
            $error = 'HASH_ERROR: ' + $_.Exception.Message
        }
    }

    $results.Add([pscustomobject]@{
        FullName  = $path
        Hash      = $hash
        Length    = $length
        Extension = $extension
        Error     = $error
    }) | Out-Null
}

$tempDir = [System.IO.Path]::GetDirectoryName($outputFull)
if (-not $tempDir) { $tempDir = [System.IO.Path]::GetTempPath() }
$tempPath = [System.IO.Path]::Combine($tempDir, [System.IO.Path]::GetRandomFileName())

$exported = $false
for ($attempt = 1; $attempt -le 3 -and -not $exported; $attempt++) {
    try {
        $results | Export-Csv -LiteralPath $tempPath -NoTypeInformation -Encoding UTF8
        $exported = $true
    } catch {
        if ($attempt -eq 3) { throw }
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 1
        $tempPath = [System.IO.Path]::Combine($tempDir, [System.IO.Path]::GetRandomFileName())
    }
}

if (-not $exported) {
    throw "No se pudo exportar datos temporales a hash_data.csv"
}

$finalized = $false
for ($attempt = 1; $attempt -le 3 -and -not $finalized; $attempt++) {
    try {
        if (Test-Path -LiteralPath $outputFull) {
            $existing = Get-Item -LiteralPath $outputFull
            if ($existing.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                $existing.IsReadOnly = $false
            }
            Remove-Item -LiteralPath $outputFull -Force
        }
        Move-Item -LiteralPath $tempPath -Destination $outputFull -Force
        $finalized = $true
    } catch {
        if ($attempt -eq 3) {
            throw "No se pudo escribir $outputFull. Cierra programas que lo tengan abierto e intentalo de nuevo."
        }
        Start-Sleep -Seconds 1
    }
}

if (Test-Path -LiteralPath $tempPath) {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}


$driveSummary = $results | Group-Object { Get-DriveFromPath $_.FullName } | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Count }
Write-Host "hash_data.csv generado -> $outputFull"
if ($driveSummary) { Write-Host ('Drives: ' + ($driveSummary -join ' | ')) }
if ($rehashCount -gt 0) { Write-Host "Rehash: $rehashCount" }
if ($missingCount -gt 0) { Write-Warning "Archivos no encontrados: $missingCount" }


