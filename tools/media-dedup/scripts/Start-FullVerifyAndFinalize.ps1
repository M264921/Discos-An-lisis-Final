[CmdletBinding()]
param([switch]$Publish)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Verify-Consolidation.ps1') -Mode Full -ProgressInterval 25
& (Join-Path $PSScriptRoot 'Generate-FinalReport.ps1')
if ($Publish) {
  Push-Location (Split-Path -Parent $PSScriptRoot)
  try {
    git add report/VERIFY-REPORT.md report/CONSOLIDATION-FINAL.md
    if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
    git commit -m 'chore(report): update verified consolidation reports'
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
    git push origin HEAD
    if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
  } finally { Pop-Location }
}
Write-Host 'Full verification and reports completed.'
