param(
  [string]$InventoryDir = "docs\inventory",
  [string]$OutCsv = "docs\hash_data.csv"
)
$scans = Get-ChildItem -LiteralPath $InventoryDir -Filter "scan_*.csv" -ErrorAction SilentlyContinue
if(!$scans){ Write-Host "No hay scans. (esperado: scan_C.csv, scan_F.csv…)" -ForegroundColor Yellow; exit 1 }
$all = foreach($f in $scans){ Import-Csv -LiteralPath $f }
$all | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv
Write-Host "Combinado -> $OutCsv ($($all.Count) filas)" -ForegroundColor Cyan
