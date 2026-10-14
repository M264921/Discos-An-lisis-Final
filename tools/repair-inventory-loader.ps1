[CmdletBinding()]
param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$out = Join-Path $RepoRoot 'docs\assets\inventory-loader.js'
$null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out)
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'inventory-loader.template.js') -Destination $out -Force
& (Join-Path $PSScriptRoot 'sync-inventory-data.ps1') -JsonPath (Join-Path $RepoRoot 'docs\data\inventory.json')
