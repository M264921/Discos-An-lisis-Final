param(
  [string[]] $Drives = @("K:\"),
  [int] $MaxFiles = 3000,
  [switch] $MediaOnly = $true
)

$ErrorActionPreference = "SilentlyContinue"

$mediaExt = @(
  ".mp4",".mkv",".avi",".mov",".wmv",".flv",".webm",
  ".mp3",".wav",".flac",".m4a",".aac",
  ".jpg",".jpeg",".png",".gif",".bmp",".tiff",".webp"
)

# Salida
Set-Location (Split-Path -Parent $PSCommandPath)
Set-Location ..
New-Item -ItemType Directory -Path ".\data" -Force | Out-Null

$results = New-Object System.Collections.Generic.List[object]
foreach ($d in $Drives) {
  if (-not (Test-Path $d)) { continue }
  $count = 0
  Write-Host ">>> Escaneando $d (máx $MaxFiles)..."
  Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
      if ($MediaOnly) {
        $ext = [System.IO.Path]::GetExtension($_.FullName).ToLowerInvariant()
        if ($mediaExt -notcontains $ext) { return }
      }
      $results.Add([pscustomobject]@{
        path     = $_.FullName
        size     = $_.Length
        ext      = ([System.IO.Path]::GetExtension($_.Name)).ToLowerInvariant()
        modified = $_.LastWriteTimeUtc
      })
      $count++
      if ($count -ge $MaxFiles) { return }
    }
}

# JSON
$jsonPath = "data\inventory.json"
$results | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 $jsonPath
Write-Host "✅ Escrito $jsonPath ($($results.Count) items)"

# GZIP
$gzPath = "data\inventory.json.gz"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8 = [System.Text.Encoding]::UTF8
$bytes = $utf8.GetBytes((Get-Content $jsonPath -Raw -Encoding UTF8))
$fs = [System.IO.File]::Create($gzPath)
$gzip = New-Object System.IO.Compression.GzipStream($fs, [System.IO.Compression.CompressionLevel]::Optimal)
$gzip.Write($bytes, 0, $bytes.Length)
$gzip.Close(); $fs.Close()
Write-Host "✅ Escrito $gzPath (gzip)"
