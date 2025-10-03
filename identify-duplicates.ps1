param(
    [string]$Root = 'J:\',
    [string]$TargetDir = 'J:\duplicados',
    [string]$ReportDir = 'J:\duplicados'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir | Out-Null
}

$targetPrefix = ([System.IO.Path]::GetFullPath($TargetDir.TrimEnd('\'))) + '\'
$progressLogPath = Join-Path $ReportDir 'progreso_identificar_duplicados.log'
$duplicatesCsvPath = Join-Path $ReportDir 'duplicados_pendientes.csv'
$hashSummaryPath = Join-Path $ReportDir 'hash_summary.json'
$errorLogPath = Join-Path $ReportDir 'hash_errors.log'

Remove-Item $progressLogPath,$duplicatesCsvPath,$hashSummaryPath,$errorLogPath -ErrorAction SilentlyContinue

$progressStream = [System.IO.StreamWriter]::new($progressLogPath, $false)
$progressStream.AutoFlush = $true

try {
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike "$targetPrefix*" }
    $totalFiles = $files.Count
    $progressStream.WriteLine("Total files scanned: $totalFiles")
    Write-Host "Total files scanned: $totalFiles"

    $groupsByLength = $files | Group-Object Length
    $groupsToHash = $groupsByLength | Where-Object { $_.Count -gt 1 }
    $filesToHash = ($groupsToHash | Measure-Object -Property Count -Sum).Sum
    if (-not $filesToHash) { $filesToHash = 0 }
    $progressStream.WriteLine("Files requiring hash: $filesToHash")
    Write-Host "Files requiring hash: $filesToHash"

    $hashLookup = @{}
    $hashIndex = 0
    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($group in $groupsToHash) {
        foreach ($file in $group.Group | Sort-Object FullName) {
            $hashIndex++
            $percent = 0
            if ($filesToHash -gt 0) {
                $percent = [Math]::Round(($hashIndex / $filesToHash) * 100, 2)
            }

            if ($hashIndex -le 10 -or ($hashIndex % 100) -eq 0 -or $hashIndex -eq $filesToHash) {
                $msg = "[{0}/{1}] Hashing {2} ({3} bytes)" -f $hashIndex, $filesToHash, $file.FullName, $file.Length
                Write-Host $msg
                $progressStream.WriteLine($msg)
            }

            Write-Progress -Activity "Hashing potential duplicates" -Status "$hashIndex of $filesToHash" -PercentComplete $percent

            try {
                $hashValue = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                if (-not $hashLookup.ContainsKey($hashValue)) {
                    $hashLookup[$hashValue] = New-Object System.Collections.Generic.List[object]
                }
                $hashLookup[$hashValue].Add([PSCustomObject]@{
                    FullName = $file.FullName
                    Length = $file.Length
                    LastWriteTime = $file.LastWriteTime
                })
            } catch {
                $err = "Failed hashing: {0} -> {1}" -f $file.FullName, $_.Exception.Message
                Write-Warning $err
                $progressStream.WriteLine($err)
                Add-Content -Path $errorLogPath -Value $err
            }
        }
    }
    Write-Progress -Activity "Hashing potential duplicates" -Completed
    $watch.Stop()
    $progressStream.WriteLine("Hashing complete in {0} seconds" -f [Math]::Round($watch.Elapsed.TotalSeconds,2))
    Write-Host ("Hashing complete in {0} seconds" -f [Math]::Round($watch.Elapsed.TotalSeconds,2))

    $duplicateRecords = New-Object System.Collections.Generic.List[object]
    foreach ($hashKey in $hashLookup.Keys) {
        $entries = $hashLookup[$hashKey]
        if ($entries.Count -gt 1) {
            $sortedEntries = $entries | Sort-Object LastWriteTime, FullName
            $original = $sortedEntries[0]
            for ($i = 1; $i -lt $sortedEntries.Count; $i++) {
                $dup = $sortedEntries[$i]
                $duplicateRecords.Add([PSCustomObject]@{
                    Hash = $hashKey
                    SizeBytes = $dup.Length
                    OriginalPath = $original.FullName
                    DuplicatePath = $dup.FullName
                    DuplicateLastWriteTime = $dup.LastWriteTime
                })
            }
        }
    }

    $duplicateRecords | Export-Csv -Path $duplicatesCsvPath -NoTypeInformation

    $hashSummary = $hashLookup.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | ForEach-Object {
        [PSCustomObject]@{
            Hash = $_.Key
            Count = $_.Value.Count
            TotalBytes = ($_.Value | Measure-Object Length -Sum).Sum
            Representative = ($_.Value | Sort-Object LastWriteTime, FullName)[0].FullName
        }
    }
    $hashSummary | ConvertTo-Json -Depth 4 | Set-Content -Path $hashSummaryPath

    $progressStream.WriteLine("Duplicate pairs: {0}" -f $duplicateRecords.Count)
    Write-Host "Duplicate pairs identified: $($duplicateRecords.Count)"
    Write-Host "CSV report: $duplicatesCsvPath"
    Write-Host "Hash summary: $hashSummaryPath"
} finally {
    $progressStream.Dispose()
}
