[CmdletBinding()]
param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$source = Join-Path $RepoRoot 'tools/templates/inventory-drive-links.js'
$asset = Join-Path $RepoRoot 'docs/assets/js/inventory-drive-links.js'
$sourceBytes = [IO.File]::ReadAllBytes($source)
[IO.Directory]::CreateDirectory((Split-Path -Parent $asset)) | Out-Null
[IO.File]::WriteAllBytes($asset, $sourceBytes)

# Preserve the original encoding, newlines and embedded inventory byte for byte.
function Add-DriveLinksScript {
  param([string]$Path, [string]$Tag, [string]$Before)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $ascii = [Text.Encoding]::ASCII.GetString($bytes)
  if ($ascii.StartsWith('version https://git-lfs.github.com/spec/v1')) {
    Write-Verbose "HTML not present locally (Git LFS pointer): $Path"
    return
  }
  if ($ascii.Contains('id="mingo-drive-links"') -or $ascii.Contains('src="./assets/js/inventory-drive-links.js"')) { return }
  $index = $ascii.IndexOf($Before, [StringComparison]::OrdinalIgnoreCase)
  if ($index -lt 0) { throw "No insertion point found: $Path" }
  $tagBytes = [Text.Encoding]::UTF8.GetBytes($Tag + "`n")
  $stream = [IO.MemoryStream]::new()
  try {
    $stream.Write($bytes, 0, $index)
    $stream.Write($tagBytes, 0, $tagBytes.Length)
    $stream.Write($bytes, $index, $bytes.Length - $index)
    [IO.File]::WriteAllBytes($Path, $stream.ToArray())
  } finally { $stream.Dispose() }
}

Add-DriveLinksScript -Path (Join-Path $RepoRoot 'docs/index.html') -Tag '<script src="./assets/js/inventory-drive-links.js"></script>' -Before '<script src="./assets/js/inventory-app.js"'
$inline = '<script id="mingo-drive-links">' + "`n" + [Text.Encoding]::UTF8.GetString($sourceBytes) + "`n</script>"
foreach ($relative in @('docs/inventario_interactivo_offline.html', 'inventario_interactivo_offline.html', 'docs/inventario_pro_offline.html')) {
  Add-DriveLinksScript -Path (Join-Path $RepoRoot $relative) -Tag $inline -Before '</head>'
}
