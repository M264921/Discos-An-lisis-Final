Param(
    [string]$RepoRoot = "$PSScriptRoot/../..",
    [string]$DupesCsv = "dupes_confirmed.csv",
    [string]$LogDir   = "logs",
    [string]$OutputDir= "docs",
    [ValidateSet("None","DryRun","Apply")] [string]$SweepMode = "None"
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path $RepoRoot).Path
Set-Location $RepoRoot

$DupesCsvPath  = Join-Path $RepoRoot $DupesCsv
$LogDirPath    = Join-Path $RepoRoot $LogDir
$OutputDirPath = Join-Path $RepoRoot $OutputDir

New-Item -ItemType Directory -Force -Path $LogDirPath, $OutputDirPath | Out-Null
$Ts = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $LogDirPath "inventory-cleaner-$Ts.log"

function Log($m) {
  $line = "[{0}] {1}" -f (Get-Date -Format "u"), $m
  $line | Tee-Object -FilePath $LogFile -Append
}

Log "== Inventory-Cleaner START =="
Log "RepoRoot: $RepoRoot"
Log "DupesCsv: $DupesCsvPath"
Log "SweepMode: $SweepMode"

if ($SweepMode -ne "None") {
  $Sweep = Join-Path $RepoRoot "tools/agents/repo-sweep.ps1"
  if (Test-Path $Sweep) {
    Log "Running repo-sweep.ps1 ($SweepMode) ..."
    powershell -NoProfile -ExecutionPolicy Bypass -File "$Sweep" -RepoRoot "$RepoRoot" -Mode "$SweepMode" 2>&1 | Tee-Object -FilePath $LogFile -Append
  } else {
    Log "SKIP: tools/agents/repo-sweep.ps1 no encontrado"
  }
}

$PyRemove = Join-Path $RepoRoot "tools/remove_nonmedia_duplicates.py"
$MoveDupes = Join-Path $RepoRoot "tools/Move-I-Duplicates.ps1"
$MakeInv = Join-Path $RepoRoot "tools/make_inventory_offline.ps1"
if (-not (Test-Path $MakeInv)) {
  $MakeInv = Join-Path $RepoRoot "make_inventory_offline.ps1"
}
$Wrapper = Join-Path $RepoRoot "tools/agents/make-inventory-offline-wrapper.ps1"
$Normalizer = Join-Path $RepoRoot "tools/normalize-inventory-html.ps1"
$Sanitizer = Join-Path $RepoRoot "tools/sanitize-inventory-html.ps1"

$pythonExe = $null
foreach ($cand in @("python","py","python3")) {
  try {
    $v = & $cand --version 2>$null
    if ($LASTEXITCODE -eq 0) {
      $pythonExe = $cand
      break
    }
  } catch {}
}

if (Test-Path $PyRemove) {
  Log "Running remove_nonmedia_duplicates.py ..."
  if ($pythonExe) {
    & $pythonExe "$PyRemove" --csv "$DupesCsvPath" 2>&1 | Tee-Object -FilePath $LogFile -Append
  } else {
    Log "WARN: Python no detectado; se omite remove_nonmedia_duplicates.py"
  }
} else {
  Log "SKIP: tools/remove_nonmedia_duplicates.py no encontrado"
}

if ((Test-Path $MoveDupes) -and (Test-Path $DupesCsvPath)) {
  Log "Running Move-I-Duplicates.ps1 ..."
  & $MoveDupes -CsvPath "$DupesCsvPath" 2>&1 | Tee-Object -FilePath $LogFile -Append
} else {
  Log "SKIP: falta Move-I-Duplicates.ps1 o $DupesCsvPath"
}

$ExpectedHtml = Join-Path $OutputDirPath "inventario_interactivo_offline.html"
$csvDefault = Join-Path $RepoRoot "docs/hash_data.csv"

if (Test-Path $Wrapper) {
  Log "Running make-inventory-offline-wrapper.ps1 ..."
  & $Wrapper -RepoRoot "$RepoRoot" -CsvPath "$csvDefault" -OutputHtml "$ExpectedHtml" 2>&1 | Tee-Object -FilePath $LogFile -Append
} elseif (Test-Path $MakeInv) {
  Log "Running make_inventory_offline.ps1 ..."
  & $MakeInv -Output "$ExpectedHtml" 2>&1 | Tee-Object -FilePath $LogFile -Append
  if (Test-Path $Normalizer) {
    Log "Normalizando bloque setData ..."
    & $Normalizer -HtmlPath "$ExpectedHtml" 2>&1 | Tee-Object -FilePath $LogFile -Append
  }
} else {
  Log "SKIP: no se encontro make_inventory_offline.ps1"
}

if (Test-Path $Sanitizer) {
  Log "Sanitizando HTML final ..."
  & $Sanitizer -HtmlPath "$ExpectedHtml" 2>&1 | Tee-Object -FilePath $LogFile -Append
} else {
  Log "SKIP: sanitizer no encontrado"
}

if (Test-Path $ExpectedHtml) {
  Log "OK: HTML generado -> $ExpectedHtml"
} else {
  Log "WARN: No se encontro $ExpectedHtml tras la ejecucion."
}

Log "== Inventory-Cleaner DONE =="
