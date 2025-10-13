<# tools\run-inventory-wizard.ps1
    Asistente:
      1) Elegir modo (Auto / Hash / Quick)
      2) Seleccionar unidades y/o carpetas
      3) Ejecutar tools\test-drive.ps1 por cada selección (sin abrir visor)
      4) Ejecutar tools\merge-and-embed.ps1
      5) Abrir HTML resultante
#>

[CmdletBinding()]
param(
  [string]$Html     = ".\docs\inventario_pro_offline.html",
  [string]$ScansDir = ".\docs\inventory"
)

$ErrorActionPreference = 'Stop'

# ---------------- Re-lanzar en STA para WinForms (y mantener parámetros) ----------------
if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
  $hostExe = try { (Get-Process -Id $PID).Path } catch { $null }
  if (-not $hostExe) {
    $hostExe = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
    if (-not $hostExe -or -not (Test-Path $hostExe)) {
      $hostExe = (Get-Command powershell).Source
    }
  }

  $argList = @('-NoLogo', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
  foreach ($kv in $PSBoundParameters.GetEnumerator()) {
    $argList += @("-$($kv.Key)", "$($kv.Value)")
  }

  Start-Process -FilePath $hostExe -ArgumentList $argList -STA | Out-Null
  return
}

# ---------------- Solo Windows ----------------
if (-not $IsWindows) {
  throw 'Este asistente requiere Windows (WinForms).'
}

# ---------------- Consola UTF-8 en PowerShell 5.1 ----------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
  try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
}

# ---------------- Rutas robustas ----------------
$self = $MyInvocation.MyCommand.Path
if (-not $self) {
  throw 'No puedo resolver la ruta de este script.'
}

$toolsDir = Split-Path -Path $self -Parent
$repoDir  = Split-Path -Path $toolsDir -Parent

$testDrive = Join-Path -Path $toolsDir -ChildPath 'test-drive.ps1'
$merge     = Join-Path -Path $toolsDir -ChildPath 'merge-and-embed.ps1'
if (-not (Test-Path -LiteralPath $testDrive)) {
  throw "No encuentro $testDrive"
}
if (-not (Test-Path -LiteralPath $merge)) {
  throw "No encuentro $merge"
}

$Html     = Join-Path -Path $repoDir -ChildPath $Html
$ScansDir = Join-Path -Path $repoDir -ChildPath $ScansDir

$null = New-Item -ItemType Directory -Force -Path (Split-Path -LiteralPath $Html -Parent)
$null = New-Item -ItemType Directory -Force -Path $ScansDir

Write-Host "↓ repo:  $repoDir"
Write-Host "↓ tools: $toolsDir"
Write-Host "↓ html:  $Html"
Write-Host "↓ scans: $ScansDir"

# ---------------- UI helpers ----------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-DriveCandidates {
  $drives = Get-PSDrive -PSProvider FileSystem |
    Where-Object { $_.Root -match '^[A-Za-z]:\\$' } |
    Sort-Object Root
  foreach ($d in $drives) {
    $letter = $d.Root.Substring(0, 1).ToUpper()
    $vol = $null
    try { $vol = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue } catch {}
    [pscustomobject]@{
      Drive  = "${letter}:"
      Label  = $vol.FileSystemLabel
      SizeGB = if ($vol) { [math]::Round($vol.Size / 1GB, 1) } else { $null }
      FreeGB = if ($vol) { [math]::Round($vol.SizeRemaining / 1GB, 1) } else { $null }
      Root   = "${letter}:\"
    }
  }
}

function Show-ModeDialog {
  $form = New-Object Windows.Forms.Form
  $form.Text = 'Modo de escaneo'
  $form.StartPosition = 'CenterScreen'
  $form.Size = New-Object Drawing.Size(460, 200)
  $form.TopMost = $true

  $rbAuto = New-Object Windows.Forms.RadioButton
  $rbHash = New-Object Windows.Forms.RadioButton
  $rbQuick = New-Object Windows.Forms.RadioButton
  $rbAuto.Text = 'AUTO (incremental: calcula hash solo si falta)'
  $rbHash.Text = 'HASH completo (forzar hash)'
  $rbQuick.Text = 'QUICK (rápido, sin hash)'
  $rbAuto.Location = '10,15'; $rbAuto.AutoSize = $true; $rbAuto.Checked = $true
  $rbHash.Location = '10,45'; $rbHash.AutoSize = $true
  $rbQuick.Location = '10,75'; $rbQuick.AutoSize = $true

  $ok = New-Object Windows.Forms.Button
  $ok.Text = 'OK'
  $ok.Anchor = 'Bottom,Right'
  $ok.Location = '340,120'
  $ok.Add_Click({
    $form.DialogResult = 'OK'
    $form.Close()
  })

  $form.Controls.AddRange(@($rbAuto, $rbHash, $rbQuick, $ok))
  [void]$form.ShowDialog()

  if ($rbHash.Checked) { return 'Hash' }
  if ($rbQuick.Checked) { return 'Quick' }
  'Auto'
}

