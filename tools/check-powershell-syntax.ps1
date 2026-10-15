# Parse tracked PowerShell sources only; never execute a scanner or cleaner.
[CmdletBinding()]
param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$files = @(& git -C $resolvedRoot -c core.quotepath=false ls-files -- '*.ps1' '*.psm1' '*.psd1')
if ($LASTEXITCODE -ne 0) { throw 'Cannot list tracked PowerShell sources.' }
if ($files.Count -eq 0) { throw 'No PowerShell sources were found.' }
$failed = 0
foreach ($relative in $files) {
  $path = Join-Path $resolvedRoot $relative
  $tokens = $null
  $parseErrors = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
  foreach ($item in $parseErrors) {
    $failed++
    Write-Host ('{0}:{1}: {2}' -f $relative, $item.Extent.StartLineNumber, $item.Message)
  }
}
if ($failed -gt 0) { throw ('PowerShell syntax errors: {0}' -f $failed) }
Write-Host ('PowerShell syntax OK: {0} files; no scripts executed.' -f $files.Count)
