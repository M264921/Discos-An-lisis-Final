Param(
  [string]$HtmlPath = 'docs/inventario_interactivo_offline.html'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $HtmlPath)) {
  throw "No existe el HTML de inventario: $HtmlPath"
}

[string]$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8

$singleLine = [System.Text.RegularExpressions.RegexOptions]::Singleline
$ignoreCase = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$rxOptions = $singleLine -bor $ignoreCase

function Remove-Pattern {
  param(
    [string]$Input,
    [string]$Pattern
  )
  $regex = [System.Text.RegularExpressions.Regex]::new($Pattern, $rxOptions)
  return $regex.Replace($Input, '')
}

$externalPatterns = @(
  '<script[^>]*\bsrc\s*=\s*"(?:https?:|ftp:)?//[^"]*"[^>]*>\s*</script>',
  "<script[^>]*\\bsrc\\s*=\\s*'(?:https?:|ftp:)?//[^']*'[^>]*>\\s*</script>",
  '<link[^>]*\bhref\s*=\s*"(?:https?:|ftp:)?//[^"]*"[^>]*?>',
  "<link[^>]*\\bhref\\s*=\\s*'(?:https?:|ftp:)?//[^']*'[^>]*?>",
  '<iframe[^>]*\bsrc\s*=\s*"(?:https?:|ftp:)?//[^"]*"[^>]*>[\s\S]*?</iframe>',
  "<iframe[^>]*\\bsrc\\s*=\\s*'(?:https?:|ftp:)?//[^']*'[^>]*>[\\s\\S]*?</iframe>",
  '<img[^>]*\bsrc\s*=\s*"(?:https?:|ftp:)?//[^"]*"[^>]*>',
  "<img[^>]*\\bsrc\\s*=\\s*'(?:https?:|ftp:)?//[^']*'[^>]*>"
)

foreach ($pattern in $externalPatterns) {
  $html = Remove-Pattern -Input $html -Pattern $pattern
}

$blockList = '(?:acestream|yandex|metrika|tiktok|facebook|doubleclick|googletag|google-analytics|mc\.yandex|vk\.com)'
$scriptBlockPattern = "<script[^>]*$blockList[^>]*>[\\s\\S]*?</script>"
$iframeBlockPattern = "<iframe[^>]*$blockList[^>]*>[\\s\\S]*?</iframe>"
$html = Remove-Pattern -Input $html -Pattern $scriptBlockPattern
$html = Remove-Pattern -Input $html -Pattern $iframeBlockPattern

$acestreamPattern = '(?i)acestream://[^\s"'']+'
$html = [System.Text.RegularExpressions.Regex]::Replace($html, $acestreamPattern, '')

$attributePatterns = @(
  '\bsrc\s*=\s*"(?:https?:|ftp:)?//[^\"#]+"',
  "\\bsrc\\s*=\\s*'(?:https?:|ftp:)?//[^'"#]+'",
  '\bhref\s*=\s*"(?:acestream:|magnet:)[^"]*"',
  "\\bhref\\s*=\\s*'(?:acestream:|magnet:)[^']*'"
)
foreach ($attrPattern in $attributePatterns) {
  $regex = [System.Text.RegularExpressions.Regex]::new($attrPattern, $rxOptions)
  $html = $regex.Replace($html, ' data-sanitized="#"')
}

$html = $html -replace '\s+data-sanitized="#"', ' data-sanitized="#"'

[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "OK: HTML sanitizado -> $HtmlPath"
