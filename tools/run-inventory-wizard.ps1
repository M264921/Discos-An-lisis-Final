<<<<<<< Updated upstream
<# tools\run-inventory-wizard.ps1 #>
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    $self = $PSCommandPath
    if (-not $self) { $self = $MyInvocation.MyCommand.Path }
    if (-not $self) { throw "No puedo resolver la ruta del propio script." }

    $toolsDir = Split-Path $self
    $repoDir  = Split-Path $toolsDir
    return (Resolve-Path $repoDir).Path
}

function Pick-Drives {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $drvs = Get-PSDrive -PSProvider FileSystem |
          Where-Object { $_.Root -match '^[A-Za-z]:\\$' } |
          Sort-Object Root
  $form = New-Object Windows.Forms.Form
  $form.Text = "Selecciona unidades a analizar"
  $form.Width = 420; $form.Height = 420; $form.TopMost = $true
  $list = New-Object Windows.Forms.CheckedListBox
  $list.Dock = 'Top'; $list.Height = 300
  foreach($d in $drvs){ [void]$list.Items.Add($d.Root.TrimEnd('\')) }
  $ok = New-Object Windows.Forms.Button
  $ok.Text = "OK"; $ok.Dock='Bottom'
  $form.Controls.Add($list); $form.Controls.Add($ok)
  $sel = @()
  $ok.Add_Click({ $script:sel = @($list.CheckedItems); $form.Close() })
  [void]$form.ShowDialog()
  return @($sel)
}

function Pick-Folders {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $picked = @()
  while($true){
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Elige una carpeta (Cancelar para terminar)"
    if($dlg.ShowDialog() -eq 'OK'){ $picked += $dlg.SelectedPath } else { break }
  }
  return $picked
}

function Pick-Mode {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $form = New-Object Windows.Forms.Form
  $form.Text = "Modo de escaneo"; $form.Width=360; $form.Height=200; $form.TopMost=$true
  $rb1 = New-Object Windows.Forms.RadioButton; $rb1.Text="Auto (incremental)"; $rb1.Checked=$true; $rb1.Top=20; $rb1.Left=20
  $rb2 = New-Object Windows.Forms.RadioButton; $rb2.Text="Hash completo";   $rb2.Top=50; $rb2.Left=20
  $rb3 = New-Object Windows.Forms.RadioButton; $rb3.Text="Sin hash (rápido)";$rb3.Top=80; $rb3.Left=20
  $ok  = New-Object Windows.Forms.Button; $ok.Text="OK"; $ok.Top=120; $ok.Left=20
  $form.Controls.AddRange(@($rb1,$rb2,$rb3,$ok))
  $mode='Auto'
  $ok.Add_Click({
    if($rb2.Checked){ $script:mode='Hash' }
    elseif($rb3.Checked){ $script:mode='Quick' }
    else { $script:mode='Auto' }
    $form.Close()
  })
  [void]$form.ShowDialog()
  return $mode
}

# ---------- Rutas requeridas ----------
$repo  = Resolve-RepoRoot
$tools = Join-Path $repo 'tools'
$test  = Join-Path $tools 'test-drive.ps1'
$merge = Join-Path $tools 'merge-and-embed.ps1'
if(!(Test-Path $test)){  throw "No encuentro $test"  }
if(!(Test-Path $merge)){ throw "No encuentro $merge" }

# ---------- Selecciones ----------
$targets = @()
$targets += Pick-Drives          # ej. "C:" "D:"
$targets += Pick-Folders         # cero o más carpetas
if(-not $targets){ Write-Host "Nada seleccionado. Saliendo..." -ForegroundColor Yellow; exit }

$mode = Pick-Mode

# ---------- Ejecuta por cada destino (acumulativo) ----------
foreach($t in $targets){
  Write-Host "=== Escaneando $t ($mode) ===" -ForegroundColor Cyan
  pwsh -NoLogo -ExecutionPolicy Bypass -File $test -Path $t -Mode $mode -NoOpen
}

# ---------- Unifica y abre HTML ----------
& $merge
=======
﻿<# tools\run-inventory-wizard.ps1
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
        # Fallback razonable
        $hostExe = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
        if (-not $hostExe -or -not (Test-Path $hostExe)) {
            $hostExe = (Get-Command powershell).Source
        }
    }

    # Reconstruir argumentos con los parámetros vinculados
    $argList = @('-NoLogo','-ExecutionPolicy','Bypass','-File', $PSCommandPath)
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        $argList += @("-$($kv.Key)", "$($kv.Value)")
    }

    Start-Process -FilePath $hostExe -ArgumentList $argList -STA | Out-Null
    return
}

