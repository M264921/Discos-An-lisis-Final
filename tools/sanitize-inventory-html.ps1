[CmdletBinding()]
param(
  [string]$HtmlPath = 'docs/inventario_interactivo_offline.html'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $HtmlPath)) {
  throw "No existe el HTML de inventario: $HtmlPath"
}

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8

$options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::Singleline

function Remove-Pattern {
  param(
    [string]$Content,
    [string]$Pattern,
    [System.Text.RegularExpressions.RegexOptions]$Options
  )
  $regex = [System.Text.RegularExpressions.Regex]::new($Pattern, $Options)
  return $regex.Replace($Content, '')
}

$externalPatterns = @(
  '<script[^>]*\bsrc\s*=\s*"(?:(?:https?|ftp):)?//[^"]*"[^>]*>\s*</script>',
  '<script[^>]*\bsrc\s*=\s*''(?:(?:https?|ftp):)?//[^'']*''[^>]*>\s*</script>',
  '<link[^>]*\bhref\s*=\s*"(?:(?:https?|ftp):)?//[^"]*"[^>]*?>',
  '<link[^>]*\bhref\s*=\s*''(?:(?:https?|ftp):)?//[^'']*''[^>]*?>',
  '<iframe[^>]*\bsrc\s*=\s*"(?:(?:https?|ftp):)?//[^"]*"[^>]*>[\s\S]*?</iframe>',
  '<iframe[^>]*\bsrc\s*=\s*''(?:(?:https?|ftp):)?//[^'']*''[^>]*>[\s\S]*?</iframe>',
  '<img[^>]*\bsrc\s*=\s*"(?:(?:https?|ftp):)?//[^"]*"[^>]*>',
  '<img[^>]*\bsrc\s*=\s*''(?:(?:https?|ftp):)?//[^'']*''[^>]*>'
)

foreach ($pattern in $externalPatterns) {
  $html = Remove-Pattern -Content $html -Pattern $pattern -Options $options
}

$blockList = '(?:acestream|yandex|metrika|tiktok|facebook|doubleclick|googletag|google-analytics|mc\.yandex|vk\.com)'
$scriptBlockPattern = "<script[^>]*$blockList[^>]*>[\s\S]*?</script>"
$iframeBlockPattern = "<iframe[^>]*$blockList[^>]*>[\s\S]*?</iframe>"
$html = Remove-Pattern -Content $html -Pattern $scriptBlockPattern -Options $options
$html = Remove-Pattern -Content $html -Pattern $iframeBlockPattern -Options $options

$html = [System.Text.RegularExpressions.Regex]::Replace(
  $html,
  '(?i)acestream://[^\s"''>]+',
  ''
)

$attributePatterns = @(
  '\bsrc\s*=\s*"(?:(?:https?|ftp):)?//[^"#]+"',
  '\bsrc\s*=\s*''(?:(?:https?|ftp):)?//[^''#]+''',
  '\bhref\s*=\s*"(?:acestream:|magnet:)[^"]*"',
  '\bhref\s*=\s*''(?:acestream:|magnet:)[^'']*'''
)

foreach ($attrPattern in $attributePatterns) {
  $regex = [System.Text.RegularExpressions.Regex]::new($attrPattern, $options)
  $html = $regex.Replace($html, ' data-sanitized="#"')
}

$html = [System.Text.RegularExpressions.Regex]::Replace(
  $html,
  '\s+data-sanitized="#"',
  ' data-sanitized="#"'
)

[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host ("OK: HTML sanitizado -> {0}" -f $HtmlPath) -ForegroundColor Green
