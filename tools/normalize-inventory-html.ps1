[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [Alias('Path','InputFile','HtmlPath')]
  [string]$Html,
  [int]$PreviewRows = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$resolvedHtml = (Resolve-Path -LiteralPath $Html).Path
Write-Host ("-> Normalizando: {0}" -f $resolvedHtml) -ForegroundColor Cyan

$doc = Get-Content -LiteralPath $resolvedHtml -Raw

$doc = [regex]::Replace(
  $doc,
  '<script[^>]+id=["'']bridge-inventory-offline["''][\s\S]*?</script>\s*',
  '',
  [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

$rx = [regex]::new(
  '<script[^>]+id=["'']inventory-data["''][^>]*>(?<json>[\s\S]*?)</script>',
  [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)
$json = $null
if ($rx.IsMatch($doc)) {
  try {
    $json = ($rx.Match($doc).Groups['json'].Value) | ConvertFrom-Json
  } catch {
    $json = $null
  }
}

$driveCounts = [ordered]@{}
if ($json -and $json.Count -gt 0) {
  $json | Group-Object unidad | ForEach-Object {
    $driveCounts[$_.Name] = $_.Count
  }
}

Set-Content -LiteralPath $resolvedHtml -Encoding UTF8 -Value $doc
Write-Host "OK Normalizado" -ForegroundColor Green
