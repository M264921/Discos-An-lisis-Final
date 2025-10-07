[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$Drive,                 # ej: C:  o  D:
  [Parameter(Mandatory=$true)]
  [string]$OutCsv                 # ej: docs\inventory\scan_C.csv
)

# Importa filtro multimedia común
. "$PSScriptRoot\common\media-filter.ps1"

# Normaliza Drive a "X:\"
if($Drive.Length -eq 2 -and $Drive[1] -eq ':'){ $Drive = "$Drive\" }
elseif($Drive.Length -ge 2 -and $Drive[1] -eq ':' -and $Drive[-1] -ne '\'){ $Drive = "$Drive\" }

if(-not (Test-Path -LiteralPath $Drive)){
  throw "Unidad no encontrada: $Drive"
}

# Asegura carpeta destino
$dir = Split-Path -Parent $OutCsv
if($dir){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }

Write-Host (">>> Hasheando SOLO multimedia en $Drive → $OutCsv") -ForegroundColor Green

$sw   = [System.Diagnostics.Stopwatch]::StartNew()
$cnt  = 0
$ok   = 0
$fail = 0
$heartbeatEvery = 250
$progressEvery  = 100
$spinner = @('|','/','-','\')
$spinIdx = 0

try{
  Get-ChildItem -LiteralPath $Drive -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { Is-MediaFile $_ } |
    ForEach-Object {
      $cnt++

      if(($cnt % $heartbeatEvery) -eq 0){
        $rate = "{0:n0}/s" -f (($cnt) / [Math]::Max(1,$sw.Elapsed.TotalSeconds))
        Write-Host ("  · Multimedia vistos: {0:n0} | Tiempo: {1:c} | Velocidad: {2}" -f $cnt, $sw.Elapsed, $rate)
      }
      if(($cnt % $progressEvery) -eq 0){
        $spinIdx = ($spinIdx + 1) % $spinner.Count
        Write-Progress -Activity "Hasheando $Drive (multimedia)" -Status "$($spinner[$spinIdx]) Archivos: $cnt" -PercentComplete 0
      }

      try{
        $h = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName -ErrorAction Stop
        $ok++
        [pscustomobject]@{
          Path           = $_.FullName
          Length         = $_.Length
          LastWriteTime  = $_.LastWriteTimeUtc
          Hash           = $h.Hash
          Drive          = $Drive.TrimEnd('\')
          Ext            = $_.Extension
        }
      } catch {
        $fail++
        $null # saltar
      }
    } | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv
}
finally{
  Write-Progress -Activity "Hasheando $Drive (multimedia)" -Completed -Status "Completado"
  $sw.Stop()
  Write-Host ("✔ CSV listo: {0}" -f $OutCsv) -ForegroundColor Cyan
  Write-Host ("   Vistos: {0:n0} | OK: {1:n0} | Fallidos: {2:n0} | Tiempo: {3:c}" -f $cnt, $ok, $fail, $sw.Elapsed)
}
