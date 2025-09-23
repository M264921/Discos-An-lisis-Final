# Script: Listado_H_iconos.ps1
# Genera un árbol del disco H:\ con iconos y lo guarda en el Escritorio

function Show-Tree {
    param(
        [string]$Path = "H:\",
        [string]$Prefix = ""
    )

    $items = Get-ChildItem -LiteralPath $Path | Sort-Object PSIsContainer, Name

    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            # Carpeta
            if ((Get-ChildItem -LiteralPath $item.FullName -Force | Measure-Object).Count -eq 0) {
                Write-Output "$Prefix📂❌ $($item.Name)"   # Carpeta vacía con ❌
            } else {
                Write-Output "$Prefix📂 $($item.Name)"
                Show-Tree -Path $item.FullName -Prefix "$Prefix   "
            }
        }
        else {
            # Archivo (por extensión)
            switch ($item.Extension.ToLower()) {
                ".mp4" { $icon = "🎬" }
                ".mkv" { $icon = "🎬" }
                ".avi" { $icon = "🎬" }
                ".mov" { $icon = "🎬" }
                ".jpg" { $icon = "🖼️" }
                ".jpeg" { $icon = "🖼️" }
                ".png" { $icon = "🖼️" }
                ".gif" { $icon = "🖼️" }
                ".csv" { $icon = "📊" }
                ".xls" { $icon = "📊" }
                ".xlsx" { $icon = "📊" }
                ".txt" { $icon = "📄" }
                ".doc" { $icon = "📄" }
                ".docx" { $icon = "📄" }
                ".pdf" { $icon = "📄" }
                default { $icon = "📄" }
            }
            Write-Output "$Prefix$icon $($item.Name)"
        }
    }
}

# Exporta el resultado al Escritorio
$OutputFile = "$env:USERPROFILE\Desktop\Listado_H_iconos.txt"
Show-Tree "H:\" | Out-File $OutputFile -Encoding UTF8

Write-Host "✅ Listado generado en: $OutputFile" -ForegroundColor Green
