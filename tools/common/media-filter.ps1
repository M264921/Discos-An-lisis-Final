$global:MediaRegex = "^(?i)\.(jpg|jpeg|png|gif|heic|heif|tif|tiff|bmp|webp|raw|cr2|nef|arw|dng|rw2|orf|sr2|mp4|mov|mkv|avi|wmv|mts|m2ts|m4v|mp3|wav|flac|aac|m4a|ogg|wma)$"
function Is-MediaFile {
  param([Parameter(Mandatory,ValueFromPipeline)][System.IO.FileInfo]$File)
  process { try { return ($File.Extension -match $global:MediaRegex) } catch { return $false } }
}
