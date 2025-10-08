$ErrorActionPreference="Stop"
$inventoryJson="docs\data\inventory.json"
if(!(Test-Path $inventoryJson)){ throw "Falta $inventoryJson" }
$bytes=[IO.File]::ReadAllBytes($inventoryJson)
$b64=[Convert]::ToBase64String($bytes)
$h="docs\inventario_standalone.html"
$html = Get-Content -LiteralPath $h -Raw
# Sustituye el bloque Base64 dentro del <script id="INV_B64">...</script>
$html = $html -replace '(?s)(<script id="INV_B64"[^>]*>).*?(</script>)',("`$1`r`n"+$b64+"`r`n`$2")
Set-Content -LiteralPath $h -Value $html -Encoding UTF8
Start-Process $h
