param(
    [string]$Root = "H:\",
    [string]$DuplicateDirName = "duplicados"
)

$ErrorActionPreference = 'Stop'

$duplicateDir = Join-Path $Root $DuplicateDirName
$report = Join-Path $duplicateDir 'hash_data.csv'
if (!(Test-Path $report)) {
    Write-Error "Hash data file not found at $report"
    exit 1
}

$mediaExtensions = @('.jpg','.jpeg','.png','.gif','.bmp','.tif','.tiff','.heic','.heif','.raw','.nef','.cr2','.arw','.mp4','.mov','.avi','.mkv','.wmv','.flv','.mpg','.mpeg','.mts','.m2ts','.3gp','.m4v','.webm','.ts','.aac','.mp3','.wav','.flac')
$lowPriorityExtensions = @('.db','.info')

$hashData = Import-Csv -Path $report
$validData = $hashData | Where-Object { $_.Hash -and $_.Hash.Trim() -ne '' -and ($_.Error -eq '' -or $_.Error -eq $null) }

if ($validData.Count -eq 0) {
    Write-Host 'No valid hashed entries to process.'
    exit 0
}

$groups = $validData | Group-Object -Property Hash
$duplicateGroups = $groups | Where-Object { $_.Count -gt 1 }
$totalGroups = $duplicateGroups.Count
$totalMoves = (($duplicateGroups | ForEach-Object { $_.Count - 1 }) | Measure-Object -Sum).Sum
if (-not $totalMoves) { $totalMoves = 0 }

Write-Host "Duplicate hash groups: $totalGroups"
Write-Host "Total files to move: $totalMoves"

$logPath = Join-Path $duplicateDir 'duplicate_moves.log'
$csvPath = Join-Path $duplicateDir 'duplicate_moves.csv'
$summaryPath = Join-Path $duplicateDir 'duplicate_summary.json'
$errorCsvPath = Join-Path $duplicateDir 'duplicate_errors.csv'

if (Test-Path $csvPath) { Remove-Item $csvPath -Force }
if (Test-Path $logPath) { Remove-Item $logPath -Force }
if (Test-Path $summaryPath) { Remove-Item $summaryPath -Force }
if (Test-Path $errorCsvPath) { Remove-Item $errorCsvPath -Force }

$moveRecords = New-Object System.Collections.Generic.List[object]
$logEntries = New-Object System.Collections.Generic.List[string]
$errorRecords = New-Object System.Collections.Generic.List[object]

$movedCount = 0
$bytesMoved = [int64]0
$processedGroups = 0

foreach ($group in $duplicateGroups) {
    $processedGroups++
    $fileInfos = $group.Group | ForEach-Object {
        $ext = $_.Extension
        $extLower = if ($ext) { $ext.ToString().ToLowerInvariant() } else { '' }
        [PSCustomObject]@{
            FullName        = $_.FullName
            Hash            = $_.Hash
            Extension       = $_.Extension
            ExtensionLower  = $extLower
            Length          = [int64]$_.Length
        }
    }

    $ordered = $fileInfos | Sort-Object @{Expression = {
            $ext = $_.ExtensionLower
            if ($mediaExtensions -contains $ext) { 0 }
            elseif ($lowPriorityExtensions -contains $ext) { 2 }
            else { 1 }
        }}, @{Expression = { $_.FullName }}

    $keep = $ordered | Select-Object -First 1

    foreach ($file in $fileInfos) {
        if ($file.FullName -eq $keep.FullName) { continue }
        $relativePath = $file.FullName.Substring($Root.Length)
        $destination = Join-Path $duplicateDir $relativePath
        $destinationDir = Split-Path -Path $destination -Parent
        if (-not (Test-Path $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }
        $finalDestination = $destination
        if (Test-Path $finalDestination) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($destination)
            $extension = [System.IO.Path]::GetExtension($destination)
            $counter = 1
            do {
                if ($extension) {
                    $newName = "${baseName}_dup${counter}${extension}"
                } else {
                    $newName = "${baseName}_dup${counter}"
                }
                $finalDestination = Join-Path $destinationDir $newName
                $counter++
            } while (Test-Path $finalDestination)
        }
        try {
            Move-Item -LiteralPath $file.FullName -Destination $finalDestination -Force
            $movedCount++
            $bytesMoved += $file.Length
            $timestamp = Get-Date -Format 's'
            $logEntries.Add("$timestamp|MOVE|$($file.FullName)|$finalDestination|$($file.Hash)") > $null
            $moveRecords.Add([PSCustomObject]@{
                OriginalPath    = $file.FullName
                DestinationPath = $finalDestination
                Hash            = $file.Hash
                Length          = $file.Length
                Extension       = $file.ExtensionLower
            }) > $null
        } catch {
            $errorRecords.Add([PSCustomObject]@{
                OriginalPath = $file.FullName
                Hash         = $file.Hash
                Message      = $_.Exception.Message
            }) > $null
        }
    }
    if ($totalMoves -gt 0) {
        $percent = [int](($movedCount / $totalMoves) * 100)
    } else {
        $percent = 100
    }
    Write-Progress -Activity 'Moving duplicates' -Status "$movedCount of $totalMoves" -PercentComplete $percent
}

if ($moveRecords.Count -gt 0) {
    $moveRecords | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
}
if ($logEntries.Count -gt 0) {
    $logEntries | Set-Content -Path $logPath -Encoding UTF8
}
$summary = [PSCustomObject]@{
    RootPath                 = $Root
    DuplicateFolder          = $duplicateDir
    DuplicateHashGroups      = $totalGroups
    FilesMoved               = $movedCount
    BytesMoved               = $bytesMoved
    Errors                   = $errorRecords.Count
}
$summary | ConvertTo-Json | Set-Content -Path $summaryPath -Encoding UTF8
if ($errorRecords.Count -gt 0) {
    $errorRecords | Export-Csv -Path $errorCsvPath -NoTypeInformation -Encoding UTF8
    Write-Warning "Encountered $($errorRecords.Count) errors; see $errorCsvPath"
}

Write-Host "Files moved: $movedCount"
Write-Host "Bytes moved: $bytesMoved"
Write-Host "Summary written to $summaryPath"
