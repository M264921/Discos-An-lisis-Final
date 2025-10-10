Param(
  [string]$RepoRoot = "$PSScriptRoot/../..",
  [string]$HtmlPath = 'docs/inventario_interactivo_offline.html',
  [string]$CsvFallback = 'docs/hash_data.csv',
  [int]$PreviewRows = 50
)

$ErrorActionPreference = 'Stop'

function Resolve-InRepo {
  param(
    [string]$Base,
    [string]$Path
  )
  if ([string]::IsNullOrWhiteSpace($Path)) { return $Base }
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  $combined = [IO.Path]::Combine($Base, $Path)
  return [IO.Path]::GetFullPath($combined)
}

$resolvedRepo = (Resolve-Path -LiteralPath $RepoRoot).Path
Push-Location $resolvedRepo
try {
  $logDir = Join-Path $resolvedRepo 'logs'
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $logPath = Join-Path $logDir 'make-inventory-wrapper.log'

  function Write-WrapperLog {
    param(
      [string]$Message,
      [string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'u'), $Level.ToUpperInvariant(), $Message
    $line | Tee-Object -FilePath $logPath -Append | Out-Null
  }

  $htmlFull = Resolve-InRepo -Base $resolvedRepo -Path $HtmlPath
  $csvFull = $null
  try {
    $csvFull = Resolve-InRepo -Base $resolvedRepo -Path $CsvFallback
  } catch {
    $csvFull = $null
  }

  if (-not (Test-Path -LiteralPath $htmlFull)) {
    throw "No existe el HTML generado: $htmlFull"
  }

  $normalizer = Resolve-InRepo -Base $resolvedRepo -Path 'tools/normalize-inventory-html.ps1'
  $injector = Resolve-InRepo -Base $resolvedRepo -Path 'tools/inventory-inject-from-csv.ps1'
  $sanitizer = Resolve-InRepo -Base $resolvedRepo -Path 'tools/sanitize-inventory-html.ps1'

  foreach ($scriptPath in @($normalizer, $injector, $sanitizer)) {
    if (-not (Test-Path -LiteralPath $scriptPath)) {
      throw "Script requerido no encontrado: $scriptPath"
    }
  }

  function Parse-JsonRows {
    param([string]$Json)
    if (-not $Json) { return @() }
    $text = $Json.Trim()
    if ($text.EndsWith(';')) { $text = $text.Substring(0, $text.Length - 1) }
    try {
      $parsed = $text | ConvertFrom-Json -ErrorAction Stop
    } catch {
      return @()
    }
    if ($null -eq $parsed) { return @() }
    if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string])) {
      return @($parsed)
    }
    return @($parsed)
  }

  function Build-DriveCounts {
    param([object[]]$Rows)
    $counts = [ordered]@{}
    foreach ($row in $Rows) {
      if (-not $row) { continue }
      $drive = $null
      if ($row.PSObject.Properties['Drive']) { $drive = $row.Drive }
      if (-not $drive -and $row.PSObject.Properties['Unidad']) { $drive = $row.Unidad }
      if (-not $drive) {
        $path = $null
        foreach ($candidate in @('Path', 'FullPath', 'FullName', 'Location', 'Ruta')) {
          if ($row.PSObject.Properties[$candidate]) {
            $path = $row.$candidate
            break
          }
        }
        if ($path -and $path -match '^[A-Za-z]:') { $drive = $path.Substring(0, 1) }
      }
      if (-not $drive) { continue }
      $key = ("{0}" -f $drive).Substring(0, 1).ToUpperInvariant()
      if (-not $counts.Contains($key)) { $counts[$key] = 0 }
      $counts[$key]++
    }
    foreach ($letter in @('H','I','J')) {
      if (-not $counts.Contains($letter)) { $counts[$letter] = 0 }
    }
    return $counts
  }

  function Format-MetaSummary {
    param(
      [object[]]$Rows,
      [System.Collections.Specialized.OrderedDictionary]$DriveCounts,
      [string]$ExistingSummary
    )
    if ($ExistingSummary) { return $ExistingSummary }
    $segments = New-Object System.Collections.Generic.List[string]
    $segments.Add("Total: {0}" -f $Rows.Count) | Out-Null

    $hiParts = New-Object System.Collections.Generic.List[string]
    foreach ($letter in @('H','I','J')) {
      $count = if ($DriveCounts.Contains($letter)) { $DriveCounts[$letter] } else { 0 }
      $null = $hiParts.Add([string]::Format("{0}: {1}", $letter, $count))
    }
    if ($hiParts.Count -gt 0) {
      $segments.Add(($hiParts -join ' / ')) | Out-Null
    }

    $others = $DriveCounts.Keys | Where-Object { $_ -notin @('H','I','J') } | Sort-Object
    if ($others) {
      $extraParts = $others | ForEach-Object { [string]::Format("{0}: {1}", $_, $DriveCounts[$_]) }
      if ($extraParts) {
        $segments.Add(($extraParts -join ' / ')) | Out-Null
      }
    }

    return ($segments -join ' | ')
  }

  function Get-InventorySnapshot {
    param([string]$Path)
    $snapshot = [ordered]@{
      Count = 0
      MetaSummary = ''
      Drives = [ordered]@{}
    }
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]$snapshot }
    $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($content)) { return [pscustomobject]$snapshot }
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    $setDataRegex = [System.Text.RegularExpressions.Regex]::new('window\.__INVENTARIO__\.setData\(\s*(\[[\s\S]*?\])\s*,\s*([^)]+?)\);', $options)
    $match = $setDataRegex.Match($content)
    $json = $null
    $metaRaw = $null
    if ($match.Success) {
      $json = $match.Groups[1].Value
      $metaRaw = $match.Groups[2].Value
    } else {
      $dataRegex = [System.Text.RegularExpressions.Regex]::new('window\.(?:__DATA__|_DATA_)\s*=\s*(\[[\s\S]*?\]);', $options)
      $dataMatch = $dataRegex.Match($content)
      if ($dataMatch.Success) {
        $json = $dataMatch.Groups[1].Value
      }
      $metaRegex = [System.Text.RegularExpressions.Regex]::new('window\.(?:__META__|_META_)\s*=\s*(.+?);', $options)
      $metaMatch = $metaRegex.Match($content)
      if ($metaMatch.Success) { $metaRaw = $metaMatch.Groups[1].Value }
    }
    $rows = Parse-JsonRows -Json $json
    $snapshot.Count = $rows.Count
    $driveCounts = Build-DriveCounts -Rows $rows
    if ($rows.Count -le 0) {
      $inlineJsonRegex = [System.Text.RegularExpressions.Regex]::new('<script[^>]+id=["'']inventory-data["''][^>]*>(?<data>[\s\S]*?)</script>', $options)
      $jsonMatch = $inlineJsonRegex.Match($content)
      if ($jsonMatch.Success) {
        $jsonInline = $jsonMatch.Groups['data'].Value
        $rows = Parse-JsonRows -Json $jsonInline
        $snapshot.Count = $rows.Count
        $driveCounts = Build-DriveCounts -Rows $rows
      }
    }
    if ($rows.Count -le 0) {
      $invB64Regex = [System.Text.RegularExpressions.Regex]::new(
        '<script[^>]+id=["'']INV_B64["''][^>]*>(?<data>[\s\S]*?)</script>',
        $options
      )
      $match = $invB64Regex.Match($content)
      if ($match.Success) {
        $b64Raw = ($match.Groups['data'].Value) -replace '\s+', ''
        if ($b64Raw -and ($b64Raw -match '^[A-Za-z0-9+/=]+$')) {
          try {
            $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64Raw))
            $rows = Parse-JsonRows -Json $decoded
            $snapshot.Count = $rows.Count
            $driveCounts = Build-DriveCounts -Rows $rows
          } catch {
            Write-WrapperLog ("Fallo al decodificar INV_B64: {0}" -f $_.Exception.Message) 'WARN'
          }
        }
      }
    }
    $snapshot.Drives = $driveCounts
    $metaObj = $null
    if ($metaRaw) {
      $metaText = $metaRaw.Trim()
      if ($metaText.EndsWith(';')) { $metaText = $metaText.Substring(0, $metaText.Length - 1) }
      try {
        $metaObj = $metaText | ConvertFrom-Json -ErrorAction Stop
      } catch {
        if ($metaText.StartsWith('"') -and $metaText.EndsWith('"')) {
          try { $metaObj = $metaText | ConvertFrom-Json -ErrorAction Stop } catch { $metaObj = $metaText.Trim('"') }
        } else {
          $metaObj = $metaText
        }
      }
    }
    $summary = $null
    if ($metaObj -is [psobject] -and $metaObj.PSObject.Properties['summary']) {
      $summary = ("{0}" -f $metaObj.summary).Trim()
    } elseif ($metaObj -is [string]) {
      $summary = ("{0}" -f $metaObj).Trim()
    }
    $snapshot.MetaSummary = Format-MetaSummary -Rows $rows -DriveCounts $driveCounts -ExistingSummary $summary
    return [pscustomobject]$snapshot
  }

  Write-WrapperLog "== Wrapper inventario (post-proceso) =="
  Write-WrapperLog "Repositorio: $resolvedRepo"
  Write-WrapperLog "HTML: $htmlFull"
  if ($csvFull) { Write-WrapperLog "CSV fallback: $csvFull" }

  Write-WrapperLog 'Normalizando inventario...'
  & $normalizer -HtmlPath $htmlFull -PreviewRows $PreviewRows | Tee-Object -FilePath $logPath -Append
  $snapshot = Get-InventorySnapshot -Path $htmlFull
  Write-WrapperLog ("Filas tras normalizacion: {0}" -f $snapshot.Count)

  if ($snapshot.Count -le 0) {
    if ($csvFull -and (Test-Path -LiteralPath $csvFull)) {
      Write-WrapperLog "Inventario vacio. Inyectando datos desde CSV de respaldo..." 'WARN'
      & $injector -CsvPath $csvFull -HtmlPath $htmlFull | Tee-Object -FilePath $logPath -Append
      Write-WrapperLog 'Re-aplicando normalizacion tras inyeccion...'
      & $normalizer -HtmlPath $htmlFull -PreviewRows $PreviewRows | Tee-Object -FilePath $logPath -Append
      $snapshot = Get-InventorySnapshot -Path $htmlFull
      Write-WrapperLog ("Filas tras inyeccion: {0}" -f $snapshot.Count)
    } else {
      Write-WrapperLog 'Inventario vacio y sin CSV de respaldo disponible.' 'WARN'
    }
  }

  Write-WrapperLog 'Sanitizando HTML final...'
  & $sanitizer -HtmlPath $htmlFull | Tee-Object -FilePath $logPath -Append
  $snapshot = Get-InventorySnapshot -Path $htmlFull
  if ($snapshot.MetaSummary) {
    Write-WrapperLog ("Meta final: {0}" -f $snapshot.MetaSummary)
  }
  Write-WrapperLog ("Filas finales: {0}" -f $snapshot.Count)
  Write-WrapperLog '== Wrapper completado =='
} finally {
  Pop-Location
}



