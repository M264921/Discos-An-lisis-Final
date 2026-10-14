@{
  Root = '.'
  # Enumerate current local fixed/removable volumes; no historical letter assumptions.
  Drives = @()
  IncludeSystemDrive = $false
  SourceVolumes = @()
  LegacyDriveMap = @{}
  DestinationVolume = @{}
  DestinationFolder = 'media_final'
  MinSizeBytes = 1MB
  ExcludeDirs = @('$Recycle.Bin', 'System Volume Information', 'Windows', 'Program Files', 'Program Files (x86)', '_quarantine_', '_dedup_store')
  VerifyHash = $true
  ReportName = 'informe_integral.html'
}
