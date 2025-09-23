param(
    [string]$Root = "H:\",
    [string]$Output = "$env:USERPROFILE\Desktop\Listado_H_iconos.txt",
    [switch]$Ascii
)

function Format-Size {
    param([Int64]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    elseif ($Bytes -lt 1MB) { return ("{0:N1} KB" -f ($Bytes/1KB)) }
    elseif ($Bytes -lt 1GB) { return ("{0:N1} MB" -f ($Bytes/1MB)) }
    elseif ($Bytes -lt 1TB) { return ("{0:N1} GB" -f ($Bytes/1GB)) }
    else { return ("{0:N2} TB" -f ($Bytes/1TB)) }
}

function Get-Icon {
    param(
        [System.IO.FileSystemInfo]$Item,
        [bool]$UseAscii
    )

    if ($Item.PSIsContainer) {
        if ($UseAscii) { return "[DIR]" } else { return "📂" }
    }

    $ext = ""
    if ($Item.Extension) { $ext = $Item.Extension.ToLower() }

    if ($UseAscii) {
        switch ($ext) {
            ".mp4" { "[VID]" ; break }
            ".mkv" { "[VID]" ; break }
            ".avi" { "[VID]" ; break }
            ".mov" { "[VID]" ; break }
            ".jpg" { "[IMG]" ; break }
            ".jpeg"{ "[IMG]" ; break }
            ".png" { "[IMG]" ; break }
            ".gif" { "[IMG]" ; break }
            ".csv" { "[CSV]" ; break }
            ".xls" { "[XLS]" ; break }
            ".xlsx"{ "[XLSX]"; break }
            ".txt" { "[TXT]" ; break }
            ".doc" { "[DOC]" ; break }
            ".docx"{ "[DOCX]"; break }
            ".pdf" { "[PDF]" ; break }
            default { "[FILE]" }
        }
    } else {
        switch ($ext) {
            ".mp4" { "🎬" ; break }
            ".mkv" { "🎬" ; break }
            ".avi" { "🎬" ; break }
            ".mov" { "🎬" ; break }
            ".jpg" { "🖼️" ; break }
            ".jpeg"{ "🖼️" ; break }
            ".png" { "🖼️" ; break }
            ".gif" { "🖼️" ; break }
            ".csv" { "📊" ; break }
            ".xls" { "📊" ; break }
            ".xlsx"{ "📊" ; break }
            ".txt" { "📄" ; break }
            ".doc" { "📄" ; break }
            ".docx"{ "📄" ; break }
            ".pdf" { "📄" ; break }
            default { "📄" }
        }
    }
}

function Show-Tree {
    param(
        [string]$Path,
        [string]$Prefix = "",
        [switch]$UseAscii
    )

    try {
        $children = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        Write-Output "$Prefix[ERROR] Acceso denegado o ruta no válida: $Path"
        return
    }

    # Orden: directorios primero, luego archivos; por nombre
    $dirs  = $children | Where-Object { $_.PSIsContainer } | Sort-Object Name
    $files = $children | Where-Object { -not $_.PSIsContainer } | Sort-Object Name

    foreach ($d in $dirs) {
        # Conteo y tamaño total (recursivo)
        $fileCount = 0
        $totalBytes = 0
        try {
            $allFiles = Get-ChildItem -LiteralPath $d.FullName -Force -File -Recurse -ErrorAction SilentlyContinue
            if ($allFiles) {
                $fileCount = $allFiles.Count
                $totalBytes = ($allFiles | Measure-Object -Sum Length).Sum
                if ($null -eq $totalBytes) { $totalBytes = 0 }
            }
        } catch {}

        # ¿Carpeta vacía directa?
        $isEmpty = $false
        try {
            $isEmpty = ((Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0)
        } catch {}

        $icon = Get-Icon -Item $d -UseAscii:$UseAscii
        if ($UseAscii) {
            if ($isEmpty) {
                $label = "$icon [EMPTY] $($d.Name)"
            } else {
                $label = "$icon $($d.Name) ($fileCount files, $(Format-Size $totalBytes))"
            }
        } else {
            if ($isEmpty) {
                $label = "$icon❌ $($d.Name)"
            } else {
                $label = "$icon $($d.Name) ($fileCount archivos, $(Format-Size $totalBytes))"
            }
        }

        Write-Output "$Prefix$label"
        Show-Tree -Path $d.FullName -Prefix "$Prefix   " -UseAscii:$UseAscii
    }

    foreach ($f in $files) {
        $icon = Get-Icon -Item $f -UseAscii:$UseAscii
        Write-Output "$Prefix$icon $($f.Name)"
    }
}

# Ejecuta y exporta
$useAscii = $Ascii.IsPresent
$lines = @()
$lines += ("{0}  (generado {1:yyyy-MM-dd HH:mm})" -f $Root, (Get-Date))
$lines += ("".PadRight(40,"-"))
$lines += (Get-Item -LiteralPath $Root).FullName
$lines += ""

$tree = Show-Tree -Path $Root -UseAscii:$useAscii
$lines += $tree

$lines | Out-File -FilePath $Output -Encoding UTF8
Write-Host "✅ Listado generado en: $Output" -ForegroundColor Green
