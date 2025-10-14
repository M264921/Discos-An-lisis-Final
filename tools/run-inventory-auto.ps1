# Requires PowerShell 7 or later
<#
    .SYNOPSIS
        Automates the inventory scan and publication process for the disc
        analysis project with minimal user interaction.

    .DESCRIPTION
        This helper script is designed for less technical users who should
        only have to click through a couple of windows to update the
        inventory on GitHub Pages. It leverages the existing PowerShell
        helper scripts in the tools directory to scan a fixed drive,
        generate the inventory JSON and GZip files, and then optionally
        commit and push the results back to the repository.  Before
        running this script, ensure that Git is installed and configured
        to push without prompting (for example, by caching credentials via
        the Git Credential Manager or by using an access token).

    .PARAMETER Drive
        The drive letter or root folder to scan.  Defaults to `K:\` if
        unspecified.

    .PARAMETER Filter
        The media filter to apply when scanning.  Acceptable values are
        `Media` or `Todo`.  Defaults to `Media`.

    .NOTES
        Author: Community contribution
        Last modified: ${env:USERNAME} on $(Get-Date -Format 'yyyy-MM-dd')

    .EXAMPLE
        # Launch the GUI, scan K:\ and publish automatically when
        # prompted.
        ./run-inventory-auto.ps1

#>

[CmdletBinding()]
param(
    [string]$Drive = 'K:\\',
    [ValidateSet('Media','Todo')]
    [string]$Filter = 'Media'
)

Set-StrictMode -Version Latest

try {
    # Load Windows Forms for GUI message boxes.
    Add-Type -AssemblyName System.Windows.Forms
} catch {
    Write-Warning "Failed to load Windows Forms assemblies. Ensure you're running Windows PowerShell or PowerShell 7 on Windows."
    throw
}

function Show-YesNoQuestion {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [Parameter(Mandatory)] [string]$Title
    )
    return [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
}

function Show-Info {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [string]$Title = 'Information'
    )
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

# Determine repository root based on script location
$scriptDir = $PSScriptRoot
$repoRoot = (Get-Item $scriptDir).Parent.FullName

if (-not (Test-Path $repoRoot)) {
    Show-Info -Message "Cannot determine repository root from $scriptDir." -Title 'Error'
    exit 1
}

# Confirm start of scanning
$resp = Show-YesNoQuestion -Message "Scan drive $Drive with filter '$Filter'?" -Title 'Start Inventory Scan'
if ($resp -ne [System.Windows.Forms.DialogResult]::Yes) {
    Show-Info -Message 'Operation cancelled by user.' -Title 'Cancelled'
    exit 0
}

# Build paths for intermediate and output files
$csvFile  = Join-Path $repoRoot 'inventory_by_folder.csv'
$jsonFile = Join-Path $repoRoot 'data' 'inventory.json'
$gzipFile = Join-Path $repoRoot 'data' 'inventory.json.gz'

try {
    # Ensure output directory exists
    New-Item -ItemType Directory -Path (Join-Path $repoRoot 'data') -ErrorAction SilentlyContinue | Out-Null

    # Step 1: scan drive to CSV
    # Run the drive scan script.  The parameter name for the filter is
    # -ContentFilter in hash-drive-to-csv.ps1 (Media/Otros/Todo).
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'hash-drive-to-csv.ps1') `
        -Drive $Drive `
        -OutCsv $csvFile `
        -ContentFilter $Filter

    # Step 2: convert CSV to JSON inventory.  csv-to-inventory-json.ps1 expects
    # -CsvPath and -JsonPath.
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'csv-to-inventory-json.ps1') `
        -CsvPath $csvFile `
        -JsonPath $jsonFile

    # Step 3: compress JSON to .gz for Pages.  minify-and-gzip-inventory.ps1
    # takes a data directory and source filename, then writes
    # inventory.min.json and inventory.json.gz into that directory.
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptDir 'minify-and-gzip-inventory.ps1') `
        -DataDir (Join-Path $repoRoot 'data') `
        -Source (Split-Path -Leaf $jsonFile)
} catch {
    Show-Info -Message "An error occurred while generating the inventory: $_" -Title 'Error'
    exit 1
}

# Ask user if they want to publish changes
$resp2 = Show-YesNoQuestion -Message 'Inventory generated successfully. Commit and push to GitHub?' -Title 'Publish Inventory'
if ($resp2 -ne [System.Windows.Forms.DialogResult]::Yes) {
    Show-Info -Message "Inventory file generated at $gzipFile. No changes were published." -Title 'Finished'
    exit 0
}

# Perform git operations
Set-Location $repoRoot
try {
    git add $gzipFile 2>&1 | Out-String | Write-Verbose
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $commitMsg = "auto: update inventory $timestamp"
    git commit -m $commitMsg 2>&1 | Out-String | Write-Verbose
    git push 2>&1 | Out-String | Write-Verbose
    Show-Info -Message 'Inventory committed and pushed successfully.' -Title 'Success'
} catch {
    Show-Info -Message "Failed to publish changes: $_" -Title 'Git Error'
    exit 1
}