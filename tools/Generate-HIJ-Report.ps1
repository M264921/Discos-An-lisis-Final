[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Push,
    [switch]$Preview,
    [string]$CommitMessage = 'chore(docs): refresh hij report'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptRoot
$docsDir = Join-Path $repoRoot 'docs'

if (-not (Test-Path $docsDir)) {
    New-Item -ItemType Directory -Path $docsDir | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logDir = Join-Path $repoRoot "logs_$timestamp"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir 'build.log'

function Write-Log {
    param([string]$Message, [System.ConsoleColor]$Color = [System.ConsoleColor]::Cyan)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$stamp] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line -ForegroundColor $Color
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory = $repoRoot,
        [string]$Description = 'Ejecutando comando'
    )
    Write-Log -Message ("{0}: {1} {2}" -f $Description, $FilePath, ($Arguments -join ' ')) -Color Yellow
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    if ($Arguments) {
        foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add($arg) }
    }
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($stdout) { Add-Content -Path $logFile -Value $stdout.TrimEnd(); Write-Host $stdout }
    if ($stderr) { Add-Content -Path $logFile -Value $stderr.TrimEnd(); Write-Host $stderr -ForegroundColor Red }
    if ($process.ExitCode -ne 0) {
        throw "El comando '$FilePath' terminó con código $($process.ExitCode)"
    }
}

Push-Location $repoRoot
try {
    Write-Log -Message "Repositorio: $repoRoot"

    $python = Get-Command python -ErrorAction Stop
    Write-Log -Message "Python detectado en: $($python.Source)" -Color Green

    Invoke-External -FilePath $python.Source -Arguments @((Join-Path $scriptRoot 'generate_duplicates_table.py')) -Description 'Generando Listado_Duplicados_interactivo.html'

    $artifacts = @(
        @{ Source = 'informe_cronologico.html'; Target = 'index.html' },
        @{ Source = 'Listado_H_interactivo.html'; Target = 'Listado_H_interactivo.html' },
        @{ Source = 'Listado_I_interactivo.html'; Target = 'Listado_I_interactivo.html' },
        @{ Source = 'Listado_J_interactivo.html'; Target = 'Listado_J_interactivo.html' },
        @{ Source = 'dupes_confirmed.csv'; Target = 'dupes_confirmed.csv' }
    )

    foreach ($item in $artifacts) {
        $sourcePath = Join-Path $repoRoot $item.Source
        if (-not (Test-Path $sourcePath)) {
            Write-Log -Message "No se encontró $($item.Source), se omite" -Color DarkYellow
            continue
        }
        $destination = Join-Path $docsDir $item.Target
        Copy-Item -Path $sourcePath -Destination $destination -Force
        Write-Log -Message "Actualizado $($item.Target)" -Color Green
    }

    if ($Preview) {
        Write-Log -Message 'Generación en modo preview: no se realizará push.' -Color Yellow
        $Push = $false
    }

    if ($Push) {
        $pathsToStage = @(
            'docs/index.html',
            'docs/Listado_Duplicados_interactivo.html',
            'docs/Listado_H_interactivo.html',
            'docs/Listado_I_interactivo.html',
            'docs/Listado_J_interactivo.html',
            'docs/dupes_confirmed.csv',
            'informe_cronologico.html'
        )
        foreach ($path in $pathsToStage) {
            if (Test-Path $path) {
                Invoke-External -FilePath 'git' -Arguments @('add', $path) -Description "git add $path"
            }
        }
        $status = (& git status --short)
        if (-not $status) {
            Write-Log -Message 'No hay cambios para commitear.' -Color Yellow
        } else {
            if ($PSCmdlet.ShouldProcess('git commit', $CommitMessage)) {
                Invoke-External -FilePath 'git' -Arguments @('commit', '-m', $CommitMessage) -Description 'git commit'
            }
            Invoke-External -FilePath 'git' -Arguments @('push') -Description 'git push'
        }
    } else {
        Write-Log -Message 'Ejecución completada sin push. Revisa docs/ y ejecuta git status para validar.' -Color Green
    }

    Write-Log -Message "Build log disponible en $logFile" -Color Gray
} finally {
    Pop-Location
}





