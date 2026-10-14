[CmdletBinding()]
param([Parameter(Mandatory)][string]$JsonPath)
$ErrorActionPreference = 'Stop'
$text = [IO.File]::ReadAllText([IO.Path]::GetFullPath($JsonPath))
# Validate before replacing the derived compressed file. Keep source bytes/data unchanged.
$null = ConvertFrom-Json -InputObject $text -Depth 100 -NoEnumerate
$target = [IO.Path]::GetFullPath($JsonPath) + '.gz'
$temporary = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
$file = [IO.File]::Create($temporary)
try {
  $stream = [IO.Compression.GZipStream]::new($file, [IO.Compression.CompressionLevel]::Optimal)
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $stream.Write($bytes, 0, $bytes.Length)
  } finally { $stream.Dispose() }
} finally { $file.Dispose() }
[IO.File]::Move($temporary, $target, $true)
Write-Host "Compressed inventory refreshed: $target"
