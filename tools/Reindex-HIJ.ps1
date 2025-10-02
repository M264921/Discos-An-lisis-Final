[CmdletBinding()]
param(
    [string[]]$Drives = @('H','I','J'),
    [switch]$SkipCopy,
    [string]$Python = 'python'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$pythonExe = (Get-Command $Python -ErrorAction Stop).Source
$reindexScript = Join-Path $scriptRoot 'reindex_hij.py'

if (-not (Test-Path $reindexScript)) {
    throw "No se encuentra reindex_hij.py en $scriptRoot"
}

$arguments = @($reindexScript, '--output-root', $repoRoot)
if ($Drives -and $Drives.Count -gt 0) {
    $arguments += '--drives'
    $arguments += $Drives
}
if ($SkipCopy) {
    $arguments += '--skip-copy'
}

$processOutput = & $pythonExe @arguments 2>&1
if ($processOutput) {
    $processOutput | ForEach-Object { Write-Host $_ }
}

if ($LASTEXITCODE -ne 0) {
    throw "reindex_hij.py termino con codigo $LASTEXITCODE"
}
