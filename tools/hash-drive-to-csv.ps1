[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Drive,
  [string]$OutCsv,
  [ValidateSet('SHA256','SHA1','None')][string]$Algorithm = 'SHA256'
)

$patterns = '\.(jpg|jpeg|png|gif|heic|tif|tiff|bmp|svg|mp4|m4v|mov|avi|mkv|webm|mp3|wav|flac|aac|ogg)$'

$drivePath = $Drive.Trim()
if ($drivePath.Length -eq 2 -and $drivePath[1] -eq ':') {
  $drivePath += '\'
}
if (-not (Test-Path -LiteralPath $drivePath)) {
  throw "No se encuentra la raiz $drivePath"
}

if ([string]::IsNullOrWhiteSpace($OutCsv)) {
  $letter = ($drivePath.TrimEnd('\'))[0]
  if (-not $letter) { $letter = 'X' }
  $OutCsv = "docs\inventory\scan_{0}.csv" -f ([char]::ToUpper($letter))
}

$progressEvery = 500
$heartbeat = 2000
$rows = New-Object System.Collections.Generic.List[object]
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$count = 0
$computeHash = $Algorithm -ne 'None'

function New-Hasher([string]$Name){
  switch ($Name) {
    'SHA256' { return [System.Security.Cryptography.SHA256]::Create() }
    'SHA1'   { return [System.Security.Cryptography.SHA1]::Create() }
    default  { return $null }
  }
}

$hasher = if ($computeHash) { New-Hasher $Algorithm } else { $null }

Get-ChildItem -LiteralPath $drivePath -Recurse -Force -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match $patterns } |
  ForEach-Object {
    $count++

    if (($count % $progressEvery) -eq 0) {
      Write-Progress -Activity ("Escaneando {0}" -f $drivePath) -Status ("{0} archivos..." -f $count) -PercentComplete 0
    }

    $sha = ""
    if ($computeHash -and $hasher) {
      try {
        $stream = $_.OpenRead()
        $hashBytes = $hasher.ComputeHash($stream)
        $stream.Dispose()
        $sha = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
        $sha = $sha.ToUpperInvariant()
      } catch {
        Write-Warning ("No se pudo hashear {0}: {1}" -f $_.FullName, $_.Exception.Message)
      }
    }

    $rows.Add([pscustomobject]@{
      sha    = $sha
      tipo   = ($_.Extension).TrimStart('.').ToLowerInvariant()
      nombre = $_.Name
      ruta   = $_.DirectoryName
      drive  = $drivePath.Substring(0, [Math]::Min(2, $drivePath.Length))
      tamano = [int64]$_.Length
      fecha  = $_.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    })

    if (($count % $heartbeat) -eq 0) {
      $rate = "{0:n0}/s" -f ($count / [Math]::Max(1, $stopwatch.Elapsed.TotalSeconds))
      Write-Host ("  Procesados: {0:n0} | Tiempo: {1:c} | Velocidad: {2}" -f $count, $stopwatch.Elapsed, $rate)
    }
  }

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv
Write-Host ("CSV listo: {0} ({1} filas)" -f $OutCsv, $rows.Count) -ForegroundColor Green

if ($hasher) { $hasher.Dispose() }
