[CmdletBinding()]
param(
  [string]$CsvPath = "docs\hash_data.csv",
  [string]$JsonPath = "docs\data\inventory.json"
)

if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "No existe $CsvPath"
}

$imageExt = @('jpg','jpeg','png','gif','bmp','tif','tiff','heic','webp','svg','raw','nef','cr2')
$videoExt = @('mp4','m4v','mov','avi','mkv','webm','wmv','flv','mpg','mpeg','ts')
$audioExt = @('mp3','wav','flac','aac','ogg','m4a','opus','wma','aiff')
$docExt   = @('pdf','doc','docx','xls','xlsx','ppt','pptx','txt','rtf','csv','json','xml','psd','ai')

function Normalize-Extension {
  param([object]$Value)
  if ($null -eq $Value) { return "" }
  $text = ("{0}" -f $Value).Trim()
  if (-not $text) { return "" }
  return $text.TrimStart('.').ToLowerInvariant()
}

function Detect-Category {
  param(
    [string]$Extension,
    [string]$Name
  )
  $ext = $Extension
  if (-not $ext -and $Name) {
    $ext = [IO.Path]::GetExtension($Name).TrimStart('.').ToLowerInvariant()
  }
  if ([string]::IsNullOrWhiteSpace($ext)) { return 'archivo' }
  if ($imageExt -contains $ext) { return 'foto' }
  if ($videoExt -contains $ext) { return 'video' }
  if ($audioExt -contains $ext) { return 'audio' }
  if ($docExt   -contains $ext) { return 'documento' }
  return 'archivo'
}

$rows = Import-Csv -LiteralPath $CsvPath
$data = $rows | ForEach-Object {
  $extension = Normalize-Extension ($_.extension ?? $_.ext)
  $name = $_.nombre
  $category = $_.tipo
  if (-not $name) { $name = $_.name }
  if (-not $category) { $category = $_.type }
  if (-not $category) { $category = Detect-Category $extension $name }

  $unitRaw = ($_.Drive ?? $_.unidad ?? $_.unit ?? "")
  $unitTxt = ("{0}" -f $unitRaw).Trim()
  if ($unitTxt.EndsWith(':')) { $unitTxt = $unitTxt.TrimEnd(':') }
  $unitTxt = $unitTxt.TrimEnd('\')
  if ($unitTxt) { $unitTxt = $unitTxt.ToUpperInvariant() + ':' }

  [pscustomobject]@{
    sha        = $_.sha ?? $_.hash ?? ""
    tipo       = $category
    extension  = $extension
    nombre     = $name ?? ""
    ruta       = $_.ruta ?? $_.path ?? ""
    unidad     = $unitTxt
    tamano     = [int64]($_.tamano ?? $_.size ?? $_.length ?? 0)
    fecha      = $_.fecha ?? $_.lastWriteTime ?? ""
  }
}

$data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $JsonPath -Encoding UTF8
Write-Host ("Generado {0} con {1} elementos" -f $JsonPath, $data.Count) -ForegroundColor Green
