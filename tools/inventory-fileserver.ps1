[CmdletBinding()]
param(
  [string]$ConfigPath,
  [string[]]$Prefix,
  [hashtable]$DriveMap,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Info {
  param([string]$Message)
  if (-not $Quiet) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'u'), $Message)
  }
}

$scriptRoot = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')).Path

if (-not $ConfigPath) {
  $ConfigPath = Join-Path $repoRoot 'inventory.config.json'
}

$config = $null
$resolvedConfig = $null
try {
  if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath)) {
    $resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).Path
    $jsonRaw = Get-Content -LiteralPath $resolvedConfig -Raw -Encoding UTF8
    if ($jsonRaw.Trim().Length -gt 0) {
      $config = $jsonRaw | ConvertFrom-Json
    }
  }
} catch {
  throw "No se pudo leer $ConfigPath. Detalle: $($_.Exception.Message)"
}

if (-not $Prefix -or $Prefix.Count -eq 0) {
  if ($config -and $config.listenerPrefixes) {
    $Prefix = @($config.listenerPrefixes | ForEach-Object { [string]$_ })
  } else {
    $Prefix = @('http://+:8765/')
  }
}

function Normalize-Root {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  $full = (Resolve-Path -LiteralPath $Path).Path
  if (-not $full.EndsWith([IO.Path]::DirectorySeparatorChar)) {
    $full += [IO.Path]::DirectorySeparatorChar
  }
  return $full
}

$driveRoots = @{}

if ($DriveMap -and $DriveMap.Keys.Count -gt 0) {
  foreach ($key in $DriveMap.Keys) {
    $rootPath = Normalize-Root $DriveMap[$key]
    if ($rootPath) {
      $driveRoots[$key.ToString().TrimEnd(':').ToUpperInvariant()] = $rootPath
    }
  }
} elseif ($config -and $config.driveMappings) {
  foreach ($entry in $config.driveMappings.PSObject.Properties) {
    $rootPath = Normalize-Root $entry.Value
    if ($rootPath) {
      $driveRoots[$entry.Name.TrimEnd(':').ToUpperInvariant()] = $rootPath
    }
  }
} else {
  Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $driveRoots[$_.Name.ToUpperInvariant()] = Normalize-Root $_.Root
  }
}

if ($driveRoots.Count -eq 0) {
  throw "No hay unidades configuradas para exponer."
}

$publicBaseUrl = ''
if ($config -and $config.publicBaseUrl) {
  $publicBaseUrl = [string]$config.publicBaseUrl
}

Write-Info ("Base de contenido: {0}" -f ($publicBaseUrl -ne '' ? $publicBaseUrl : '(sin configurar)'))
Write-Info ("Unidades expuestas:")
foreach ($entry in $driveRoots.GetEnumerator() | Sort-Object Key) {
  Write-Info ("  {0}: {1}" -f $entry.Key, $entry.Value)
}

$contentTypes = @{
  '.7z'  = 'application/x-7z-compressed'
  '.aac' = 'audio/aac'
  '.avi' = 'video/x-msvideo'
  '.bmp' = 'image/bmp'
  '.csv' = 'text/csv'
  '.flac' = 'audio/flac'
  '.gif' = 'image/gif'
  '.ico' = 'image/x-icon'
  '.jpg' = 'image/jpeg'
  '.jpeg' = 'image/jpeg'
  '.json' = 'application/json'
  '.m4a' = 'audio/mp4'
  '.mkv' = 'video/x-matroska'
  '.mov' = 'video/quicktime'
  '.mp3' = 'audio/mpeg'
  '.mp4' = 'video/mp4'
  '.oga' = 'audio/ogg'
  '.ogg' = 'audio/ogg'
  '.ogv' = 'video/ogg'
  '.pdf' = 'application/pdf'
  '.png' = 'image/png'
  '.svg' = 'image/svg+xml'
  '.txt' = 'text/plain; charset=utf-8'
  '.wav' = 'audio/wav'
  '.webm' = 'video/webm'
  '.webp' = 'image/webp'
  '.xml' = 'application/xml'
  '.zip' = 'application/zip'
}

function Get-ContentType {
  param([string]$Path)
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($contentTypes.ContainsKey($ext)) {
    return $contentTypes[$ext]
  }
  if ($ext -match '^\.(txt|log)$') {
    return 'text/plain; charset=utf-8'
  }
  return 'application/octet-stream'
}

$listener = [System.Net.HttpListener]::new()
foreach ($pref in $Prefix) {
  $listener.Prefixes.Add($pref)
}

try {
  $listener.Start()
} catch {
  throw "No se pudo iniciar HttpListener en ${Prefix}. Ejecuta PowerShell como administrador o registra la URL con 'netsh http add urlacl'. Error: $($_.Exception.Message)"
}

