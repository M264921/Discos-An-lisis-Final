[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Drive,
  [string]$OutCsv,
  [ValidateSet('SHA256','SHA1','None')][string]$Algorithm = 'SHA256',
  [ValidateSet('Media','Otros','Todo')][string]$ContentFilter = 'Media'
)

$imageExt = @('jpg','jpeg','png','gif','bmp','tif','tiff','heic','webp','svg','raw','nef','cr2')
$videoExt = @('mp4','m4v','mov','avi','mkv','webm','wmv','flv','mpg','mpeg','ts')
$audioExt = @('mp3','wav','flac','aac','ogg','m4a','opus','wma','aiff')
$docExt   = @('pdf','doc','docx','xls','xlsx','ppt','pptx','txt','rtf','csv','json','xml','psd','ai')

function Get-Category {
  param([string]$Extension)
  if ([string]::IsNullOrWhiteSpace($Extension)) { return 'archivo' }
  $ext = $Extension.ToLowerInvariant()
  if ($imageExt -contains $ext) { return 'foto' }
  if ($videoExt -contains $ext) { return 'video' }
  if ($audioExt -contains $ext) { return 'audio' }
  if ($docExt   -contains $ext) { return 'documento' }
  return 'archivo'
}

function Should-Include {
  param(
    [string]$Category,
    [string]$Filter
  )
  switch ($Filter) {
    'Media' { return $Category -in @('foto','video','audio') }
    'Otros' { return $Category -notin @('foto','video','audio') }
    default { return $true }
  }
}

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

foreach ($item in (Get-ChildItem -LiteralPath $drivePath -Recurse -Force -File -ErrorAction SilentlyContinue)) {
  $extension = ""
  if ($item.Extension) {
    $extension = ($item.Extension).ToString().TrimStart('.')
  }
  $category  = Get-Category $extension
  if (-not (Should-Include $category $ContentFilter)) { continue }

  $count++

  if (($count % $progressEvery) -eq 0) {
    Write-Progress -Activity ("Escaneando {0}" -f $drivePath) -Status ("{0} archivos..." -f $count) -PercentComplete 0
  }

  $sha = ""
  if ($computeHash -and $hasher) {
    try {
      $stream = $item.OpenRead()
      $hashBytes = $hasher.ComputeHash($stream)
      $stream.Dispose()
      $sha = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
      $sha = $sha.ToUpperInvariant()
    } catch {
      Write-Warning ("No se pudo hashear {0}: {1}" -f $item.FullName, $_.Exception.Message)
    }
  }

  $unit = $drivePath.Substring(0, [Math]::Min(2, $drivePath.Length)).TrimEnd('\')
  if (-not $unit.EndsWith(':')) {
    $unit = ($unit.TrimEnd(':')) + ':'
  }
  $unit = $unit.ToUpperInvariant()

  $rows.Add([pscustomobject]@{
    sha        = $sha
    tipo       = $category
    extension  = $extension.ToLowerInvariant()
    nombre     = $item.Name
    ruta       = $item.DirectoryName
    unidad     = $unit
    drive      = $unit
    tamano     = [int64]$item.Length
    fecha      = $item.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
  })

  if (($count % $heartbeat) -eq 0) {
    $rate = "{0:n0}/s" -f ($count / [Math]::Max(1, $stopwatch.Elapsed.TotalSeconds))
    Write-Host ("  Procesados: {0:n0} | Tiempo: {1:c} | Velocidad: {2}" -f $count, $stopwatch.Elapsed, $rate)
  }
}

$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv
Write-Host ("CSV listo: {0} ({1} filas)" -f $OutCsv, $rows.Count) -ForegroundColor Green

if ($hasher) { $hasher.Dispose() }
