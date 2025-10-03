param(
    [string]$DuplicatesCsv = 'J:\duplicados\duplicados_pendientes.csv',
    [string]$TargetDir = 'J:\duplicados'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $DuplicatesCsv)) {
    throw "Duplicates CSV not found: $DuplicatesCsv"
}

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir | Out-Null
}

$moveLogPath = Join-Path $TargetDir 'movimientos_duplicados.log'
$skippedLogPath = Join-Path $TargetDir 'duplicados_omitidos.log'
$finalCsvPath = Join-Path $TargetDir 'duplicados_movidos.csv'

Remove-Item $moveLogPath,$skippedLogPath,$finalCsvPath -ErrorAction SilentlyContinue

$moveStream = [System.IO.StreamWriter]::new($moveLogPath, $false)
$moveStream.AutoFlush = $true
$skippedStream = [System.IO.StreamWriter]::new($skippedLogPath, $false)
$skippedStream.AutoFlush = $true

try {
    $records = Import-Csv -Path $DuplicatesCsv
    $total = $records.Count
    Write-Host "Duplicates to move: $total"
    $moveStream.WriteLine("Duplicates to move: $total")

    $movedRecords = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($record in $records) {
        $index++
        $source = $record.DuplicatePath
        $hash = $record.Hash
        $size = [int64]$record.SizeBytes
        $statusPrefix = "[{0}/{1}]" -f $index, $total
        $progressPercent = 0
        if ($total -gt 0) {
            $progressPercent = [Math]::Round(($index / $total) * 100, 2)
        }
        Write-Progress -Activity "Moving duplicates" -Status "$index of $total" -PercentComplete $progressPercent

        if (-not (Test-Path -LiteralPath $source)) {
            $msg = "$statusPrefix Missing source: $source"
            Write-Warning $msg
            $skippedStream.WriteLine($msg)
            continue
        }

        $fullSource = [System.IO.Path]::GetFullPath($source)
        if (-not $fullSource.StartsWith('J:\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $msg = "$statusPrefix Outside J: $fullSource"
            Write-Warning $msg
            $skippedStream.WriteLine($msg)
            continue
        }

        $relative = $fullSource.Substring(3) # remove 'J:\'
        $destinationPath = Join-Path $TargetDir $relative
        $destinationDir = Split-Path -Path $destinationPath -Parent
        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        $finalDestination = $destinationPath
        $counter = 1
        while (Test-Path -LiteralPath $finalDestination) {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($destinationPath)
            $extension = [System.IO.Path]::GetExtension($destinationPath)
            $dir = Split-Path -Path $destinationPath -Parent
            $finalDestination = Join-Path $dir ($fileName + "_dup" + $counter + $extension)
            $counter++
        }

        $msg = "$statusPrefix Moving '$source' -> '$finalDestination'"
        Write-Host $msg
        $moveStream.WriteLine($msg)

        try {
            Move-Item -LiteralPath $source -Destination $finalDestination
            $movedRecords.Add([PSCustomObject]@{
                Hash = $hash
                SizeBytes = $size
                OriginalPath = $record.OriginalPath
                DuplicateSource = $source
                NewPath = $finalDestination
                MovedAt = (Get-Date)
            })
        } catch {
            $err = "$statusPrefix Failed to move '$source': $($_.Exception.Message)"
            Write-Warning $err
            $skippedStream.WriteLine($err)
        }
    }

    $movedRecords | Export-Csv -Path $finalCsvPath -NoTypeInformation
    Write-Host "Moved files logged to $finalCsvPath"
    $moveStream.WriteLine("Moved files logged to $finalCsvPath")
} finally {
    Write-Progress -Activity "Moving duplicates" -Completed
    $moveStream.Dispose()
    $skippedStream.Dispose()
}