Write-Info ("Servidor iniciado en: {0}" -f ($Prefix -join ', '))
Write-Info "Pulsa Ctrl+C para detener."

$cancelled = $false
$handler = {
  $global:cancelled = $true
  Write-Info "Deteniendo servidor..."
  $listener.Stop()
}
[Console]::CancelKeyPress += $handler

function Send-Error {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [int]$StatusCode,
    [string]$Message
  )
  try {
    $Response.StatusCode = $StatusCode
    if ($Message) {
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
      $Response.ContentType = 'text/plain; charset=utf-8'
      $Response.ContentLength64 = $bytes.Length
      $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
      $Response.ContentLength64 = 0
    }
  } finally {
    $Response.OutputStream.Close()
  }
}

function Handle-File {
  param(
    [System.Net.HttpListenerRequest]$Request,
    [System.Net.HttpListenerResponse]$Response
  )

  $segments = $Request.Url.AbsolutePath.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($segments.Length -lt 2 -or $segments[0].ToLowerInvariant() -ne 'files') {
    Send-Error -Response $Response -StatusCode 404 -Message "Ruta no encontrada."
    return
  }

  $driveToken = $segments[1].TrimEnd(':').ToUpperInvariant()
  if (-not $driveRoots.ContainsKey($driveToken)) {
    Send-Error -Response $Response -StatusCode 404 -Message "Unidad no expuesta."
    return
  }

  $parts = @()
  for ($i = 2; $i -lt $segments.Length; $i++) {
    $raw = [System.Uri]::UnescapeDataString($segments[$i])
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq '.' -or $raw -eq '..' -or $raw.Contains('..')) {
      Send-Error -Response $Response -StatusCode 400 -Message "Ruta no permitida."
      return
    }
    $parts += $raw
  }

  $root = $driveRoots[$driveToken]
  $target = $root
  foreach ($part in $parts) {
    $target = Join-Path $target $part
  }
  $target = [IO.Path]::GetFullPath($target)

  if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    Send-Error -Response $Response -StatusCode 403 -Message "Acceso denegado."
    return
  }

  if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
    if (Test-Path -LiteralPath $target -PathType Container) {
      Send-Error -Response $Response -StatusCode 403 -Message "No se sirve contenido de carpetas."
    } else {
      Send-Error -Response $Response -StatusCode 404 -Message "Archivo no encontrado."
    }
    return
  }

  $fileInfo = Get-Item -LiteralPath $target
  $Response.StatusCode = 200
  $Response.SendChunked = $false
  $Response.ContentType = Get-ContentType -Path $target
  $Response.ContentLength64 = $fileInfo.Length
  $Response.AddHeader('Content-Disposition', "inline; filename=`"$($fileInfo.Name)`"")
  $Response.AddHeader('Cache-Control', 'no-cache')

  if ($Request.HttpMethod -eq 'HEAD') {
    $Response.OutputStream.Close()
    return
  }

  $buffer = New-Object byte[] 65536
  $stream = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    while ($true) {
      $read = $stream.Read($buffer, 0, $buffer.Length)
      if ($read -le 0) { break }
      $Response.OutputStream.Write($buffer, 0, $read)
    }
  } finally {
    $stream.Dispose()
    $Response.OutputStream.Close()
  }
}

try {
  while ($listener.IsListening) {
    try {
      $context = $listener.GetContext()
    } catch {
      if ($listener.IsListening) {
        Write-Info ("Error al aceptar conexion: {0}" -f $_.Exception.Message)
      }
      continue
    }

    $request = $context.Request
    $response = $context.Response
    Write-Info ("{0} {1}" -f $request.HttpMethod, $request.Url.AbsolutePath)

    try {
      switch -Regex ($request.Url.AbsolutePath) {
        '^/healthz/?$' {
          $response.StatusCode = 200
          $response.ContentLength64 = 0
          $response.OutputStream.Close()
        }
        '^/files/' {
          Handle-File -Request $request -Response $response
        }
        default {
          Send-Error -Response $response -StatusCode 404 -Message "Ruta no encontrada."
        }
      }
    } catch {
      Write-Info ("Error atendiendo solicitud: {0}" -f $_.Exception.Message)
      if ($response.OutputStream.CanWrite) {
        Send-Error -Response $response -StatusCode 500 -Message "Error interno del servidor."
      }
    }
  }
} finally {
  if ($listener.IsListening) {
    $listener.Stop()
  }
  [Console]::CancelKeyPress -= $handler
  if ($cancelled) {
    Write-Info "Servidor detenido."
  }
}
