[CmdletBinding()]
param(
  [string[]]$Roots
)

# Importa el filtro multimedia compartido
. "$PSScriptRoot\common\media-filter.ps1"

function Get-DefaultRoots {
  try {
    $fixed = Get-PSDrive -PSProvider FileSystem |
      Where-Object { $_.DisplayRoot -eq $null -and $_.Free -ne $null } |
      ForEach-Object { ($_.Root).TrimEnd('\') }
  } catch { $fixed = @("C:") }
  if(-not $fixed -or $fixed.Count -eq 0){ $fixed = @("C:") }
  return $fixed
}

function Normalize-Root([string]$r){
  if([string]::IsNullOrWhiteSpace($r)){ return $null }
  $r = $r.Trim().Trim('"').Trim("'")
  if($r.Length -eq 2 -and $r[1] -eq ':'){ return "$r\" }
  if($r.Length -ge 2 -and $r[1] -eq ':' -and $r[-1] -ne '\'){ return "$r\" }
  return $r
}

if(-not $Roots -or $Roots.Count -eq 0){
  $defaults = Get-DefaultRoots
  Write-Host "Unidades detectadas: $($defaults -join ', ')"
  $ans = Read-Host "¿Qué quieres escanear? (enter = todas; o ej. C:\,F:\,G:\)"
  if([string]::IsNullOrWhiteSpace($ans)){
    $Roots = $defaults
  } else {
    $Roots = $ans -split ',' | ForEach-Object { Normalize-Root $_ } | Where-Object { $_ }
  }
} else {
  $Roots = $Roots | ForEach-Object { Normalize-Root $_ } | Where-Object { $_ }
}

if(-not $Roots -or $Roots.Count -eq 0){
  Write-Warning "No hay raíces válidas para escanear. Saliendo."
  return
}

$HeartbeatEvery = 500        # línea cada 500 archivos multimedia
$ProgressEvery  = 100        # update de Write-Progress cada 100 archivos multimedia

foreach($root in $Roots){
  if(-not (Test-Path -LiteralPath $root)){
    Write-Warning "Raíz no encontrada: $root"
    continue
  }

  Write-Host ""
  Write-Host (">>> Escaneando SOLO multimedia en $root ...") -ForegroundColor Green

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $count = 0
  $activity = "Escaneando $root (multimedia)"
  $spinner  = @('|','/','-','\')
  $spinIdx  = 0

  try {
    Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue |
      Where-Object { Is-MediaFile $_ } |
      ForEach-Object {
        $count++

        if(($count % $HeartbeatEvery) -eq 0){
          $rate = "{0:n0}/s" -f (($count) / [math]::Max(1, $sw.Elapsed.TotalSeconds))
          Write-Host ("  · Multimedia procesados: {0:n0} | Tiempo: {1:c} | Velocidad: {2}" -f $count, $sw.Elapsed, $rate)
        }

        if(($count % $ProgressEvery) -eq 0){
          $spinIdx = ($spinIdx + 1) % $spinner.Count
          Write-Progress -Activity $activity `
                         -Status "$($spinner[$spinIdx]) Multimedia: $count  |  $($sw.Elapsed.ToString())" `
                         -PercentComplete 0
        }

        # (Lugar para lógica adicional por archivo si la necesitas)
      }

    Write-Progress -Activity $activity -Completed -Status "Completado"
    $sw.Stop()
    $rateFinal = "{0:n0}/s" -f (($count) / [math]::Max(1, $sw.Elapsed.TotalSeconds))
    Write-Host ("✔ Finalizado {0} → {1:n0} archivos multimedia en {2:c} ({3})" -f $root, $count, $sw.Elapsed, $rateFinal) -ForegroundColor Cyan

  } catch {
    Write-Warning ("Error durante el escaneo de {0}: {1}" -f $root, $_.Exception.Message)
  }
}

Write-Host ""
Write-Host "Todo listo. Puedes pasarlo con -Roots 'C:\','F:\' para seleccionar unidades." -ForegroundColor Yellow
