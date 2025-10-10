[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CsvPath,
  [Parameter(Mandatory)][string]$HtmlPath
)

$ErrorActionPreference = 'Stop'

function First-NonEmpty {
  param([object[]]$Values)
  foreach ($candidate in $Values) {
    if ($null -ne $candidate -and ("$candidate").Trim()) {
      return "$candidate"
    }
  }
  return ""
}

function Leaf-Or-Empty {
  param([string]$Path)
  if (-not $Path) { return "" }
  try { return (Split-Path -Path $Path -Leaf) } catch { return "" }
}

function Drive-From-Path {
  param([string]$Path)
  if ($Path -and $Path -match '^([A-Za-z]):') { return $Matches[1].ToUpper() }
  return 'OTROS'
}

function Infer-Type {
  param([string]$Name)
  $n = ("$Name").ToLower()
  switch -regex ($n) {
    '\.(mp4|mkv|avi|mov|wmv|webm|m4v)$' { return 'video' }
    '\.(jpg|jpeg|png|gif|bmp|tif|tiff|webp|heic)$' { return 'foto' }
    '\.(mp3|wav|flac|aac|ogg|m4a|opus)$' { return 'audio' }
    '\.(pdf|docx?|xlsx?|pptx?|txt|rtf)$' { return 'documento' }
    default { return 'otro' }
  }
}

$csvFull = (Get-Item -LiteralPath $CsvPath).FullName
$htmlFull = (Get-Item -LiteralPath $HtmlPath).FullName
$rows = Import-Csv -LiteralPath $csvFull

$normalized = $rows | ForEach-Object {
  $path = First-NonEmpty @($_.path,$_.full_path,$_.filepath,$_.ruta,$_.location,$_.FullName)
  $name = First-NonEmpty @($_.name,$_.filename,$_.file_name,(Leaf-Or-Empty $path),$_.sha)
  if (-not $name) { $name = "(sin nombre)" }

  $size = 0L
  $sizeCandidates = @($_.Length,$_.size,$_.bytes,$_.filesize,$_.tamano,$_.length)
  foreach ($candidate in $sizeCandidates) {
    if ($candidate -and [int64]::TryParse("$candidate", [ref]$size)) { break }
  }

  $drive = First-NonEmpty @($_.drive,$_.unidad)
  if (-not $drive) { $drive = Drive-From-Path $path }
  $drive = $drive.TrimEnd(':').ToUpper()

  $type = First-NonEmpty @($_.type,$_.category,$_.tipo,(Infer-Type $name))
  $hash = First-NonEmpty @($_.sha,$_.hash,$_.md5,$_.sha1,$_.sha256)
  $last = First-NonEmpty @($_.last,$_.modified,$_.mtime,$_.date,$_.fecha)

  [pscustomobject]@{
    sha   = $hash
    type  = $type
    name  = $name
    path  = $path
    drive = $drive
    size  = [int64]$size
    last  = $last
  }
}

$meta = [pscustomobject]@{
  total = $normalized.Count
  driveCounts = @{}
  generatedAt = (Get-Date).ToString("s")
}

$normalized | Group-Object drive | ForEach-Object {
  $meta.driveCounts[$_.Name] = $_.Count
}

$doc = Get-Content -LiteralPath $htmlFull -Raw

function Update-ScriptBlock {
  param(
    [string]$Id,
    [string]$Payload
  )
  $pattern = "<script id=""$Id""[^>]*>[\s\S]*?</script>"
  $replacement = "<script id=""$Id"" type=""application/json"">$Payload</script>"
  if ($script:doc -match $pattern) {
    $script:doc = [regex]::Replace($script:doc, $pattern, $replacement, 1)
  } else {
    $script:doc = $script:doc -replace '</body>', ($replacement + "`r`n</body>")
  }
}

$script:doc = $doc
Update-ScriptBlock -Id 'inventory-data' -Payload (ConvertTo-Json $normalized -Depth 6)
Update-ScriptBlock -Id 'inventory-meta' -Payload (ConvertTo-Json $meta -Depth 6)
Set-Content -LiteralPath $htmlFull -Encoding UTF8 -Value $script:doc

$totalBytes = ($normalized | Measure-Object size -Sum).Sum
Write-Host ("Injector OK: {0} filas | bytes totales: {1}" -f $normalized.Count, $totalBytes) -ForegroundColor Green
