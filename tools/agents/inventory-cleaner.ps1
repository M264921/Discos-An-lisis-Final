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
    & $Sweep -RepoRoot "$RepoRoot" -Mode "$SweepMode" 2>&1 | Tee-Object -FilePath $LogFile -Append
  } else {
    Log "SKIP: tools/agents/repo-sweep.ps1 no encontrado"
  }
}

$PyRemove = Join-Path $RepoRoot "tools/remove_nonmedia_duplicates.py"
$MoveDupes = Join-Path $RepoRoot "tools/Move-I-Duplicates.ps1"
$BuildHash = Join-Path $RepoRoot "tools/build-hash-data.ps1"
$MakeInv = Join-Path $RepoRoot "tools/make_inventory_offline.ps1"
if (-not (Test-Path $MakeInv)) {
  $MakeInv = Join-Path $RepoRoot "make_inventory_offline.ps1"
}
$Wrapper = Join-Path $RepoRoot "tools/agents/make-inventory-offline-wrapper.ps1"
$Normalizer = Join-Path $RepoRoot "tools/normalize-inventory-html.ps1"
$Sanitizer = Join-Path $RepoRoot "tools/sanitize-inventory-html.ps1"
$DupesExplorer = Join-Path $RepoRoot "tools/generate_duplicates_table.py"

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
  $targetDrive = 'I:\'
  if (Test-Path -LiteralPath $targetDrive) {
    Log "Running Move-I-Duplicates.ps1 ..."
    & $MoveDupes -CsvPath "$DupesCsvPath" 2>&1 | Tee-Object -FilePath $LogFile -Append
  } else {
    Log "SKIP: unidad I:\ no disponible; se omite Move-I-Duplicates.ps1"
  }
} else {
  Log "SKIP: falta Move-I-Duplicates.ps1 o $DupesCsvPath"
}

$hashDataPath = Join-Path $OutputDirPath "hash_data.csv"
if (Test-Path $BuildHash) {
  Log "Regenerando docs/hash_data.csv ..."
  & $BuildHash -RepoRoot "$RepoRoot" -IndexPath "index_by_hash.csv" -OutputCsv "$hashDataPath" 2>&1 | Tee-Object -FilePath $LogFile -Append
  if (Test-Path $hashDataPath) {
    Log "OK: hash_data.csv actualizado"
  } else {
    Log "WARN: build-hash-data.ps1 no produjo $hashDataPath"
  }
} else {
  Log "SKIP: tools/build-hash-data.ps1 no encontrado"
}

$ExpectedHtml = Join-Path $OutputDirPath "inventario_interactivo_offline.html"
$csvDefault = Join-Path $RepoRoot "docs/hash_data.csv"

$htmlGenerado = $false
if (Test-Path $MakeInv) {
  Log "Generando inventario base con make_inventory_offline.ps1 ..."
  try {
    & $MakeInv -RepoRoot "$RepoRoot" -Output "$ExpectedHtml" 2>&1 | Tee-Object -FilePath $LogFile -Append
  } catch {
    Log ("ERROR: make_inventory_offline.ps1 fallo: {0}" -f $_.Exception.Message)
  }
  if (Test-Path $ExpectedHtml) {
    $htmlGenerado = $true
  } else {
    Log "WARN: make_inventory_offline.ps1 no produjo $ExpectedHtml"
  }
} else {
  Log "ERROR: no se encontro make_inventory_offline.ps1"
}

if ($htmlGenerado -and (Test-Path $Wrapper)) {
  Log "Post-procesando inventario (wrapper)..."
  & $Wrapper `
    -RepoRoot "$RepoRoot" `
    -HtmlPath "$ExpectedHtml" `
    -CsvFallback "$csvDefault" `
    -PreviewRows 50 2>&1 | Tee-Object -FilePath $LogFile -Append
} elseif ($htmlGenerado) {
  Log "Wrapper no encontrado; aplicando normalizacion y sanitizado manual."
  if (Test-Path $Normalizer) {
    Log "Normalizando HTML ..."
    & $Normalizer -HtmlPath "$ExpectedHtml" -PreviewRows 50 2>&1 | Tee-Object -FilePath $LogFile -Append
  } else {
    Log "SKIP: normalizador no encontrado"
  }
  if (Test-Path $Sanitizer) {
    Log "Sanitizando HTML final ..."
    & $Sanitizer -HtmlPath "$ExpectedHtml" 2>&1 | Tee-Object -FilePath $LogFile -Append
  } else {
    Log "SKIP: sanitizer no encontrado"
  }
}

if (Test-Path $ExpectedHtml) {
  Log "OK: HTML generado -> $ExpectedHtml"
} else {
  Log "WARN: No se encontro $ExpectedHtml tras la ejecucion."
}

$dupesHtml = Join-Path $OutputDirPath "Listado_Duplicados_interactivo.html"
if (Test-Path $DupesExplorer) {
  if (-not (Test-Path $DupesCsvPath)) {
    Log "SKIP: dupes_confirmed.csv no encontrado; no se genera Listado_Duplicados_interactivo.html"
  } elseif ($pythonExe) {
    Log "Generando Listado_Duplicados_interactivo.html ..."
    & $pythonExe "$DupesExplorer" --source "$DupesCsvPath" --target "$dupesHtml" 2>&1 | Tee-Object -FilePath $LogFile -Append
    if (Test-Path $dupesHtml) {
      Log "OK: Listado_Duplicados_interactivo.html actualizado"
    } else {
      Log "WARN: No se encontro $dupesHtml tras ejecutar generate_duplicates_table.py"
    }
  } else {
    Log "WARN: Python no detectado; se omite generate_duplicates_table.py"
  }
} else {
  Log "SKIP: tools/generate_duplicates_table.py no encontrado"
}

Log "== Inventory-Cleaner DONE =="
