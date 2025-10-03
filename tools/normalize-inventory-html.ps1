Param(
  [string]$HtmlPath = "docs\inventario_interactivo_offline.html"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path $HtmlPath)) { throw "No se genero $HtmlPath" }

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8

$html = [regex]::Replace($html, 'windiw', 'window', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$rx = [System.Text.RegularExpressions.Regex]::new('window\.(?:__DATA__|_DATA_)\s*=\s*(\[[\s\S]*?\]);', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$m = $rx.Match($html)
if ($m.Success) {
  $json = $m.Groups[1].Value
  $inject = "`n<script>window.__INVENTARIO__.setData($json, 'Normalizado desde __DATA__');</script>`n"
  $html = $rx.Replace($html, '')
  $html = [regex]::Replace($html, '</body>\s*</html>\s*$', $inject + '</body></html>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  [IO.File]::WriteAllText($HtmlPath, $html, [Text.Encoding]::UTF8)
  Write-Host "OK: normalizado a __INVENTARIO__.setData(...)"
} else {
  Write-Host "No se encontro __DATA__/_DATA_; no hay cambios."
}

