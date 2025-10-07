param([Parameter(Mandatory)]$CsvPath,[Parameter(Mandatory)]$HtmlPath)

function FirstNonEmpty([object[]]$v){ foreach($x in $v){ if($null-ne $x -and "$x".Trim()){ return "$x" } } "" }
function LeafOrEmpty([string]$p){ if($p -and "$p".Trim()){ try{ return (Split-Path $p -Leaf) }catch{ "" } } ""; }
function DriveFromPath([string]$p){ if($p -and $p -match '^([A-Za-z]):'){ return $Matches[1].ToUpper() } "OTROS" }
function ExtType([string]$n){
  if(-not $n){ return 'otro' }
  $n = "$n".ToLower()
  switch -regex ($n){
    '\.(mp4|mkv|avi|mov|wmv|flv|m4v)$'             { 'video'; break }
    '\.(jpg|jpeg|png|gif|bmp|tif|tiff|webp|heic)$' { 'foto'; break }
    '\.(mp3|wav|flac|aac|ogg|m4a)$'                { 'audio'; break }
    '\.(pdf|docx?|xlsx?|pptx?|txt|rtf)$'           { 'documento'; break }
    default                                        { 'otro' }
  }
}

$csv  = (Get-Item -LiteralPath $CsvPath).FullName
$html = (Get-Item -LiteralPath $HtmlPath).FullName
$rows = Import-Csv -LiteralPath $csv

$map = $rows | ForEach-Object {
  $path  = FirstNonEmpty @($_.path,$_.FullName,$_.filepath,$_.ruta,$_.location)
  $name  = FirstNonEmpty @($_.name,$_.filename,$_.file_name,(LeafOrEmpty $path))
  if(-not $name){ $name = FirstNonEmpty @($_.sha,$_.hash,"(sin nombre)") }
  $sizeS = FirstNonEmpty @($_.size,$_.bytes,$_.length,$_.filesize,0)
  [void][int64]::TryParse("$sizeS",[ref]([int64]$size=0))
  $last  = FirstNonEmpty @($_.last,$_.modified,$_.mtime,$_.date)
  $drive = if(FirstNonEmpty @($_.drive,$_.unidad)){ (FirstNonEmpty @($_.drive,$_.unidad)).ToUpper() } else { DriveFromPath $path }
  $type  = FirstNonEmpty @($_.type,$_.category,$_.tipo,(ExtType $name))
  [pscustomobject]@{
    sha   = FirstNonEmpty @($_.sha,$_.hash,$_.md5,$_.sha1,$_.sha256)
    type  = $type
    name  = $name
    path  = $path
    drive = $drive
    size  = [int64]$size
    last  = $last
  }
}

# === resumen ===
$meta = [pscustomobject]@{ total=$map.Count; driveCounts=@{}; generatedAt=(Get-Date).ToString("s") }
$map | Group-Object drive | ForEach-Object { $meta.driveCounts[$_.Name] = $_.Count }
$bytesTotal = ($map | Measure-Object size -Sum).Sum

$h = ($meta.driveCounts['H'] ?? 0)
$i = ($meta.driveCounts['I'] ?? 0)
$j = ($meta.driveCounts['J'] ?? 0)
Write-Output ("Injector OK: {0} filas | bytes totales: {1:N0} | H:{2} I:{3} J:{4}" -f $map.Count, $bytesTotal, $h, $i, $j)

# === inyección ===
$doc = Get-Content -LiteralPath $html -Raw
function SetBlock($id,$json){
  $pat = "<script id=""$id""[^>]*>[\s\S]*?</script>"
  $rep = "<script id=""$id"" type=""application/json"">$json</script>"
  if($doc -match $pat){ $script:doc = [regex]::Replace($doc,$pat,$rep,1) } else { $script:doc = $doc -replace '</body>',($rep+"`r`n</body>") }
  $doc = $script:doc
}
SetBlock "inventory-data" (ConvertTo-Json $map -Depth 6)
SetBlock "inventory-meta" (ConvertTo-Json $meta -Depth 6)
Set-Content -LiteralPath $html -Value $doc -Encoding UTF8
