Param(
  [string]$HtmlPath = "docs\inventario_interactivo_offline.html"
)
$ErrorActionPreference = "Stop"
if (!(Test-Path -LiteralPath $HtmlPath)) { throw "No existe: $HtmlPath" }
[string]$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8

# Quitar <script src="http(s)://..."></script> y <iframe src="http(s)://..."></iframe>
$html = [regex]::Replace($html, '<script[^>]*\bsrc\s*=\s*"(https?:)?//[^"]*"[^>]*>\s*</script>', '', 'IgnoreCase')
$html = [regex]::Replace($html, '<iframe[^>]*\bsrc\s*=\s*"(https?:)?//[^"]*"[^>]*>\s*</iframe>', '', 'IgnoreCase')

# Quitar cualquier referencia a dominios sospechosos/trackers
$block = '(acestream\.net|yandex\.ru|metrika|mc\.yandex|instat\.acestream|emet\.news)'
$html = [regex]::Replace($html, "(?is)<script[^>]*$block[^>]*>.*?</script>", '', 'IgnoreCase')
$html = [regex]::Replace($html, "(?is)<iframe[^>]*$block[^>]*>.*?</iframe>", '', 'IgnoreCase')

# Quitar enlaces 'acestream://' (a, href, texto plano)
$html = [regex]::Replace($html, '(?is)<a[^>]*\bhref\s*=\s*"acestream://[^"]*"[^>]*>.*?</a>', '', 'IgnoreCase')
$html = [regex]::Replace($html, 'acestream://[^\s"''<>]+', '', 'IgnoreCase')

# Salvar limpio
[IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
Write-Host "OK: Sanitizado -> $HtmlPath"
