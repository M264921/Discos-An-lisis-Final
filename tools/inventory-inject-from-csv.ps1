param(
  [Parameter(Mandatory)]$CsvPath,
  [Parameter(Mandatory)]$HtmlPath
)

function FirstNonEmpty([object[]]$v){ foreach($x in $v){ if($null -ne $x -and "$x".Trim()){ return "$x" } } ""; }
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
  $path  = FirstNonEmpty @($_.path,$_.full_path,$_.filepath,$_.ruta,$_.location,$_.FullName)
  $name  = FirstNonEmpty @($_.name,$_.filename,$_.file_name, (LeafOrEmpty $path))
  if(-not $name){ $name = FirstNonEmpty @($_.sha,$_.hash,"(sin nombre)") }

  # Tamaño: prioriza Length; si viene vacío intenta otros campos y castea a int64
  $size = 0L
  if($_.PSObject.Properties.Match('Length').Count -gt 0 -and "$($_.Length)".Trim()){
    [void][int64]::TryParse("$($_.Length)", [ref]$size) | Out-Null
  }
  if($size -le 0){
    $sizeS = FirstNonEmpty @($_.size,$_.bytes,$_.length,$_.filesize,0)
    [void][int64]::TryParse("$sizeS", [ref]$size) | Out-Null
  }

  $last  = FirstNonEmpty @($_.last,$_.modified,$_.mtime,$_.date)
  $drive = if(FirstNonEmpty @($_.drive,$_.unidad)){ (FirstNonEmpty @($_.drive,$_.unidad)).ToUpper() } else { DriveFromPath $path }
  $type  = FirstNonEmpty @($_.type,$_.category,$_.tipo, (ExtType $name))

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

$meta = [pscustomobject]@{ total=$map.Count; driveCounts=@{}; generatedAt=(Get-Date).ToString("s") }
$map | Group-Object drive | ForEach-Object { $meta.driveCounts[$_.Name] = $_.Count }

$doc = Get-Content -LiteralPath $html -Raw
function SetBlock($id,$json){
  $pat = "<script id=""$id""[^>]*>[\s\S]*?</script>"
  $rep = "<script id=""$id"" type=""application/json"">$json</script>"
  if($doc -match $pat){ $script:doc = [regex]::Replace($doc,$pat,$rep,1) } else { $script:doc = $doc -replace '</body>',($rep+"`r`n</body>") }
  $doc = $script:doc
}
SetBlock "inventory-data" (ConvertTo-Json $map -Depth 6)
SetBlock "inventory-meta" (ConvertTo-Json $meta -Depth 6)
Set-Content -LiteralPath $html -Value $doc -Encoding utf8

$sum = ($map | Measure-Object size -Sum).Sum
"Injector OK: $($map.Count) filas | bytes totales: $sum | H:$($meta.driveCounts.H) I:$($meta.driveCounts.I) J:$($meta.driveCounts.J)"
