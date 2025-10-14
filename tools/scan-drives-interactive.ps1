[CmdletBinding()]
param(
  [string[]]$Roots,
  [switch]$ComputeHash,
  [switch]$OpenAfter,
  [switch]$VerboseLog,
  [ValidateSet('Media','Otros','Todo')][string]$ContentFilter = 'Media',
  [switch]$SkipPublish
)

$ErrorActionPreference = 'Stop'

function Get-DefaultRoots {
  try {
    $drives = Get-PSDrive -PSProvider FileSystem | Sort-Object Name
  } catch {
    Write-Warning ("No se pudieron enumerar las unidades: {0}" -f $_.Exception.Message)
    return @('C:')
  }

  if (-not $drives -or $drives.Count -eq 0) { return @('C:') }

  $included = @()
  $report = @()

  foreach ($drive in $drives) {
    $root = $drive.Root
    if (-not $root) { $root = ("{0}:\\" -f $drive.Name) }
    $normalizedRoot = ($root).TrimEnd('\\') + '\\'

    $include = $true
    $reasons = @()

    if ($drive.DisplayRoot) {
      $reasons += ("DisplayRoot={0}" -f $drive.DisplayRoot)
    }
    if ($drive.Free -eq $null) {
      $reasons += 'Espacio libre desconocido'
    }
    if (-not (Test-Path -LiteralPath $normalizedRoot)) {
      $include = $false
      $reasons += 'Ruta inaccesible'
    }

    $freeGb = $null
    if ($drive.Free -ne $null) {
      $freeGb = [math]::Round(($drive.Free / 1GB), 2)
    }

    $report += [pscustomobject]@{
      Name    = $drive.Name
      Root    = $normalizedRoot
      FreeGB  = $freeGb
      Include = $include
      Reason  = if ($reasons.Count -gt 0) { $reasons -join '; ' } else { 'OK' }
    }

    if ($include) {
      $included += $normalizedRoot.TrimEnd('\\')
    }
  }

  Write-Host ''
  Write-Host 'Resumen de unidades disponibles:' -ForegroundColor Cyan
  foreach ($item in $report) {
    $status = if ($item.Include) { 'incluida' } else { 'omitida' }
    $freeText = if ($item.FreeGB -ne $null) { ('{0:N2} GB libres' -f $item.FreeGB) } else { 'espacio desconocido' }
    $reasonText = if ($item.Reason -and $item.Reason -ne 'OK') { (" (motivo: {0})" -f $item.Reason) } else { '' }
    Write-Host ("  {0}: {1} ({2}) -> {3}{4}" -f $item.Name, $item.Root, $freeText, $status, $reasonText)
  }

  if (-not $included -or $included.Count -eq 0) {
    Write-Warning 'No se detectaron unidades con espacio libre accesible; usando C:\\ por defecto.'
    return @('C:')
  }

  return $included
}

