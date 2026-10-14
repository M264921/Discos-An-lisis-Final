Describe 'Portable storage identity regression' {
  It 'resolves renamed volumes, rejects absent/ambiguous/locked volumes and handles folder mounts' {
    & (Join-Path $PSScriptRoot 'StorageRegression.ps1')
  }
}
