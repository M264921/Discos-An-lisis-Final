param(
  [switch]$HashNow,
  [string[]]$Drives
)
function Normalize-Root([string]$r){
  if([string]::IsNullOrWhiteSpace($r)){return $null}
  $r=$r.Trim().Trim('"').Trim("'")
  if($r.Length -eq 2 -and $r[1] -eq ':'){return "$r\"}
  if($r.Length -ge 2 -and $r[1] -eq ':' -and $r[-1] -ne '\'){return "$r\"}
  return $r
}
$defaults = (Get-PSDrive -PSProvider FileSystem | Where-Object {$_.DisplayRoot -eq $null -and $_.Free -ne $null}).Root |
  ForEach-Object { ($_).TrimEnd('\') }
if(!$Drives){ $Drives = $defaults }
$Drives = $Drives | ForEach-Object { Normalize-Root $_ } | Where-Object { $_ }

Write-Host "Unidades detectadas: $($defaults -join ', ')" -ForegroundColor DarkCyan
if($HashNow){
  foreach($d in $Drives){
    if(!(Test-Path $d)){ Write-Warning "No existe $d"; continue }
    $out = "docs\inventory\scan_$((($d[0])).ToUpper()).csv"
    Write-Host "Hashing SOLO multimedia en $d → $out" -ForegroundColor Cyan
    pwsh -NoProfile -ExecutionPolicy Bypass -File tools\hash-drive-to-csv.ps1 -Drive $d -OutCsv $out
  }
}else{
  Write-Host "Saltando hash (HashNow no indicado). Continuamos con merge + JSON + HTML..." -ForegroundColor Yellow
}

pwsh -NoProfile -ExecutionPolicy Bypass -File tools\merge-scans.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File tools\csv-to-inventory-json.ps1

# asegúrate del viewer y el offline
& tools\ensure-viewers.ps1

Write-Host ("`n✔ HTML listo: " + (Resolve-Path "docs\view.html")) -ForegroundColor Green
Write-Host ("✔ HTML offline (fetch JSON): " + (Resolve-Path "docs\inventario_interactivo_offline.html")) -ForegroundColor Green
