# tools/run-inventory-auto.ps1
[CmdletBinding()]
param(
  [string]$Drive = 'K:\',
  [ValidateSet('Media','Todo')][string]$ContentFilter = 'Media'
)

$ErrorActionPreference = 'Stop'

try {
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
} catch {
  Write-Error 'System.Windows.Forms no está disponible en este entorno.'
  throw
}

function Show-YesNoQuestion {
  param(
    [Parameter(Mandatory)][string]$Message,
    [string]$Title = 'Confirmación'
  )
  return [System.Windows.Forms.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
  )
}

function Show-Info {
  param(
    [Parameter(Mandatory)][string]$Message,
    [string]$Title = 'Información'
  )
  [void][System.Windows.Forms.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Information
  )
}

function Show-ErrorDialog {
  param(
    [Parameter(Mandatory)][string]$Message,
    [string]$Title = 'Error'
  )
  [void][System.Windows.Forms.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::OK,
    [System.Windows.Forms.MessageBoxIcon]::Error
  )
}

$scriptPath = $PSCommandPath
if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
$scriptDir = Split-Path -Parent $scriptPath
if (-not $scriptDir) { throw 'No se pudo determinar el directorio del script.' }

$repoRoot = $scriptDir
while ($repoRoot -and -not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
  $parent = Split-Path -Parent $repoRoot
  if (-not $parent -or $parent -eq $repoRoot) { throw 'No se encontró la raíz del repositorio.' }
  $repoRoot = $parent
}

$dataDir = Join-Path $repoRoot 'data'
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$csvFile = Join-Path $dataDir ("inventory-scan-$timestamp.csv")
$jsonFile = Join-Path $dataDir ("inventory-$timestamp.json")
$gzipFile = Join-Path $dataDir 'inventory.json.gz'

$drivePath = $Drive.Trim()
if ($drivePath.Length -eq 2 -and $drivePath[1] -eq ':') { $drivePath += '\\' }

$question = "Escanear la unidad $drivePath con el filtro '$ContentFilter'?"
$choice = Show-YesNoQuestion -Message $question -Title 'Iniciar escaneo'
if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
  Show-Info -Message 'Operación cancelada por el usuario.' -Title 'Cancelado'
  return
}

try {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'hash-drive-to-csv.ps1') `
    -Drive $drivePath -OutCsv $csvFile -ContentFilter $ContentFilter
  if ($LASTEXITCODE -ne 0) { throw "hash-drive-to-csv.ps1 devolvió código $LASTEXITCODE" }

  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'csv-to-inventory-json.ps1') `
    -CsvPath $csvFile -JsonPath $jsonFile
  if ($LASTEXITCODE -ne 0) { throw "csv-to-inventory-json.ps1 devolvió código $LASTEXITCODE" }

  & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'minify-and-gzip-inventory.ps1') `
    -DataDir $dataDir -Source (Split-Path -Leaf $jsonFile)
  if ($LASTEXITCODE -ne 0) { throw "minify-and-gzip-inventory.ps1 devolvió código $LASTEXITCODE" }
} catch {
  Show-ErrorDialog -Message ("Falló la generación del inventario: {0}" -f $_.Exception.Message) -Title 'Proceso interrumpido'
  throw
}

$publishQuestion = 'Inventario generado correctamente. ¿Publicar cambios en GitHub?'
$publishChoice = Show-YesNoQuestion -Message $publishQuestion -Title 'Publicar inventario'
if ($publishChoice -ne [System.Windows.Forms.DialogResult]::Yes) {
  Show-Info -Message 'Inventario generado localmente. Publicación omitida.' -Title 'Proceso finalizado'
  return
}

Push-Location $repoRoot
try {
  & git add -- "data/inventory.json.gz"
  if ($LASTEXITCODE -ne 0) { throw "git add falló con código $LASTEXITCODE" }

  $commitMessage = "auto: update inventory $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  $commitOutput = & git commit -m $commitMessage 2>&1
  if ($LASTEXITCODE -ne 0) {
    if ($commitOutput -match 'nothing to commit') {
      Show-Info -Message 'No hay cambios que publicar.' -Title 'Sin cambios'
      return
    }
    throw "git commit falló con código $LASTEXITCODE: $commitOutput"
  }

  & git push
  if ($LASTEXITCODE -ne 0) { throw "git push falló con código $LASTEXITCODE" }

  Show-Info -Message 'Inventario publicado en GitHub correctamente.' -Title 'Éxito'
} catch {
  Show-ErrorDialog -Message ("No se pudo publicar el inventario: {0}" -f $_.Exception.Message) -Title 'Error al publicar'
  throw
} finally {
  Pop-Location
}
