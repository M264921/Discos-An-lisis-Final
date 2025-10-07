# tools/common/media-filter.ps1
# Uso:
#   . "$PSScriptRoot\..\common\media-filter.ps1"
#   if (Is-MediaFile $_) { ... }

# Regex de extensiones multimedia (insensible a mayúsculas)
$global:MediaRegex = '^(?i)\.(jpg|jpeg|png|gif|heic|heif|tif|tiff|bmp|webp|raw|cr2|nef|arw|dng|rw2|orf|sr2|' +
                     'mp4|mov|mkv|avi|wmv|mts|m2ts|m4v|' +
                     'mp3|wav|flac|aac|m4a|ogg|wma)$'

function Is-MediaFile {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [System.IO.FileInfo]$File
    )
    process {
        try {
            return ($File -and $File.Extension -match $global:MediaRegex)
        } catch { return $false }
    }
}