function Show-DriveFolderPicker {
  $form = New-Object Windows.Forms.Form
  $form.Text = 'Selecciona unidades / carpetas'
  $form.StartPosition = 'CenterScreen'
  $form.Size = New-Object Drawing.Size(780, 460)
  $form.TopMost = $true

  $lv = New-Object Windows.Forms.ListView
  $lv.View = 'Details'
  $lv.CheckBoxes = $true
  $lv.FullRowSelect = $true
  $lv.GridLines = $true
  $lv.Location = '10,10'
  $lv.Size = New-Object Drawing.Size(745, 360)
  [void]$lv.Columns.Add('Tipo', 80)
  [void]$lv.Columns.Add('Unidad/Carpeta', 300)
  [void]$lv.Columns.Add('Etiqueta', 120)
  [void]$lv.Columns.Add('Tamaño', 110)
  [void]$lv.Columns.Add('Libre', 110)

  foreach ($d in Get-DriveCandidates) {
    $row = New-Object Windows.Forms.ListViewItem('Disco')
    [void]$row.SubItems.Add($d.Drive)
    [void]$row.SubItems.Add($d.Label)
    [void]$row.SubItems.Add((if ($d.SizeGB) { "$($d.SizeGB) GB" } else { '' }))
    [void]$row.SubItems.Add((if ($d.FreeGB) { "$($d.FreeGB) GB" } else { '' }))
    $row.Tag = [pscustomobject]@{
      Kind    = 'Drive'
      Path    = $d.Root
      Display = $d.Drive
    }
    [void]$lv.Items.Add($row)
  }

  $btnAdd = New-Object Windows.Forms.Button
  $btnAdd.Text = 'Añadir carpeta…'
  $btnAdd.Location = '10,380'
  $btnAdd.Add_Click({
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Elige carpeta a analizar'
    if ($dlg.ShowDialog() -eq 'OK') {
      $p = $dlg.SelectedPath
      $row = New-Object Windows.Forms.ListViewItem('Carpeta')
      [void]$row.SubItems.Add($p)
      [void]$row.SubItems.Add('')
      [void]$row.SubItems.Add('')
      [void]$row.SubItems.Add('')
      $row.Tag = [pscustomobject]@{
        Kind    = 'Folder'
        Path    = $p
        Display = $p
      }
      $row.Checked = $true
      [void]$lv.Items.Add($row)
    }
  })

  $ok = New-Object Windows.Forms.Button
  $ok.Text = 'OK'
  $ok.Anchor = 'Bottom,Right'
  $ok.Location = '655,380'
  $ok.Add_Click({
    $form.DialogResult = 'OK'
    $form.Close()
  })

  $form.Controls.AddRange(@($lv, $btnAdd, $ok))
  [void]$form.ShowDialog()

  $selected = @()
  foreach ($it in $lv.Items) {
    if ($it.Checked) {
      $selected += $it.Tag
    }
  }

  $selected
}

# ---------------- Ejecución ----------------
$mode = Show-ModeDialog
if (-not $mode) {
  Write-Host 'Cancelado'
  return
}

$targets = Show-DriveFolderPicker
if (-not $targets -or $targets.Count -eq 0) {
  Write-Host 'No se seleccionó nada. Saliendo.'
  return
}

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwsh) {
  $pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
}
if (-not (Test-Path $pwsh)) {
  $pwsh = (Get-Command powershell).Source
}

Write-Host "== Escaneando en modo: $mode ==" -ForegroundColor Cyan

$N = $targets.Count
$idx = 0
foreach ($t in $targets) {
  $idx++
  $label = $t.Display
  $pct = [int](($idx - 1) * 100 / $N)
  Write-Progress -Activity "Inventario: escaneando ($mode)" -Status "Preparando $label" -PercentComplete $pct

  Write-Progress -Id 2 -Activity "Escaneando $label" -Status 'Lanzando test-drive.ps1' -PercentComplete 5

  $args = @(
    '-NoLogo', '-ExecutionPolicy', 'Bypass',
    '-File', $testDrive,
    '-Mode', $mode,
    '-NoOpen',
    '-Path', $t.Path
  )

  Write-Progress -Id 2 -Activity "Escaneando $label" -Status 'Trabajando...' -PercentComplete 25
  & $pwsh @args
  Write-Progress -Id 2 -Activity "Escaneando $label" -Status 'Finalizando...' -PercentComplete 90
  Start-Sleep -Milliseconds 200
  Write-Progress -Id 2 -Completed -Activity "Escaneando $label"
}

Write-Progress -Activity 'Inventario: fusionando y embebiendo' -Status 'merge-and-embed' -PercentComplete 50
& $pwsh -NoLogo -ExecutionPolicy Bypass -File $merge
Write-Progress -Activity 'Inventario: fusionando y embebiendo' -Completed

if (Test-Path -LiteralPath $Html) {
  Write-Host '[OK] Terminado. Abriendo visor...' -ForegroundColor Green
  Start-Process $Html
} else {
  Write-Warning "Terminado, pero no se encontró el HTML esperado: $Html"
}
