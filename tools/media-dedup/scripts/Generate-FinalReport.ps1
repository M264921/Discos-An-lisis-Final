param(
  [Parameter(Mandatory=$false)] [string]$ConsolidateLog = (Join-Path $PSScriptRoot '..\logs\consolidate_log.csv'),
  [Parameter(Mandatory=$false)] [string]$CatalogCsv = (Join-Path $PSScriptRoot '..\artifacts\media_catalog.csv'),
  [Parameter(Mandatory=$false)] [string]$VerifyReport = (Join-Path $PSScriptRoot '..\report\VERIFY-REPORT.md'),
  [Parameter(Mandatory=$false)] [string]$OutPath = (Join-Path $PSScriptRoot '..\report\CONSOLIDATION-FINAL.md'),
  [int]$TopYears = 12
)
$ErrorActionPreference='Stop'
if (-not (Test-Path $ConsolidateLog)) { throw "No existe $ConsolidateLog" }
$cons = Import-Csv -LiteralPath $ConsolidateLog
$success = @($cons | Where-Object { $_.Mode -in 'Copy','Move' -and $_.Result -eq 'Success' -and $_.DestPath })
$okCount = $success.Count

# Cargar tamaños desde el catálogo
$sizeMap = @{}
if (Test-Path $CatalogCsv) {
  Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
  Read-MediaCsv $CatalogCsv | ForEach-Object {
    if ($_.SHA256) { $sizeMap[$_.SHA256] = [long]($_.SizeBytes ?? $_.Length) }
  }
}

function Sum-Bytes($paths){ $t=[long]0; foreach($p in $paths){ if($sizeMap.ContainsKey($p)){ $t+=$sizeMap[$p] } }; return $t }
function To-GB($bytes){ [math]::Round($bytes/1GB,2) }

$catSizes=@{}
$yearSizes=@{}
foreach($r in $success){
  $dst=$r.DestPath; $src=$r.SourcePath
  $m=[regex]::Match($dst,'[\\/]([^\\/]+)[\\/]([^\\/]+)[\\/][^\\/]+$')
  if(-not $m.Success){ continue }
  $cat=$m.Groups[1].Value; $year=$m.Groups[2].Value
  $sz=[long]0; if($src -and $sizeMap.ContainsKey($r.SHA256)){ $sz=$sizeMap[$r.SHA256] }
  if(-not $catSizes.ContainsKey($cat)){ $catSizes[$cat]=[long]0 }; $catSizes[$cat]+=$sz
  if(-not $yearSizes.ContainsKey($year)){ $yearSizes[$year]=[long]0 }; $yearSizes[$year]+=$sz
}
$totalBytes = 0; foreach($v in $catSizes.Values){ $totalBytes+=$v }

# Leer verificación si existe
$verifySummary = ''
if (Test-Path $VerifyReport) {
  $verifySummary = (Get-Content -LiteralPath $VerifyReport -TotalCount 50) -join "`n"
}

$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine('# Informe Final de Consolidación')
$null = $sb.AppendLine()
$null = $sb.AppendLine("- Archivos copiados (Success): $okCount")
$null = $sb.AppendLine("- Tamaño total consolidado: " + (To-GB $totalBytes) + ' GB')
$null = $sb.AppendLine()
$null = $sb.AppendLine('**Por Categoría (GB)**')
foreach($k in ($catSizes.Keys | Sort-Object)) { $null = $sb.AppendLine("- ${k}: " + (To-GB $catSizes[$k]) + ' GB') }
$null = $sb.AppendLine()
$null = $sb.AppendLine("**Top $TopYears Años (GB)**")
foreach($kv in ($yearSizes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $TopYears)) { $null = $sb.AppendLine("- $($kv.Key): " + (To-GB $kv.Value) + ' GB') }
$null = $sb.AppendLine()
$null = $sb.AppendLine('**Verificación (resumen Quick/Full si disponible)**')
if ($verifySummary) { $null = $sb.AppendLine($verifySummary) } else { $null = $sb.AppendLine('- Aún no hay reporte de verificación.') }

$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutPath)))
[IO.File]::WriteAllText($OutPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "OK: Informe final generado en $OutPath"