# ---------------- Solo Windows ----------------
if (-not $IsWindows) { throw "Este asistente requiere Windows (WinForms)." }

# ---------------- Consola UTF-8 en PowerShell 5.1 ----------------
if ($PSVersionTable.PSVersion.Major -lt 7) {
    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}
}

# ---------------- Rutas robustas ----------------
$self = $MyInvocation.MyCommand.Path
if (-not $self) { throw "No puedo resolver la ruta de este script." }

$toolsDir = Split-Path -Path $self -Parent
$repoDir  = Split-Path -Path $toolsDir -Parent

$testDrive = Join-Path -Path $toolsDir -ChildPath 'test-drive.ps1'
$merge     = Join-Path -Path $toolsDir -ChildPath 'merge-and-embed.ps1'
if (-not (Test-Path -LiteralPath $testDrive)) { throw "No encuentro $testDrive" }
if (-not (Test-Path -LiteralPath $merge))     { throw "No encuentro $merge" }

# NO usar Resolve-Path sobre destinos que aún no existen
$Html     = Join-Path -Path $repoDir -ChildPath $Html
$ScansDir = Join-Path -Path $repoDir -ChildPath $ScansDir

# Asegurar directorios de salida
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
    foreach($d in $drives){
        $letter = $d.Root.Substring(0,1).ToUpper()
        $vol = $null
        try { $vol = Get-Volume -DriveLetter $letter -ErrorAction SilentlyContinue } catch {}
        [pscustomobject]@{
            Drive   = "${letter}:"
            Label   = $vol.FileSystemLabel
            SizeGB  = if($vol){ [math]::Round($vol.Size/1GB,1) } else { $null }
            FreeGB  = if($vol){ [math]::Round($vol.SizeRemaining/1GB,1) } else { $null }
            Root    = "${letter}:\"
        }
    }
}

function Show-ModeDialog {
    $form = New-Object Windows.Forms.Form
    $form.Text = "Modo de escaneo"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object Drawing.Size(460,200)
    $form.TopMost = $true

    $rbAuto  = New-Object Windows.Forms.RadioButton
    $rbHash  = New-Object Windows.Forms.RadioButton
    $rbQuick = New-Object Windows.Forms.RadioButton
    $rbAuto.Text  = "AUTO (incremental: calcula hash solo si falta)"
    $rbHash.Text  = "HASH completo (forzar hash)"
    $rbQuick.Text = "QUICK (rápido, sin hash)"
    $rbAuto.Location  = '10,15';  $rbAuto.AutoSize  = $true;  $rbAuto.Checked = $true
    $rbHash.Location  = '10,45';  $rbHash.AutoSize  = $true
    $rbQuick.Location = '10,75';  $rbQuick.AutoSize = $true

    $ok = New-Object Windows.Forms.Button
    $ok.Text = "OK"; $ok.Anchor = 'Bottom,Right'; $ok.Location = '340,120'
    $ok.Add_Click({ $form.DialogResult = 'OK'; $form.Close() })

    $form.Controls.AddRange(@($rbAuto,$rbHash,$rbQuick,$ok))
    [void]$form.ShowDialog()
    if($rbHash.Checked){ return 'Hash' }
    if($rbQuick.Checked){ return 'Quick' }
    'Auto'
}

