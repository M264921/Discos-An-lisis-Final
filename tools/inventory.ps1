param(
  [ValidateSet("quick","interactive","auto","gui")]
  [string]$Mode = "quick",
  [string[]]$Drives = @("K:\"),
  [int]$MaxFiles = 3000
)

$PSDefaultParameterValues["*:ErrorAction"] = "Stop"

function Run-Quick {
  $p = Join-Path $PSScriptRoot "quick-scan.ps1"
  if (-not (Test-Path $p)) { throw "No existe $p. Ejecuta primero el paso que crea quick-scan.ps1." }
  pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Drives $Drives -MaxFiles $MaxFiles -MediaOnly
}

function Run-Interactive {
  $p = Join-Path $PSScriptRoot "scan-drives-interactive.ps1"
  if (-not (Test-Path $p)) { throw "No existe $p (scan-drives-interactive.ps1)." }
  pwsh -NoProfile -ExecutionPolicy Bypass -File $p
}

function Run-Auto {
  $p = Join-Path $PSScriptRoot "run-inventory-auto.ps1"
  if (-not (Test-Path $p)) { throw "No existe $p (run-inventory-auto.ps1)." }
  pwsh -NoProfile -ExecutionPolicy Bypass -File $p
}

function Run-Gui {
  $py = Join-Path $PSScriptRoot "montana_inventory_gui.py"
  if (-not (Test-Path $py)) { throw "No existe $py (montana_inventory_gui.py)." }
  if (-not (Test-Path (Join-Path $PSScriptRoot "..\.venv\Scripts\python.exe"))) {
    Write-Host "⚠️ No se detecta .venv\Scripts\python.exe; se usará 'python' del sistema."
    python $py
  } else {
    & (Join-Path $PSScriptRoot "..\.venv\Scripts\python.exe") $py
  }
}

switch ($Mode) {
  "quick"       { Run-Quick }
  "interactive" { Run-Interactive }
  "auto"        { Run-Auto }
  "gui"         { Run-Gui }
  default       { throw "Modo desconocido: $Mode" }
}
Write-Host "✅ inventory.ps1 ($Mode) finalizado."
