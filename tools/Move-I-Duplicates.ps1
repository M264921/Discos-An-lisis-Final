<#
    Move-I-Duplicates.ps1
    Moves all duplicate files located on a drive (default I:) based on dupes_confirmed.csv
    into a single quarantine folder on that drive, preserving relative paths.
    Shows live progress and writes a detailed log.
#>

[CmdletBinding()]
param(
    [string]$CsvPath,
    [string]$DriveLetter = 'I',
    [string]$DestinationRoot,
    [switch]$WhatIf,
    [string]$LogPath
)

$DriveLetter = $DriveLetter.ToUpper()

if (-not $CsvPath) {
    $CsvPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'dupes_confirmed.csv'
}

if (-not $DestinationRoot) {
    $DestinationRoot = ('{0}:\\duplicados' -f $DriveLetter)
}

if (-not $LogPath) {
    $LogPath = Join-Path (Split-Path -Parent $PSScriptRoot) ('moved_duplicates_{0}.csv' -f $DriveLetter)
}

if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
    throw "No se encuentra el CSV de duplicados: $CsvPath"
}

function Add-LongPrefix([string]$Path) {
    if ($Path -match '^[A-Za-z]:\\' -and -not $Path.StartsWith('\\?\')) {
        return '\\?\' + $Path
    }
    return $Path
}

function Ensure-Directory([string]$DirPath) {
    if (-not $DirPath) { return }
    if (-not (Test-Path -LiteralPath $DirPath)) {
        $null = New-Item -ItemType Directory -Path $DirPath -Force
    }
}

function Ensure-DirectoryLong([string]$DirPath) {
    if (-not $DirPath) { return }
    $long = Add-LongPrefix $DirPath
    if (-not [System.IO.Directory]::Exists($long)) {
        [System.IO.Directory]::CreateDirectory($long) | Out-Null
    }
}

function Format-Bytes([long]$Bytes) {
    if ($Bytes -le 0) { return '0 B' }
    $units = 'B','KB','MB','GB','TB','PB'
    $idx = [Math]::Floor([Math]::Log($Bytes,1024))
    if ($idx -ge $units.Length) { $idx = $units.Length - 1 }
    $value = $Bytes / [Math]::Pow(1024,$idx)
    if ($value -ge 100) { return '{0:N0} {1}' -f $value,$units[$idx] }
    elseif ($value -ge 10) { return '{0:N1} {1}' -f $value,$units[$idx] }
    else { return '{0:N2} {1}' -f $value,$units[$idx] }
}

function Get-UniqueDestination([string]$Candidate) {
    if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
        return $Candidate
    }
    $dir = Split-Path -Parent $Candidate
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Candidate)
    $ext = [System.IO.Path]::GetExtension($Candidate)
    $counter = 1
    while ($true) {
        $nextName = "{0} (dup{1}){2}" -f $baseName,$counter,$ext
        $nextPath = Join-Path $dir $nextName
        if (-not (Test-Path -LiteralPath $nextPath -PathType Leaf)) {
            return $nextPath
        }
        $counter++
    }
}