function Show-DriveFolderPicker {
    $form = New-Object Windows.Forms.Form
    $form.Text = "Selecciona unidades / carpetas"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object Drawing.Size(780,460)
    $form.TopMost = $true

    $lv = New-Object Windows.Forms.ListView
    $lv.View = 'Details'; $lv.CheckBoxes = $true; $lv.FullRowSelect = $true; $lv.GridLines = $true
    $lv.Location = '10,10'; $lv.Size = New-Object Drawing.Size(745,360)
    [void]$lv.Columns.Add("Tipo",80)
    [void]$lv.Columns.Add("Unidad/Carpeta",300)
    [void]$lv.Columns.Add("Etiqueta",120)
    [void]$lv.Columns.Add("Tamaño",110)
    [void]$lv.Columns.Add("Libre",110)

    foreach($d in Get-DriveCandidates){
        $row = New-Object Windows.Forms.ListViewItem("Disco")
        [void]$row.SubItems.Add($d.Drive)
        [void]$row.SubItems.Add($d.Label)
        [void]$row.SubItems.Add((if($d.SizeGB){ "$($d.SizeGB) GB" } else { "" }))
        [void]$row.SubItems.Add((if($d.FreeGB){ "$($d.FreeGB) GB" } else { "" }))
        $row.Tag = [pscustomobject]@{ Kind='Drive'; Path=$d.Root; Display=$d.Drive }
        [void]$lv.Items.Add($row)
    }

    $btnAdd = New-Object Windows.Forms.Button
    $btnAdd.Text = "Añadir carpeta…"; $btnAdd.Location = '10,380'
    $btnAdd.Add_Click({
        $dlg = New-Object Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Elige carpeta a analizar"
        if($dlg.ShowDialog() -eq 'OK'){
            $p = $dlg.SelectedPath
            $row = New-Object Windows.Forms.ListViewItem("Carpeta")
            [void]$row.SubItems.Add($p)
            [void]$row.SubItems.Add(""); [void]$row.SubItems.Add(""); [void]$row.SubItems.Add("")
            $row.Tag = [pscustomobject]@{ Kind='Folder'; Path=$p; Display=$p }
            $row.Checked = $true
            [void]$lv.Items.Add($row)
        }
    })

    $ok = New-Object Windows.Forms.Button
    $ok.Text = "OK"; $ok.Anchor = 'Bottom,Right'; $ok.Location = '655,380'
    $ok.Add_Click({ $form.DialogResult = 'OK'; $form.Close() })

    $form.Controls.AddRange(@($lv,$btnAdd,$ok))
    [void]$form.ShowDialog()

    $selected = @()
    foreach($it in $lv.Items){ if($it.Checked){ $selected += $it.Tag } }
    $selected
}

# ---------------- Ejecución ----------------
$mode = Show-ModeDialog
if(-not $mode){ Write-Host "Cancelado"; return }

$targets = Show-DriveFolderPicker
if(-not $targets -or $targets.Count -eq 0){ Write-Host "No se seleccionó nada. Saliendo."; return }

# Resolver pwsh/PowerShell para subinvocaciones
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if(-not $pwsh){ $pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe" }
if(-not (Test-Path $pwsh)){ $pwsh = (Get-Command powershell).Source } # fallback PS 5.1

Write-Host "== Escaneando en modo: $mode ==" -ForegroundColor Cyan

$N = $targets.Count
$idx = 0
foreach($t in $targets){
    $idx++
    $label = $t.Display
    $pct   = [int](($idx-1) * 100 / $N)
    Write-Progress -Activity "Inventario: escaneando ($mode)" -Status "Preparando $label" -PercentComplete $pct

    # Progreso por objetivo
    Write-Progress -Id 2 -Activity "Escaneando $label" -Status "Lanzando test-drive.ps1" -PercentComplete 5

    $args = @(
        '-NoLogo','-ExecutionPolicy','Bypass',
        '-File', $testDrive,
        '-Mode', $mode,
        '-NoOpen',
        '-Path', $t.Path
    )

    Write-Progress -Id 2 -Activity "Escaneando $label" -Status "Trabajando..." -PercentComplete 25
    & $pwsh @args
    Write-Progress -Id 2 -Activity "Escaneando $label" -Status "Finalizando..." -PercentComplete 90
    Start-Sleep -Milliseconds 200
    Write-Progress -Id 2 -Completed -Activity "Escaneando $label"
}

Write-Progress -Activity "Inventario: fusionando y embebiendo" -Status "merge-and-embed" -PercentComplete 50
& $pwsh -NoLogo -ExecutionPolicy Bypass -File $merge
Write-Progress -Activity "Inventario: fusionando y embebiendo" -Completed

if (Test-Path -LiteralPath $Html) {
    Write-Host "[OK] Terminado. Abriendo visor..." -ForegroundColor Green
    Start-Process $Html
} else {
    Write-Warning "Terminado, pero no se encontró el HTML esperado: $Html"
}
>>>>>>> Stashed changes
