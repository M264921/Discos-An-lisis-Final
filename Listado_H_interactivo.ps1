param(
    [string]$Root = "H:\",
    [string]$OutputHtml = "$env:USERPROFILE\Desktop\Listado_H_interactivo.html",
    [switch]$Ascii
)

function Format-Size {
    param([Int64]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    elseif ($Bytes -lt 1MB) { return ("{0:N1} KB" -f ($Bytes/1KB)) }
    elseif ($Bytes -lt 1GB) { return ("{0:N1} MB" -f ($Bytes/1MB)) }
    elseif ($Bytes -lt 1TB) { return ("{0:N1} GB" -f ($Bytes/1GB)) }
    else { return ("{0:N2} TB" -f ($Bytes/1TB)) }
}

function Get-Icon {
    param(
        [System.IO.FileSystemInfo]$Item,
        [bool]$UseAscii
    )
    if ($Item.PSIsContainer) {
        if ($UseAscii) { return "[DIR]" } else { return "📂" }
    }

    $ext = ""
    if ($Item.Extension) { $ext = $Item.Extension.ToLower() }

    if ($UseAscii) {
        switch ($ext) {
            ".mp4" { "[VID]"; break } ".mkv" { "[VID]"; break } ".avi" { "[VID]"; break } ".mov" { "[VID]"; break }
            ".jpg" { "[IMG]"; break } ".jpeg"{ "[IMG]"; break } ".png" { "[IMG]"; break } ".gif" { "[IMG]"; break }
            ".csv" { "[CSV]"; break } ".xls" { "[XLS]"; break } ".xlsx"{ "[XLSX]"; break }
            ".txt" { "[TXT]"; break } ".doc" { "[DOC]"; break } ".docx"{ "[DOCX]"; break } ".pdf" { "[PDF]"; break }
            default { "[FILE]" }
        }
    } else {
        switch ($ext) {
            ".mp4" { "🎬"; break } ".mkv" { "🎬"; break } ".avi" { "🎬"; break } ".mov" { "🎬"; break }
            ".jpg" { "🖼️"; break } ".jpeg"{ "🖼️"; break } ".png" { "🖼️"; break } ".gif" { "🖼️"; break }
            ".csv" { "📊"; break } ".xls" { "📊"; break } ".xlsx"{ "📊"; break }
            ".txt" { "📄"; break } ".doc" { "📄"; break } ".docx"{ "📄"; break } ".pdf" { "📄"; break }
            default { "📄" }
        }
    }
}

# Cache para tamaños por carpeta (mejora rendimiento)
$FolderSizeCache = @{}

function Get-FolderStats {
    param([string]$Path)
    if ($FolderSizeCache.ContainsKey($Path)) { return $FolderSizeCache[$Path] }

    $fileCount = 0
    [Int64]$totalBytes = 0
    try {
        $files = Get-ChildItem -LiteralPath $Path -Force -File -Recurse -ErrorAction SilentlyContinue
        if ($files) {
            $fileCount = $files.Count
            $sum = ($files | Measure-Object -Sum Length).Sum
            if ($null -ne $sum) { $totalBytes = [Int64]$sum }
        }
    } catch {}

    $stats = [PSCustomObject]@{ Count = $fileCount; Bytes = $totalBytes }
    $FolderSizeCache[$Path] = $stats
    return $stats
}

function Html-Escape { param([string]$s)
    if ($null -eq $s) { return "" }
    $t = $s -replace '&','&amp;'
    $t = $t -replace '<','&lt;'
    $t = $t -replace '>','&gt;'
    return $t
}

function Get-FileUri {
    param([string]$FullPath)

    if (-not $FullPath) { return "" }

    try {
        return ([System.Uri]$FullPath).AbsoluteUri
    } catch {
        return ""
    }
}

function Build-TreeHtml {
    param(
        [string]$Path,
        [switch]$UseAscii
    )

    try {
        $children = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        return "<div class='error'>[ERROR] Acceso denegado: $(Html-Escape $Path)</div>"
    }

    $dirs  = $children | Where-Object { $_.PSIsContainer } | Sort-Object Name
    $files = $children | Where-Object { -not $_.PSIsContainer } | Sort-Object Name

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine("<ul>")

    foreach ($d in $dirs) {
        $stats = Get-FolderStats -Path $d.FullName

        $isEmpty = $false
        try {
            $isEmpty = ((Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0)
        } catch {}

        $icon = Get-Icon -Item $d -UseAscii:$UseAscii
        $folderName = Html-Escape $d.Name

        if ($isEmpty) {
            if ($UseAscii) { $label = "$icon [EMPTY] $folderName" } else { $label = "$icon❌ $folderName" }
            $null = $sb.AppendLine("<li class='dir empty'><details><summary>$label</summary></details></li>")
        } else {
            if ($UseAscii) {
                $label = "$icon $folderName ($($stats.Count) files, $(Format-Size $($stats.Bytes)))"
            } else {
                $label = "$icon $folderName ($($stats.Count) archivos, $(Format-Size $($stats.Bytes)))"
            }
            $null = $sb.AppendLine("<li class='dir'><details><summary>$label</summary>")
            $null = $sb.AppendLine( (Build-TreeHtml -Path $d.FullName -UseAscii:$UseAscii) )
            $null = $sb.AppendLine("</details></li>")
        }
    }

    foreach ($f in $files) {
        $icon = Get-Icon -Item $f -UseAscii:$UseAscii
        $size = Format-Size ([Int64]$f.Length)
        $name = Html-Escape $f.Name
        $full = Html-Escape $f.FullName
        $uri = Html-Escape (Get-FileUri -FullPath $f.FullName)
        if ($uri) {
            $label = "<a class='nm' href='$uri' target='_blank' rel='noopener'>$name</a>"
        } else {
            $label = "<span class='nm'>$name</span>"
        }
        $null = $sb.AppendLine("<li class='file' data-name='$name' title='$full'><span class='ico'>$icon</span> $label <span class='sz'>$size</span></li>")
    }

    $null = $sb.AppendLine("</ul>")
    return $sb.ToString()
}

# -------- HTML BASE --------
$useAscii = $Ascii.IsPresent
$rootItem = Get-Item -LiteralPath $Root
$rootFull = $rootItem.FullName
$generated = (Get-Date).ToString("yyyy-MM-dd HH:mm")

# Resumen global (totales)
[int]$totalDirs = 0
[int]$totalFiles = 0
[Int64]$totalBytes = 0
try {
    $totalDirs = (Get-ChildItem -LiteralPath $Root -Force -Directory -Recurse -ErrorAction SilentlyContinue).Count
} catch {}
try {
    $allFiles = Get-ChildItem -LiteralPath $Root -Force -File -Recurse -ErrorAction SilentlyContinue
    if ($allFiles) {
        $totalFiles = $allFiles.Count
        $sum = ($allFiles | Measure-Object -Sum Length).Sum
        if ($null -ne $sum) { $totalBytes = [Int64]$sum }
    }
} catch {}

$css = @"
* { box-sizing: border-box; font-family: ui-sans-serif, system-ui, Segoe UI, Roboto, Arial, "Apple Color Emoji","Segoe UI Emoji"; }
body { margin: 16px; color: #111827; }
h1 { font-size: 20px; margin-bottom: 6px; }
.summary { color:#374151; margin-bottom:10px; }
.toolbar { display:flex; gap:8px; align-items:center; margin: 8px 0 16px; }
input[type=search] { padding:8px 10px; border:1px solid #d1d5db; border-radius:8px; min-width:320px; }
button { padding:8px 10px; border:1px solid #d1d5db; background:#f9fafb; border-radius:8px; cursor:pointer; }
button:hover { background:#f3f4f6; }
ul { list-style: none; padding-left: 18px; margin:0; }
li { margin: 2px 0; }
li.dir > details > summary { cursor: pointer; }
li.dir.empty summary { color:#9ca3af; }
.sz { color:#6b7280; margin-left:8px; font-variant-numeric: tabular-nums; }
.ico { width: 1.4em; display:inline-block; text-align:center; }
a.nm { color:#2563eb; text-decoration:none; }
a.nm:visited { color:#1d4ed8; }
a.nm:hover { text-decoration:underline; }
footer { margin-top: 16px; color:#6b7280; font-size: 12px; }
.error { color:#b91c1c; }
.hidden { display:none !important; }
"@

$js = @"
(function(){
  const q = document.getElementById('q');
  const tree = document.getElementById('tree');
  const btnOpen = document.getElementById('openAll');
  const btnClose = document.getElementById('closeAll');

  function filter() {
    const term = (q.value||'').trim().toLowerCase();
    if (!term) {
      tree.querySelectorAll('.hidden').forEach(el => el.classList.remove('hidden'));
      return;
    }
    tree.querySelectorAll('li').forEach(li => li.classList.add('hidden'));
    const hits = Array.from(tree.querySelectorAll('li')).filter(li => (li.textContent||'').toLowerCase().includes(term));
    hits.forEach(li => {
      li.classList.remove('hidden');
      let p = li.parentElement;
      while (p && p !== tree) {
        if (p.tagName === 'DETAILS') p.open = true;
        if (p.tagName === 'UL') p = p.parentElement;
        else p = p.parentElement;
        if (p && p.tagName === 'LI') p.classList.remove('hidden');
      }
    });
  }
  q.addEventListener('input', filter);
  btnOpen.addEventListener('click', () => { tree.querySelectorAll('details').forEach(d => d.open = true); });
  btnClose.addEventListener('click', () => { tree.querySelectorAll('details').forEach(d => d.open = false); });
})();
"@

$treeHtml = Build-TreeHtml -Path $Root -UseAscii:$useAscii
$modoTxt = if ($useAscii) { "ASCII" } else { "Emoji" }
$summaryLine = "Carpetas: $totalDirs · Archivos: $totalFiles · Tamaño total: $(Format-Size $totalBytes)"

$html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8" />
<title>Árbol $(Html-Escape $rootFull)</title>
<style>$css</style>
</head>
<body>
  <h1>Árbol de: $(Html-Escape $rootFull)</h1>
  <div class="summary">Generado: $generated — Modo: $modoTxt<br/>$summaryLine</div>
  <div class="toolbar">
    <input id="q" type="search" placeholder="Filtrar por nombre..." />
    <button id="openAll">Abrir todo</button>
    <button id="closeAll">Cerrar todo</button>
  </div>
  <div id="tree">
    $treeHtml
  </div>
  <footer>Clic en cada carpeta para plegar/desplegar. Usa el cuadro de búsqueda para filtrar.</footer>
<script>$js</script>
</body>
</html>
"@

# Exporta
$html | Out-File -FilePath $OutputHtml -Encoding UTF8
Write-Host "✅ HTML interactivo generado en: $OutputHtml" -ForegroundColor Green
