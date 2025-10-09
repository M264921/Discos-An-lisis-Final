[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Html,
  [Parameter(Mandatory)][string]$JsonPath,
  [switch]$Backup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Html     = (Resolve-Path $Html).Path
$JsonPath = (Resolve-Path $JsonPath).Path

# 1) Backup opcional
if($Backup){
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $bak = "$Html.bak_$ts"
  Copy-Item -LiteralPath $Html -Destination $bak -Force
  Write-Host "↪ Backup: $bak" -ForegroundColor DarkGray
}

# 2) Lee y minimiza JSON
$rows = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
$min  = ($rows | ConvertTo-Json -Depth 6 -Compress)

# 3) Sustituye/Inserta bloque embebido
$doc = Get-Content -LiteralPath $Html -Raw
$rx  = [regex]::new('<script[^>]+id=["'']inventory-data["''][^>]*>[\s\S]*?</script>',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$block = '<script id="inventory-data" type="application/json">' + $min + '</script>'

if($rx.IsMatch($doc)){
  $doc = $rx.Replace($doc, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block }, 1)
}else{
  # si no existe, intenta meterlo antes de </body>, o al final
  if($doc -match '</body>'){
    $doc = $doc -replace '</body>', ($block + "`r`n</body>")
  }else{
    $doc += "`r`n$block`r`n"
  }
}

# 4) Guarda
Set-Content -LiteralPath $Html -Encoding UTF8 -Value $doc
Write-Host "✔ JSON embebido en $Html" -ForegroundColor Green