function Normalize-Root([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  $trimmed = $value.Trim().Trim('"').Trim("'")
  if ($trimmed.Length -eq 2 -and $trimmed[1] -eq ':') { return "$trimmed\" }
  if ($trimmed.Length -ge 2 -and $trimmed[1] -eq ':' -and $trimmed[-1] -ne '\') { return "$trimmed\" }
  return $trimmed
}

function Confirm-Roots([string[]]$candidates) {
  $resolved = @()
  foreach ($root in $candidates) {
    if (-not $root) { continue }
    if (-not (Test-Path -LiteralPath $root)) {
      Write-Warning ("Raiz no encontrada: {0}" -f $root)
      continue
    }
    $resolved += $root
  }
  return ($resolved | Select-Object -Unique)
}

$targetRoots = @()
$filterChoice = $ContentFilter
if (-not $Roots -or $Roots.Count -eq 0) {
  $defaults = Get-DefaultRoots
  Write-Host ("Unidades detectadas: {0}" -f ($defaults -join ', '))
  $answer = Read-Host "Que quieres escanear? (enter = todas; por ejemplo C:\,F:\,G:\)"
  if ([string]::IsNullOrWhiteSpace($answer)) {
    $targetRoots = $defaults | ForEach-Object { Normalize-Root $_ }
  } else {
    $targetRoots = $answer -split ',' | ForEach-Object { Normalize-Root $_ }
  }
  if (-not $PSBoundParameters.ContainsKey('ContentFilter')) {
    $filterInput = Read-Host "Filtro de contenido (Media/Otros/Todo) [Media]"
    if (-not [string]::IsNullOrWhiteSpace($filterInput)) {
      switch ($filterInput.Trim().ToLowerInvariant()) {
        'media' { $filterChoice = 'Media' }
        'otros' { $filterChoice = 'Otros' }
        'todo'  { $filterChoice = 'Todo' }
        default { Write-Warning ("Opcion no reconocida ({0}); se mantiene {1}" -f $filterInput, $filterChoice) }
      }
    }
  }
} else {
  $targetRoots = $Roots | ForEach-Object { Normalize-Root $_ }
}

$targetRoots = Confirm-Roots $targetRoots
if (-not $targetRoots -or $targetRoots.Count -eq 0) {
  Write-Warning "No hay raices validas para escanear. Saliendo."
  return
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$inventoryDir = Join-Path $repoRoot 'docs\inventory'
New-Item -ItemType Directory -Force -Path $inventoryDir | Out-Null

$script:LogSink = $null
if ($VerboseLog) {
  $logDir = Join-Path $repoRoot 'logs'
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $logPath = Join-Path $logDir ("scan-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
  $script:LogSink = {
    param($message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'u'), $message
    $line | Tee-Object -FilePath $logPath -Append | Out-Null
  }
  & $script:LogSink "Iniciando escaneo en $($targetRoots -join ', ')"
}

function Log-Info {
  param([string]$Message)
  if ($script:LogSink) { & $script:LogSink $Message }
}

Log-Info "Usando ComputeHash=$ComputeHash"
Log-Info ("ContentFilter={0}" -f $filterChoice)

$hashScript = Join-Path $repoRoot 'tools\hash-drive-to-csv.ps1'
if (-not (Test-Path -LiteralPath $hashScript)) {
  throw "No se encuentra $hashScript"
}

foreach ($root in $targetRoots) {
  Write-Host ""
  Write-Host (">>> Escaneando {0} ..." -f $root) -ForegroundColor Green
  Log-Info ("Escaneando {0}" -f $root)

  $letter = ($root.TrimEnd('\'))[0]
  if (-not $letter) { $letter = 'X' }
  $csvPath = Join-Path $inventoryDir ("scan_{0}.csv" -f ([char]::ToUpper($letter)))
  $algorithm = if ($ComputeHash) { 'SHA256' } else { 'None' }

  & $hashScript -Drive $root -OutCsv $csvPath -Algorithm $algorithm -ContentFilter $filterChoice
  Log-Info ("Generado {0} (filtro {1})" -f $csvPath, $filterChoice)
}

Write-Host ""
Write-Host ("Fusionando resultados y regenerando HTML... (Filtro: {0})" -f $filterChoice) -ForegroundColor Cyan
Log-Info "Lanzando make_inventory_offline.ps1"

$makeScript = Join-Path $repoRoot 'tools\make_inventory_offline.ps1'
& $makeScript -RepoRoot $repoRoot | Out-Null

$finalHtml = Join-Path $repoRoot 'docs\inventario_interactivo_offline.html'
if (Test-Path -LiteralPath $finalHtml) {
  Write-Host ("Inventario listo: {0}" -f $finalHtml) -ForegroundColor Green
  Log-Info ("Inventario listo: {0}" -f $finalHtml)
  if ($OpenAfter) {
    Start-Process $finalHtml
  }
} else {
  Write-Warning "No se encontro el HTML final."
  Log-Info "No se encontro el HTML final."
}

Write-Host ""
Write-Host "Todo listo. Puedes volver a ejecutarlo con -Roots 'C:\','F:\' para seleccionar unidades concretas." -ForegroundColor Yellow
Log-Info "Proceso completado."

if ($SkipPublish) {
  Write-Host "Publicacion omitida (SkipPublish especificado)." -ForegroundColor Yellow
  return
}

$syncScript = Join-Path $repoRoot 'tools\sync-to-github.ps1'
if (-not (Test-Path -LiteralPath $syncScript)) {
  Write-Warning "No se encontro tools\sync-to-github.ps1; omitiendo push automatico."
  return
}

Write-Host ""
Write-Host "Publicando inventario en GitHub (commit + push)..." -ForegroundColor Cyan
Log-Info "Lanzando sync-to-github.ps1"
$commitMessage = "Auto update inventory ({0}) filtro {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $filterChoice
try {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $syncScript -Message $commitMessage
  Log-Info "sync-to-github.ps1 finalizado"
} catch {
  Write-Warning ("Fallo al publicar cambios en GitHub: {0}" -f $_.Exception.Message)
  Log-Info ("sync-to-github.ps1 fallo: {0}" -f $_.Exception.Message)
}
