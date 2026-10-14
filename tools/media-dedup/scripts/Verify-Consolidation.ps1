param(
  [Parameter(Mandatory=$false)] [string]$ConsolidateLog = (Join-Path $PSScriptRoot '..\logs\consolidate_log.csv'),
  [Parameter(Mandatory=$false)] [string]$ReportPath = (Join-Path $PSScriptRoot '..\report\VERIFY-REPORT.md'),
  [ValidateSet('Quick','Full')] [string]$Mode = 'Quick',
  [int]$MaxItems = 0,
  [int]$ProgressInterval = 50,
  [int]$QuickMaxMB = 0,
  [switch]$BeepOnIssues,
  [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'MediaStorage.psm1') -Force
$settings = Get-MediaSettings $ConfigPath
$volumes = @(Get-MediaVolume)
if (-not (Test-Path $ConsolidateLog)) { Write-Host "No existe $ConsolidateLog"; exit 1 }

# Asegurar carpeta report
$reportDir = Split-Path -Parent $ReportPath
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }

$rows = Import-Csv -LiteralPath $ConsolidateLog

# Consideramos sólo copias efectivas
$todo = @($rows | Where-Object { $_.Mode -in 'Copy','Move' -and $_.Result -eq 'Success' -and $_.DestPath })
if ($MaxItems -gt 0) { $todo = @($todo | Select-Object -First $MaxItems) }

$total = $todo.Count
$checked = 0
$ok = 0
$missing = 0
$mismatch = 0
$errors = 0
$unconfirmed = 0

$catMap = @{}
$yearMap = @{}

function Bump($map, $key) { if (-not $map.ContainsKey($key)) { $map[$key]=0 }; $map[$key]++ }

foreach ($r in $todo) {
  $checked++
  $dst = $r.DestPath
  $src = $r.SourcePath
  $sha = $r.SHA256
  $cat = ''
  $year = ''
  $m = [regex]::Match($dst, '[\\/]([^\\/]+)[\\/]([^\\/]+)[\\/][^\\/]+$')
  if ($m.Success) { $cat = $m.Groups[1].Value; $year = $m.Groups[2].Value }

  try {
    $dst = Resolve-MediaSourcePath -Path $dst -Record ([pscustomobject]@{ VolumeSerial=$r.DestinationVolumeSerial; RelativePath=$r.DestinationRelativePath }) -Settings $settings -Volumes $volumes
    if ($Mode -eq 'Quick') { $src = Resolve-MediaSourcePath -Path $src -Record ([pscustomobject]@{ VolumeSerial=$r.SourceVolumeSerial; RelativePath=$r.SourceRelativePath }) -Settings $settings -Volumes $volumes }
    if (-not (Test-Path -LiteralPath $dst -PathType Leaf)) { $missing++; if ($cat){ Bump $catMap $cat }; if ($year){ Bump $yearMap $year }; continue }
    if ($Mode -eq 'Quick') {
      $di = $null
      try { $di = Get-Item -LiteralPath $dst -ErrorAction Stop } catch { throw }
      if ($QuickMaxMB -gt 0 -and ($di.Length/1MB) -ge $QuickMaxMB) { $unconfirmed++ }
      else {
        $si = $null
        try { if (Test-Path -LiteralPath $src -PathType Leaf) { $si = Get-Item -LiteralPath $src -ErrorAction Stop } } catch { }
        if (-not $si) { $unconfirmed++ } elseif ($si.Length -eq $di.Length) { $ok++ } else { $mismatch++ }
      }
    } else {
      $h = Get-FileHash -LiteralPath $dst -Algorithm SHA256
      if ($sha -and $h.Hash.ToUpper() -eq $sha.ToUpper()) { $ok++ } else { $mismatch++ }
    }
  } catch { $errors++ }

  if ($cat){ Bump $catMap $cat }
  if ($year){ Bump $yearMap $year }

  if ($ProgressInterval -gt 0 -and ($checked % $ProgressInterval) -eq 0) {
    $pct = if ($total -gt 0) { [int](100 * $checked / $total) } else { 0 }
    Write-Progress -Activity "Verificando media_final" -Status ("Checked: $checked/$total | OK: $ok | Missing: $missing | Mismatch: $mismatch | Errors: $errors") -PercentComplete $pct
    Write-Host ("Verif: {0}/{1} | OK: {2} | Missing: {3} | Mismatch: {4} | Errors: {5} | Último: {6}" -f $checked,$total,$ok,$missing,$mismatch,$errors,$dst)
    if ($BeepOnIssues -and ($missing -gt 0 -or $mismatch -gt 0 -or $errors -gt 0)) { try { [console]::Beep(880,120) } catch {} }
  }
}

# Construir reporte Markdown
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine('# Verificación de Consolidación')
$null = $sb.AppendLine()
$null = $sb.AppendLine("- Modo: $Mode")
$null = $sb.AppendLine("- Entradas verificadas: $checked de $total")
$null = $sb.AppendLine("- OK (existencia/hash): $ok")
$null = $sb.AppendLine("- Missing (no existe en destino): $missing")
$null = $sb.AppendLine("- Mismatch (hash distinto): $mismatch")
$null = $sb.AppendLine("- Errors (acceso/otros): $errors")
$null = $sb.AppendLine("- Unconfirmed (sin fuente o fuera del limite Quick): $unconfirmed")
$null = $sb.AppendLine()
$null = $sb.AppendLine('**Resumen por Categoría**')
foreach ($k in ($catMap.Keys | Sort-Object)) { $null = $sb.AppendLine("- ${k}: $($catMap[$k])") }
$null = $sb.AppendLine()
$null = $sb.AppendLine('**Top 10 Años**')
foreach ($kv in ($yearMap.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10)) { $null = $sb.AppendLine("- $($kv.Key): $($kv.Value)") }

[IO.File]::WriteAllText($ReportPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "Verification report saved ($Mode): $ReportPath | OK: $ok | Missing: $missing | Mismatch: $mismatch | Errors: $errors | Unconfirmed: $unconfirmed"

if ($missing -or $mismatch -or $errors -or $unconfirmed -or -not $total) { throw "Verification incomplete or failed; inspect $ReportPath" }
