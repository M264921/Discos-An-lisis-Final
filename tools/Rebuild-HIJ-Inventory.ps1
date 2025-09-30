[CmdletBinding()]
param(
    [string[]]$Drives = @('H','I','J'),
    [string]$RepoRoot,
    [string]$PythonPath,
    [switch]$SkipInteractive,
    [switch]$SkipDuplicatesHtml
)

<#!
.SYNOPSIS
Recalcula el inventario HIJ y regenera los listados interactivos.

.DESCRIPTION
Escanea las unidades indicadas (por defecto H:, I: y J:), calcula hashes SHA256
por archivo y genera los ficheros clave del proyecto:

- index_by_hash.csv
- inventory_by_folder.csv
- dupes_confirmed.csv
- Listado_*.html interactivos
- Listado_Duplicados_interactivo.html (vía generate_duplicates_table.py)

Además guarda un log detallado bajo logs_YYYYMMDD_HHMMSS\rebuild.log para
trazabilidad.

.PARAMETER Drives
Letras de las unidades que se deben procesar.

.PARAMETER RepoRoot
Ruta al repositorio. Si no se indica se asume la carpeta raíz del script.

.PARAMETER PythonPath
Ruta explícita a python.exe (si no está en PATH o hay varias versiones).

.PARAMETER SkipInteractive
Evita reconstruir los listados Listado_*.html por disco.

.PARAMETER SkipDuplicatesHtml
Salta la generación de Listado_Duplicados_interactivo.html (solo deja el CSV).

.EXAMPLE
pwsh ./tools/Rebuild-HIJ-Inventory.ps1

.EXAMPLE
pwsh ./tools/Rebuild-HIJ-Inventory.ps1 -Drives H,J -SkipInteractive

.NOTES
Necesita permisos de lectura sobre las unidades y puede tardar varios minutos
según el tamaño de los discos.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $scriptRoot
}
$RepoRoot = (Resolve-Path -Path $RepoRoot).Path

$culture = [System.Globalization.CultureInfo]::GetCultureInfo('es-ES')
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = Join-Path $RepoRoot "logs_$timestamp"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir 'rebuild.log'

function Write-Log {
    param(
        [string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Cyan
    )
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line -ForegroundColor $Color
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory = $RepoRoot,
        [string]$Description = 'Ejecutando comando'
    )
    Write-Log -Message ("{0}: {1} {2}" -f $Description, $FilePath, ($Arguments -join ' ')) -Color Yellow
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    if ($Arguments) {
        foreach ($arg in $Arguments) {
            [void]$psi.ArgumentList.Add($arg)
        }
    }
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($stdout) {
        Add-Content -Path $logFile -Value $stdout.TrimEnd()
        Write-Host $stdout
    }
    if ($stderr) {
        Add-Content -Path $logFile -Value $stderr.TrimEnd()
        Write-Host $stderr -ForegroundColor Red
    }
    if ($process.ExitCode -ne 0) {
        throw "El comando '$FilePath' terminó con código $($process.ExitCode)"
    }
}

function Escape-CsvField {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    $escaped = $Value.Replace('"', '""')
    return '"' + $escaped + '"'
}

function Format-Megabytes {
    param([double]$Value)
    if ($Value -lt 0.005) { return '0' }
    $formatted = [string]::Format($culture, '{0:N2}', $Value)
    return $formatted
}

function Format-Timestamp {
    param([datetime]$Value)
    return $Value.ToString('dd/MM/yyyy HH:mm:ss', $culture)
}

$indexPath = Join-Path $RepoRoot 'index_by_hash.csv'
$inventoryPath = Join-Path $RepoRoot 'inventory_by_folder.csv'
$dupesPath = Join-Path $RepoRoot 'dupes_confirmed.csv'

$indexWriter = [System.IO.StreamWriter]::new($indexPath, $false, [System.Text.UTF8Encoding]::new($true))
$inventoryWriter = [System.IO.StreamWriter]::new($inventoryPath, $false, [System.Text.UTF8Encoding]::new($true))
try {
    $indexWriter.WriteLine('"Hash","Path","Drive","Extension","Length","MB","LastWrite"')
    $inventoryWriter.WriteLine('Drive,Folder,Name,Extension,Length,MB,LastWrite,FullPath')
} finally {
    $indexWriter.Flush()
    $inventoryWriter.Flush()
}

$hashGroups = [System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[psobject]]]::new()
$totalFiles = 0
$totalBytes = [int64]0
$scannedDrives = @()

