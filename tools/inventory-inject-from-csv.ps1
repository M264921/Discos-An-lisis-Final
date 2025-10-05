param([Parameter(Mandatory)]$CsvPath,[Parameter(Mandatory)]$HtmlPath)

function Leaf([string]$p){ if($p){ try{ (Split-Path $p -Leaf) }catch{ "" } } }
function DriveFromPath([string]$p){ if($p -match '^([A-Za-z]):'){ $Matches[1].ToUpper() } else { "OTROS" } }
function ExtType([string]$ext){
  $e = ("$ext").ToLower()
  switch -regex ($e){
    '\.(mp4|mkv|avi|mov|wmv|flv|m4v)$'                { 'video' }
    '\.(jpg|jpeg|png|gif|bmp|tif|tiff|webp|heic)$'    { 'foto' }
    '\.(mp3|wav|flac|aac|ogg|m4a)$'                   { 'audio' }
    '\.(pdf|docx?|xlsx?|pptx?|txt|rtf)$'              { 'documento' }
    default                                           { 'otro' }
  }
}

$csv  = (Get-Item -LiteralPath $CsvPath).FullName
$html = (Get-Item -LiteralPath $HtmlPath).FullName
$rows = Import-Csv -LiteralPath $csv

$map = $rows | ForEach-Object {
  $path = $_.FullName
  $name = if ($_.Name) { $_.Name } else { Leaf $path }
  $ext  = if ($_.Extension) { $_.Extension } else { [IO.Path]::GetExtension($name) }
  $size = 0; [void][int64]::TryParse("$($_.Length)", [ref]$size)

  [pscustomobject]@{
    sha   = $_.Hash
    type  = ExtType $ext
    name  = $name
    path  = $path
    drive = DriveFromPath $path
    size  = [int64]$size
    last  = ""   # no viene en el CSV
  }
}

$meta = [pscustomobject]@{ total=$map.Count; driveCounts=@{}; generatedAt=(Get-Date).ToString('s') }
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
Set-Content -LiteralPath $html -Value $doc -Encoding UTF8
"Injector OK: $($map.Count) | " + ($meta.driveCounts.GetEnumerator() | ForEach-Object { "$($_.Key):$($_.Value)" } -join ' ')
