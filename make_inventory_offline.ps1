# ============================
# make_inventory_offline.ps1
# ============================

[CmdletBinding()]
param(
  [string[]]$Drives = @('H','I','J'),
  [string]$Output = 'inventario_interactivo_offline.html',
  [string]$DocsTarget,
  [switch]$Push,
  [string]$CommitMessage = 'chore(docs): actualizar inventario offline'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-OutputPath {
  param(
    [string]$BasePath,
    [string]$Candidate
  )
  if ([string]::IsNullOrWhiteSpace($Candidate)) {
    return [System.IO.Path]::Combine($BasePath, 'inventario_interactivo_offline.html')
  }
  if ([System.IO.Path]::IsPathRooted($Candidate)) {
    return $Candidate
  }
  return [System.IO.Path]::Combine($BasePath, $Candidate)
}

function Normalize-Drive {
  param([string]$DriveId)
  if ([string]::IsNullOrWhiteSpace($DriveId)) { return $null }
  $trimmed = $DriveId.Trim()
  if (-not $trimmed) { return $null }
  return $trimmed.Substring(0,1).ToUpperInvariant()
}

function Resolve-LastWriteIso {
  param(
    [string]$Value,
    [System.Globalization.CultureInfo[]]$Cultures
  )
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  $text = $Value.Trim()
  if (-not $text) { return $null }
  $formats = @(
    'yyyy-MM-ddTHH:mm:ss',
    'yyyy-MM-ddTHH:mm:ss.fff',
    'yyyy-MM-dd HH:mm:ss',
    'yyyy/MM/dd HH:mm:ss',
    'dd/MM/yyyy HH:mm:ss',
    'dd-MM-yyyy HH:mm:ss',
    'MM/dd/yyyy HH:mm:ss',
    'yyyy-MM-dd'
  )
  foreach ($culture in $Cultures) {
    foreach ($fmt in $formats) {
      try {
        $parsed = [datetime]::ParseExact($text, $fmt, $culture)
        return $parsed.ToString('s')
      } catch {}
    }
    try {
      $parsed = [datetime]::Parse($text, $culture)
      return $parsed.ToString('s')
    } catch {}
  }
  return $null
}

$script:InventoryTypeByExtension = @{}
$inventoryGroups = @{
  video     = @('3gp','asf','avi','flv','m2ts','m4v','mkv','mov','mp4','mpeg','mpg','mts','mxf','ts','vob','webm','wmv')
  foto      = @('arw','bmp','cr2','cr3','dng','gif','heic','heif','jpg','jpeg','nef','orf','png','psd','raf','raw','svg','tif','tiff','webp')
  audio     = @('aac','aiff','ape','flac','m3u','m4a','mid','midi','mp3','ogg','opus','wav','wma')
  documento = @('csv','doc','docm','docx','htm','html','ini','json','key','log','md','numbers','odp','ods','odt','pdf','ppt','pptx','rtf','txt','xls','xlsm','xlsx','xml','yaml','yml')
}
foreach ($entry in $inventoryGroups.GetEnumerator()) {
  foreach ($ext in $entry.Value) {
    $script:InventoryTypeByExtension[$ext] = $entry.Key
  }
}

function Get-InventoryType {
  param([string]$Extension)
  if ([string]::IsNullOrWhiteSpace($Extension)) { return 'otro' }
  $ext = $Extension.Trim().ToLowerInvariant()
  if ($ext.StartsWith('.')) { $ext = $ext.Substring(1) }
  if ($script:InventoryTypeByExtension.ContainsKey($ext)) {
    return $script:InventoryTypeByExtension[$ext]
  }
  return 'otro'
}

function Escape-ScriptJson {
  param([string]$Json)
  if ($null -eq $Json) { return '' }
  return ($Json -replace '</', '<\/')
}

$repoRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
Push-Location $repoRoot
try {
  $outputPath = Resolve-OutputPath -BasePath $repoRoot -Candidate $Output
  $docsTargetPath = if ($DocsTarget) { Resolve-OutputPath -BasePath $repoRoot -Candidate $DocsTarget } else { $null }

  $outputDir = Split-Path -Parent $outputPath
  if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
  }

  if ($docsTargetPath) {
    $docsDir = Split-Path -Parent $docsTargetPath
    if ($docsDir -and -not (Test-Path -LiteralPath $docsDir)) {
      New-Item -ItemType Directory -Force -Path $docsDir | Out-Null
    }
  }

  $indexPath = Join-Path $repoRoot 'index_by_hash.csv'
  if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "index_by_hash.csv no se encontro en $repoRoot"
  }

  $driveFilter = @()
  if ($Drives) {
    foreach ($driveItem in $Drives) {
      $normalized = Normalize-Drive -DriveId $driveItem
      if ($normalized) { $driveFilter += $normalized }
    }
    if ($driveFilter.Count) {
      $driveFilter = $driveFilter | Sort-Object -Unique
    }
  }

  $cultures = @(
    [System.Globalization.CultureInfo]::GetCultureInfo('es-ES'),
    [System.Globalization.CultureInfo]::InvariantCulture
  )

  $rawRows = Import-Csv -LiteralPath $indexPath
  $rows = New-Object System.Collections.Generic.List[object]
  $driveCounts = @{}
  $driveBytes = @{}
  $typeCounts = @{}
  $totalBytes = 0L

  foreach ($item in $rawRows) {
    $path = $item.Path
    if ([string]::IsNullOrWhiteSpace($path)) { continue }
    $path = $path.Trim()
    if (-not $path) { continue }

    $drive = $item.Drive
    if (-not $drive -and $path -match '^[A-Za-z]:') {
      $drive = $path.Substring(0,1)
    }
    $drive = Normalize-Drive -DriveId $drive
    if (-not $drive) { continue }
    if ($driveFilter.Count -gt 0 -and -not ($driveFilter -contains $drive)) { continue }

    $lengthText = ('' + ($item.Length ?? '0')).Trim()
    $lengthValue = 0L
    if (-not [long]::TryParse($lengthText, [ref]$lengthValue)) {
      $normalizedLength = $lengthText -replace '[^0-9]', ''
      if (-not [long]::TryParse($normalizedLength, [ref]$lengthValue)) {
        $lengthValue = 0L
      }
    }

    $lastIso = Resolve-LastWriteIso -Value $item.LastWrite -Cultures $cultures

    $extension = $item.Extension
    if (-not $extension) {
      $extension = [System.IO.Path]::GetExtension($path)
    }
    $type = Get-InventoryType -Extension $extension

    $name = [System.IO.Path]::GetFileName($path)
    if (-not $name) { $name = $path }

    $sha = if ($item.Hash) { ('' + $item.Hash).Trim().ToUpperInvariant() } else { '' }

    $row = [PSCustomObject]@{
      sha   = $sha
      type  = $type
      name  = $name
      path  = $path
      drive = $drive
      size  = [int64]$lengthValue
      last  = $lastIso
    }
    $rows.Add($row) | Out-Null

    if (-not $driveCounts.ContainsKey($drive)) { $driveCounts[$drive] = 0 }
    $driveCounts[$drive]++

    if (-not $driveBytes.ContainsKey($drive)) { $driveBytes[$drive] = 0L }
    $driveBytes[$drive] += $lengthValue

    if (-not $typeCounts.ContainsKey($type)) { $typeCounts[$type] = 0 }
    $typeCounts[$type]++

    $totalBytes += $lengthValue
  }

  $rowsArray = @($rows)
  $metaObject = [ordered]@{
    total = $rowsArray.Count
    totalBytes = $totalBytes
    driveCounts = [ordered]@{}
    driveBytes = [ordered]@{}
    typeCounts = [ordered]@{}
    generatedAt = (Get-Date).ToUniversalTime().ToString('s')
  }
  foreach ($driveKey in ($driveCounts.Keys | Sort-Object)) {
    $metaObject.driveCounts[$driveKey] = $driveCounts[$driveKey]
    $metaObject.driveBytes[$driveKey] = $driveBytes[$driveKey]
  }
  foreach ($typeKey in ($typeCounts.Keys | Sort-Object)) {
    $metaObject.typeCounts[$typeKey] = $typeCounts[$typeKey]
  }

  $metaJson = $metaObject | ConvertTo-Json -Depth 6 -Compress
  $dataJson = $rowsArray | ConvertTo-Json -Depth 4 -Compress

  $metaPayload = Escape-ScriptJson -Json $metaJson
  $dataPayload = Escape-ScriptJson -Json $dataJson

  $assetsDir = Join-Path $repoRoot 'tools' 'templates'
  $cssPath = Join-Path $assetsDir 'inventory_offline.css'
  $jsPath = Join-Path $assetsDir 'inventory_offline.js'

  if (-not (Test-Path -LiteralPath $cssPath)) {
    throw "No se encontro $cssPath"
  }
  if (-not (Test-Path -LiteralPath $jsPath)) {
    throw "No se encontro $jsPath"
  }

  $styleBlock = Get-Content -LiteralPath $cssPath -Raw -Encoding UTF8
  $scriptBlock = Get-Content -LiteralPath $jsPath -Raw -Encoding UTF8

  $builder = New-Object System.Text.StringBuilder
  [void]$builder.AppendLine('<!DOCTYPE html>')
  [void]$builder.AppendLine('<html lang="es">')
  [void]$builder.AppendLine('<head>')
  [void]$builder.AppendLine('  <meta charset="utf-8" />')
  [void]$builder.AppendLine('  <meta name="viewport" content="width=device-width, initial-scale=1" />')
  [void]$builder.AppendLine('  <title>Inventario offline</title>')
  [void]$builder.AppendLine('  <style>')
  [void]$builder.AppendLine($styleBlock.TrimEnd())
  [void]$builder.AppendLine('  </style>')
  [void]$builder.AppendLine('</head>')
  [void]$builder.AppendLine('<body>')
  [void]$builder.AppendLine('  <div class="app">')
  [void]$builder.AppendLine('    <header class="page-header">')
  [void]$builder.AppendLine('      <div>')
  [void]$builder.AppendLine('        <h1>Inventario offline</h1>')
  [void]$builder.AppendLine('        <p class="muted" id="generated-at"></p>')
  [void]$builder.AppendLine('      </div>')
  [void]$builder.AppendLine('    </header>')
  [void]$builder.AppendLine('    <section class="toolbar">')
  [void]$builder.AppendLine('      <div class="search-box">')
  [void]$builder.AppendLine('        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 2a8 8 0 105.293 14.003l4.352 4.354a1 1 0 001.414-1.414l-4.354-4.352A8 8 0 0010 2zm0 2a6 6 0 110 12A6 6 0 0110 4z"/></svg>')
  [void]$builder.AppendLine('        <input id="global-search" type="search" placeholder="Buscar por nombre, ruta o hash" autocomplete="off" />')
  [void]$builder.AppendLine('      </div>')
  [void]$builder.AppendLine('      <div class="toolbar-buttons">')
  [void]$builder.AppendLine('        <button type="button" class="btn" id="reset-filters">Reset filtros</button>')
  [void]$builder.AppendLine('        <button type="button" class="btn primary" id="export-csv">Exportar CSV</button>')
  [void]$builder.AppendLine('      </div>')
  [void]$builder.AppendLine('    </section>')
  [void]$builder.AppendLine('    <section class="chip-bar">')
  [void]$builder.AppendLine('      <div class="chip-group">')
  [void]$builder.AppendLine('        <span class="chip-label">Unidades</span>')
  [void]$builder.AppendLine('        <div class="chip-set" id="drive-chips" data-chip="drive"></div>')
  [void]$builder.AppendLine('      </div>')
  [void]$builder.AppendLine('      <div class="chip-group">')
  [void]$builder.AppendLine('        <span class="chip-label">Tipos</span>')
  [void]$builder.AppendLine('        <div class="chip-set" id="type-chips" data-chip="type"></div>')
  [void]$builder.AppendLine('      </div>')
  [void]$builder.AppendLine('    </section>')
  [void]$builder.AppendLine('    <section class="stats">')
  [void]$builder.AppendLine('      <div class="stats-grid">')
  [void]$builder.AppendLine('        <article class="stat-card">')
  [void]$builder.AppendLine('          <span class="stat-label">Archivos visibles</span>')
  [void]$builder.AppendLine('          <span class="stat-value" id="stat-count">0</span>')
  [void]$builder.AppendLine('          <span class="stat-sub" id="stat-total"></span>')
  [void]$builder.AppendLine('        </article>')
  [void]$builder.AppendLine('        <article class="stat-card">')
  [void]$builder.AppendLine('          <span class="stat-label">Tamano visible</span>')
  [void]$builder.AppendLine('          <span class="stat-value" id="stat-size">0 B</span>')
  [void]$builder.AppendLine('          <span class="stat-sub" id="stat-size-total"></span>')
  [void]$builder.AppendLine('        </article>')
  [void]$builder.AppendLine('        <article class="stat-card">')
  [void]$builder.AppendLine('          <span class="stat-label">Resumen por unidad</span>')
  [void]$builder.AppendLine('          <ul class="stat-list" id="stat-drive"></ul>')
  [void]$builder.AppendLine('        </article>')
  [void]$builder.AppendLine('      </div>')
  [void]$builder.AppendLine('    </section>')
  [void]$builder.AppendLine('    <section class="legend">')
  [void]$builder.AppendLine('      <h2>Como usar</h2>')
  [void]$builder.AppendLine('      <ul>')
  [void]$builder.AppendLine('        <li>Busca por nombre, ruta o hash con el cuadro superior.</li>')
  [void]$builder.AppendLine('        <li>Combina chips de unidad y tipo para acotar el inventario.</li>')
  [void]$builder.AppendLine('        <li>Usa los filtros de columna para coincidencias exactas o comparaciones de tamano (ej. &gt;2GB).</li>')
  [void]$builder.AppendLine('        <li>Los botones de cada fila permiten abrir la ruta o copiarla al portapapeles.</li>')
  [void]$builder.AppendLine('        <li>Exporta el conjunto visible a CSV para compartir un corte puntual.</li>')
  [void]$builder.AppendLine('      </ul>')
  [void]$builder.AppendLine('    </section>')
  [void]$builder.AppendLine('    <section class="table-panel">')
  [void]$builder.AppendLine('      <div class="table-wrap">')
  [void]$builder.AppendLine('        <table id="inventory-table">')
  [void]$builder.AppendLine('          <thead>')
  [void]$builder.AppendLine('            <tr>')
  [void]$builder.AppendLine('              <th class="sortable" data-sort="name">Nombre<span class="sort-indicator"></span></th>')
  [void]$builder.AppendLine('              <th class="sortable" data-sort="drive">Unidad<span class="sort-indicator"></span></th>')
  [void]$builder.AppendLine('              <th class="sortable" data-sort="type">Tipo<span class="sort-indicator"></span></th>')
  [void]$builder.AppendLine('              <th class="sortable numeric" data-sort="size">Tamano<span class="sort-indicator"></span></th>')
  [void]$builder.AppendLine('              <th class="sortable" data-sort="last">Modificado<span class="sort-indicator"></span></th>')
  [void]$builder.AppendLine('              <th class="sortable" data-sort="sha">SHA<span class="sort-indicator"></span></th>')
  [void]$builder.AppendLine('              <th class="sortable" data-sort="path">Ruta<span class="sort-indicator"></span></th>')
  [void]$builder.AppendLine('              <th>Acciones</th>')
  [void]$builder.AppendLine('            </tr>')
  [void]$builder.AppendLine('            <tr class="filters">')
  [void]$builder.AppendLine('              <th><input data-filter="name" placeholder="Nombre" /></th>')
  [void]$builder.AppendLine('              <th><input data-filter="drive" placeholder="Unidad" /></th>')
  [void]$builder.AppendLine('              <th><input data-filter="type" placeholder="Tipo" /></th>')
  [void]$builder.AppendLine('              <th><input data-filter="size" placeholder="Tamano" /></th>')
  [void]$builder.AppendLine('              <th><input data-filter="last" placeholder="Fecha" /></th>')
  [void]$builder.AppendLine('              <th><input data-filter="sha" placeholder="SHA" /></th>')
  [void]$builder.AppendLine('              <th><input data-filter="path" placeholder="Ruta" /></th>')
  [void]$builder.AppendLine('              <th></th>')
  [void]$builder.AppendLine('            </tr>')
  [void]$builder.AppendLine('          </thead>')
  [void]$builder.AppendLine('          <tbody></tbody>')
  [void]$builder.AppendLine('        </table>')
  [void]$builder.AppendLine('      </div>')
  [void]$builder.AppendLine('      <div class="empty" id="empty-state" hidden>No hay filas con los filtros actuales.</div>')
  [void]$builder.AppendLine('    </section>')
  [void]$builder.AppendLine('  </div>')
  [void]$builder.AppendLine("  <script id=\"inventory-meta\" type=\"application/json\">$metaPayload</script>")
  [void]$builder.AppendLine("  <script id=\"inventory-data\" type=\"application/json\">$dataPayload</script>")
  [void]$builder.AppendLine('  <script>')
  [void]$builder.AppendLine($scriptBlock.TrimEnd())
  [void]$builder.AppendLine('  </script>')
  [void]$builder.AppendLine('</body>')
  [void]$builder.AppendLine('</html>')

  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($outputPath, $builder.ToString(), $encoding)
  Write-Host "Inventario renderizado en: $outputPath"

  if ($docsTargetPath -and -not [string]::Equals($docsTargetPath, $outputPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    Copy-Item -LiteralPath $outputPath -Destination $docsTargetPath -Force
    Write-Host "Copia adicional en: $docsTargetPath"
  }

  if ($Push) {
    $git = Get-Command git -ErrorAction Stop
    $targets = @($outputPath)
    if ($docsTargetPath) { $targets += $docsTargetPath }
    $uniqueTargets = $targets | Sort-Object -Unique
    foreach ($target in $uniqueTargets) {
      & $git.Source add -- $target
    }
    $status = & $git.Source status --short
    if ($status) {
      & $git.Source commit -m $CommitMessage | Out-Null
      & $git.Source push
      Write-Host 'Cambios enviados.'
    } else {
      Write-Host 'Sin cambios para commitear.'
    }
  }
}
finally {
  Pop-Location
}