try {
    foreach ($drive in $Drives) {
        $root = "$drive:\\"
        if (-not (Test-Path -LiteralPath $root)) {
            Write-Log -Message "Disco $drive: no disponible, se omite." -Color DarkYellow
            continue
        }
        $scannedDrives += $drive
        Write-Log -Message "Disco $drive: escaneando archivos..." -Color Green
        Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
            $item = $_
            $hash = $null
            try {
                $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
            } catch {
                Write-Log -Message "Hash fallido: $($item.FullName) - $_" -Color Red
            }
            if ($hash) {
                $ext = if ($item.Extension) { $item.Extension.ToLowerInvariant() } else { '(sin)' }
                $folder = $item.DirectoryName
                $length = [int64]$item.Length
                $mbValue = [math]::Round($length / 1MB, 2)
                $mb = Format-Megabytes -Value $mbValue
                $lastWrite = Format-Timestamp -Value $item.LastWriteTime
                $pathCsv = Escape-CsvField -Value $item.FullName
                $hashCsv = Escape-CsvField -Value $hash
                $driveCsv = Escape-CsvField -Value $drive
                $extCsv = Escape-CsvField -Value $ext
                $lengthCsv = Escape-CsvField -Value ([string]$length)
                $mbCsv = Escape-CsvField -Value $mb
                $lastCsv = Escape-CsvField -Value $lastWrite

                $indexWriter.WriteLine("$hashCsv,$pathCsv,$driveCsv,$extCsv,$lengthCsv,$mbCsv,$lastCsv")

                $inventoryFields = @(
                    Escape-CsvField -Value $drive,
                    Escape-CsvField -Value $folder,
                    Escape-CsvField -Value $item.Name,
                    Escape-CsvField -Value $ext,
                    Escape-CsvField -Value ([string]$length),
                    Escape-CsvField -Value $mb,
                    Escape-CsvField -Value $lastWrite,
                    Escape-CsvField -Value $item.FullName
                )
                $inventoryWriter.WriteLine(($inventoryFields -join ','))

                if (-not $hashGroups.ContainsKey($hash)) {
                    $hashGroups[$hash] = [System.Collections.Generic.List[psobject]]::new()
                }
                $hashGroups[$hash].Add([pscustomobject]@{
                    Path = $item.FullName
                    Bytes = $length
                    LastWrite = $item.LastWriteTime
                })

                $totalFiles++
                $totalBytes += $length
            }
        }
    }
} finally {
    $indexWriter.Dispose()
    $inventoryWriter.Dispose()
}

Write-Log -Message "Total archivos: $totalFiles" -Color Green
Write-Log -Message ("Tamaño agregado: {0:N0} bytes" -f $totalBytes) -Color Green
Write-Log -Message "Inventario CSV: $indexPath" -Color Gray
Write-Log -Message "Detalle carpeta: $inventoryPath" -Color Gray

$dupesWriter = [System.IO.StreamWriter]::new($dupesPath, $false, [System.Text.UTF8Encoding]::new($true))
try {
    $dupesWriter.WriteLine('Hash,SHA256,Bytes,LastWrite,Path')
    $dupeGroups = 0
    $dupeFiles = 0
    $dupeBytes = [int64]0
    foreach ($entry in $hashGroups.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | Sort-Object { $_.Value.Count } -Descending) {
        $sha = $entry.Key
        $records = $entry.Value | Sort-Object Path
        $groupBytes = ($records | Measure-Object Bytes -Sum).Sum
        foreach ($record in $records) {
            $line = (
                '{0},{1},{2},"{3}","{4}"' -f `
                    $sha,
                    $sha,
                    $record.Bytes,
                    (Format-Timestamp -Value $record.LastWrite),
                    ($record.Path -replace '"','""')
            )
            $dupesWriter.WriteLine($line)
        }
        $dupeGroups++
        $dupeFiles += $records.Count
        $dupeBytes += [int64]$groupBytes
    }
    if ($dupeGroups -gt 0) {
        Write-Log -Message "Grupos de duplicados: $dupeGroups (registros: $dupeFiles, bytes: $dupeBytes)" -Color Green
    } else {
        Write-Log -Message 'No se detectaron duplicados.' -Color Green
    }
} finally {
    $dupesWriter.Dispose()
}
Write-Log -Message "Duplicados CSV: $dupesPath" -Color Gray

if (-not $SkipDuplicatesHtml.IsPresent) {
    if (-not $PythonPath) {
        $PythonPath = (Get-Command python -ErrorAction Stop).Source
    }
    $pyScript = Join-Path $scriptRoot 'generate_duplicates_table.py'
    Invoke-External -FilePath $PythonPath -Arguments @($pyScript) -Description 'Generando Listado_Duplicados_interactivo.html'
    $dupesHtml = Join-Path $RepoRoot 'Listado_Duplicados_interactivo.html'
    Write-Log -Message "HTML duplicados: $dupesHtml" -Color Gray
}

if (-not $SkipInteractive.IsPresent) {
    $treeScript = Join-Path $RepoRoot 'Listado_H_interactivo.ps1'
    if (Test-Path -LiteralPath $treeScript) {
        foreach ($drive in $scannedDrives) {
            $outputHtml = Join-Path $RepoRoot ("Listado_{0}_interactivo.html" -f $drive)
            Write-Log -Message "Generando árbol interactivo para $drive:" -Color Green
            & $treeScript -Root "$drive:\" -OutputHtml $outputHtml | Out-Null
            Write-Log -Message "Árbol actualizado: $outputHtml" -Color Gray
        }
    } else {
        Write-Log -Message 'No se encontró Listado_H_interactivo.ps1; se omite la generación de árboles.' -Color DarkYellow
    }
}

Write-Log -Message "Inventario completado. Log: $logFile" -Color Cyan
