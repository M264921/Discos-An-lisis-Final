param([Parameter(Mandatory)][string]$Drive,[string]$OutCsv)
$patterns = '\.(jpg|jpeg|png|gif|heic|tif|tiff|bmp|svg|mp4|m4v|mov|avi|mkv|webm|mp3|wav|flac|aac|ogg)$'
$OutCsv = $OutCsv ?? "docs\inventory\scan_$((($Drive[0])).ToUpper()).csv"
$progressEvery=500; $heartbeat=2000
$rows = New-Object System.Collections.Generic.List[object]
$sw=[diagnostics.stopwatch]::StartNew(); $c=0
Get-ChildItem -LiteralPath $Drive -Recurse -Force -File -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match $patterns } |
  ForEach-Object {
    $c++
    if(($c % $progressEvery) -eq 0){
      Write-Progress -Activity "Escaneando $Drive" -Status "$c archivos..." -PercentComplete 0
    }
    $sha = ""
    try{
      # SHA1 rápido (si tienes otra lib, cámbiala)
      $stream = $_.OpenRead()
      $sha1 = [System.Security.Cryptography.SHA1]::Create()
      $hash = ($sha1.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join ""
      $sha = $hash.ToUpper()
      $stream.Close()
    }catch{}
    $rows.Add([pscustomobject]@{
      sha=$sha; tipo=(($_.Extension).TrimStart('.').ToLower()); nombre=$_.Name; ruta=$_.DirectoryName;
      Drive=$Drive.Substring(0,2); tamano=[int64]$_.Length; fecha=($_.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ"))
    })
    if(($c % $heartbeat) -eq 0){
      $rate = "{0:n0}/s" -f ($c/[math]::Max(1,$sw.Elapsed.TotalSeconds))
      Write-Host ("  · Procesados: {0:n0} | Tiempo: {1:c} | Velocidad: {2}" -f $c,$sw.Elapsed,$rate)
    }
  }
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv
Write-Host "CSV listo: $OutCsv" -ForegroundColor Green
