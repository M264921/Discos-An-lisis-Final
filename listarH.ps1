Add-Type -AssemblyName System.Windows.Forms

  $report = @()
  Get-ChildItem -Path 'H:\' -Directory | ForEach-Object {
      Write-Host "Carpeta: $($_.FullName)"
      $items = Get-ChildItem -Path $_.FullName -Recurse
      $items | ForEach-Object {
          $report += [pscustomobject]@{
              Carpeta    = $_.DirectoryName
              Nombre     = $_.Name
              Tipo       = if ($_.PSIsContainer) { 'Carpeta' } else { 'Archivo' }
              TamanoKB   = if ($_.PSIsContainer) { '' } else { [math]::Round(($_.Length / 1KB), 2) }
              Modificado = $_.LastWriteTime
          }
      }
      Write-Host ""
  }

  $dialog = New-Object System.Windows.Forms.SaveFileDialog
  $dialog.InitialDirectory = 'H:\'
  $dialog.Title  = 'Guardar informe de contenido'
  $dialog.Filter = 'CSV (*.csv)|*.csv|Texto (*.txt)|*.txt|Excel (*.xlsx)|*.xlsx'
  $dialog.FileName = 'contenido-H-drive'

  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
      $extension = [System.IO.Path]::GetExtension($dialog.FileName).ToLowerInvariant()

      switch ($extension) {
          '.csv' {
              $report | Export-Csv -Path $dialog.FileName -Encoding UTF8 -NoTypeInformation
              Write-Host "Informe guardado como CSV en $($dialog.FileName)"
          }
          '.txt' {
              $report | Out-String | Set-Content -Path $dialog.FileName -Encoding UTF8
              Write-Host "Informe guardado como TXT en $($dialog.FileName)"
          }
          '.xlsx' {
              if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
                  Write-Warning "Para XLSX necesitas instalar el módulo ImportExcel (Install-Module ImportExcel)."
              } else {
                  $report | Export-Excel -Path $dialog.FileName -WorksheetName 'Contenido'
                  Write-Host "Informe guardado como XLSX en $($dialog.FileName)"
              }
          }
          Default {
              Write-Warning "Extensión no soportada. Elige .csv, .txt o .xlsx."
          }
      }
  }