Write-Host ''
Write-Host ("Inicio de traslado de duplicados en {0}: {1}" -f $DriveLetter,(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Host ("CSV origen: {0}" -f $CsvPath)
Write-Host ("Carpeta destino: {0}" -f $DestinationRoot)
if ($WhatIf) { Write-Host 'Modo WhatIf: no se moveran archivos' -ForegroundColor Yellow }
Write-Host ''

Ensure-Directory $DestinationRoot
Ensure-Directory (Split-Path -Parent $LogPath)

$allRows = Import-Csv -LiteralPath $CsvPath
$pattern = '{0}:\*' -f $DriveLetter
$targetRows = $allRows | Where-Object { $_.Path -like $pattern }

$uniqueRows = $targetRows | Sort-Object Path -Unique
$total = $uniqueRows.Count

if ($total -eq 0) {
    Write-Warning ("No hay entradas para {0}: en {1}" -f $DriveLetter,$CsvPath)
    return
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$results = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[object]
$bytesMoved = [long]0

for ($i = 0; $i -lt $total; $i++) {
    $row = $uniqueRows[$i]
    $source = $row.Path
    $relative = $source.Substring(3)
    $destination = Join-Path $DestinationRoot $relative

    $sourceExists = Test-Path -LiteralPath $source -PathType Leaf
    $progressPct = [Math]::Min(100,[Math]::Round((($i+1)/$total)*100,2))
    $statusLine = "{0}/{1} - {2}" -f ($i+1),$total,$relative
    Write-Progress -Activity ("Moviendo duplicados {0}:" -f $DriveLetter) -Status $statusLine -PercentComplete $progressPct

    if (-not $sourceExists) {
        $err = [pscustomobject]@{
            Hash        = $row.Hash
            Bytes       = [int64]$row.Bytes
            SourcePath  = $source
            DestPath    = $destination
            Reason      = 'No encontrado'
        }
        $errors.Add($err)
        Write-Warning ("NO SE ENCONTRO: {0}" -f $source)
        continue
    }

    $destDir = Split-Path -Parent $destination
    Ensure-DirectoryLong $destDir

    $finalDest = Get-UniqueDestination $destination
    if ($finalDest -ne $destination) {
        Write-Host ("Colision detectada, renombrando destino a: {0}" -f (Split-Path -Leaf $finalDest)) -ForegroundColor Yellow
        $destination = $finalDest
    }

    $sourceLong = Add-LongPrefix $source
    $destLong = Add-LongPrefix $destination

    if (-not $WhatIf) {
        try {
            if ([System.IO.File]::Exists($destLong)) {
                [System.IO.File]::Delete($destLong)
            }
            [System.IO.File]::Move($sourceLong,$destLong)
            $bytes = [int64]$row.Bytes
            $bytesMoved += $bytes
            Write-Host ("Movido ({0}): {1}" -f (Format-Bytes $bytes), $relative)
            $results.Add([pscustomobject]@{
                Hash        = $row.Hash
                Bytes       = $bytes
                SourcePath  = $source
                DestPath    = $destination
                LastWrite   = $row.LastWrite
            })
        } catch {
            $err = [pscustomobject]@{
                Hash        = $row.Hash
                Bytes       = [int64]$row.Bytes
                SourcePath  = $source
                DestPath    = $destination
                Reason      = $_.Exception.Message
            }
            $errors.Add($err)
            Write-Error ("Error al mover {0}: {1}" -f $source,$_.Exception.Message)
        }
    } else {
        Write-Host ("WhatIf - Se moveria ({0}): {1}" -f (Format-Bytes([int64]$row.Bytes)), $relative)
        $results.Add([pscustomobject]@{
            Hash        = $row.Hash
            Bytes       = [int64]$row.Bytes
            SourcePath  = $source
            DestPath    = $destination
            LastWrite   = $row.LastWrite
            Simulated   = $true
        })
    }
}

$stopwatch.Stop()
Write-Progress -Activity ("Moviendo duplicados {0}:" -f $DriveLetter) -Completed -Status 'Completado'

if (-not $WhatIf) {
    $results | Export-Csv -LiteralPath $LogPath -NoTypeInformation -Encoding UTF8
    if ($errors.Count -gt 0) {
        $errorLog = [System.IO.Path]::ChangeExtension($LogPath,'errors.csv')
        $errors | Export-Csv -LiteralPath $errorLog -NoTypeInformation -Encoding UTF8
    }
}

Write-Host ''
Write-Host '================= RESUMEN =================' -ForegroundColor Cyan
Write-Host ("Archivos procesados: {0}" -f $total)
Write-Host ("Movidos correctamente: {0}" -f $results.Count)
if (-not $WhatIf) {
    Write-Host ("Bytes movidos: {0}" -f (Format-Bytes $bytesMoved))
    Write-Host ("Log guardado en: {0}" -f $LogPath)
}
if ($errors.Count -gt 0) {
    Write-Warning ("Errores: {0} (ver log)" -f $errors.Count)
} else {
    Write-Host 'Errores: 0' -ForegroundColor Green
}
Write-Host ("Duracion: {0}" -f $stopwatch.Elapsed)
Write-Host '===========================================' -ForegroundColor Cyan
Write-Host ''
