param(
  [Parameter(Mandatory=$false)]
  [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"
Set-Location $RepoRoot

function Backup-File([string]$Path){
  if(Test-Path $Path){
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $bak = "$Path.bak.$stamp"
    Copy-Item -Force $Path $bak
    Write-Host "[BACKUP] $Path -> $bak"
  } else {
    Write-Warning "[SKIP] No existe $Path"
  }
}

function Patch-TextFile([string]$Path,[ScriptBlock]$Patcher){
  if(-not (Test-Path $Path)){ Write-Warning "[SKIP] $Path no existe"; return }
  Backup-File $Path
  $txt = Get-Content -Raw -Encoding UTF8 $Path

  # 1) Param: [ordered] -> [hashtable]
  $txt = [regex]::Replace($txt, '\[ordered\]\s*\$(DriveCounts|[A-Za-z_][A-Za-z0-9_]*)', '[hashtable]$$1')

  # 2) .Contains( -> .ContainsKey(
  $txt = $txt -replace '\.Contains\(', '.ContainsKey('

  # 3) Guard clause para $DriveCounts si se usa
  if($txt -match '\$DriveCounts'){
    # Si no existe inicialización, insertamos una segura tras el bloque param o al principio del script
    if($txt -notmatch '\$DriveCounts\s*=\s*@\{'){
      # tras primer "param(...)" o inicio
      if($txt -match '(?s)^\s*param\s*\((.*?)\)'){
        $txt = $txt -replace '(?s)^\s*param\s*\((.*?)\)', {'param(' + $args[0].Groups[1].Value + " )`r`nif(-not `$DriveCounts){ `$DriveCounts = @{} }"}
      } else {
        $txt = "if(-not `$DriveCounts){ `$DriveCounts = @{} }`r`n" + $txt
      }
    }
  }

  # 4) "-f" -> [string]::Format para patrones "{0}: {1}"
  $txt = [regex]::Replace($txt, '"\{0\}\s*:\s*\{1\}"\s*-f\s*([^,]+),\s*([^\r\n\)]+)', '[string]::Format("{0}: {1}", $1, $2)')

  # 5) Normaliza separador "Â·" a "·"
  $txt = $txt -replace 'Â·','·'

  # 6) Patcher específico adicional (si se pasa)
  if($Patcher){ $txt = & $Patcher.InvokeReturnAsIs($txt) }

  Set-Content -Value $txt -Path $Path -Encoding UTF8
  Write-Host "[PATCH] $Path OK"
}

# ---  A) Parchear normalize-inventory-html.ps1  ---
$normalize = Join-Path $RepoRoot 'tools\normalize-inventory-html.ps1'
Patch-TextFile $normalize {
  param($t)
  $txt = $t

  # Extraer JSON correcto desde <script id="...duplicates... or type="application/json">
  # Insertamos/actualizamos una función robusta Get-EmbeddedJson que ignora otros <script> (evita parsear "</script>")
  if($txt -notmatch 'function\s+Get-EmbeddedJson'){
    $helper = @"
function Get-EmbeddedJson([string]`$html){
  # 1) Busca <script id="...duplicates..." type="application/json">...</script>
  `"$matches = [regex]::Matches(`$html, '<script[^>]*(id\s*=\s*["''](?<id>[^"']*duplicates[^"']*)["''])?[^>]*type\s*=\s*["'']application/json["''][^>]*>(?<json>.*?)</script>', 'Singleline,IgnoreCase')`
  if(`$matches.Count -gt 0){ return `$matches[0].Groups['json'].Value.Trim() }

  # 2) Si no hay id, coge el primer <script type="application/json"> seguro
  `"$m2 = [regex]::Match(`$html, '<script[^>]*type\s*=\s*["'']application/json["''][^>]*>(?<json>.*?)</script>', 'Singleline,IgnoreCase')`
  if(`$m2.Success){ return `$m2.Groups['json'].Value.Trim() }

  throw "No se encontró bloque JSON embebido (type=""application/json"")."
}
"@
    # Añade helper al comienzo
    $txt = $helper + "`r`n" + $txt
  }

  # Reemplaza lectura antigua si usaba regex genérico por una llamada a Get-EmbeddedJson
  $txt = $txt -replace '(?s)\$json\s*=\s*.*?;',''
  $txt = $txt -replace '(?s)\$data\s*=\s*ConvertFrom-Json\s*\(.*?\);',''
  # Inserta secuencia segura de extracción+parseo antes de usar $data
  if($txt -notmatch 'Get-EmbeddedJson\('){
    $txt = $txt -replace '(?s)(#\s*BEGIN\s*PARSE\s*JSON|^\s*)', {
      param($m)
      "$($m.Groups[0].Value)`r`n# BEGIN PARSE JSON (seguro)`r`n`$html = Get-Content -Raw -Encoding UTF8 (Join-Path `$RepoRoot 'docs\inventario_interactivo_offline.html')`r`n`$jsonRaw = Get-EmbeddedJson `$html`r`n`$data = `$jsonRaw | ConvertFrom-Json`r`n# END PARSE JSON`r`n"
    }
  }

  return $txt
}

# ---  B) (opcional) Parchear también cualquier wrapper *.ps1 en tools que haga la misma lectura ---
Get-ChildItem -Path (Join-Path $RepoRoot 'tools') -Filter *.ps1 | ForEach-Object {
  if($_.FullName -ne $normalize){
    Patch-TextFile $_.FullName $null
  }
}

# ---  C) Añadir paginación básica en docs\assets\inventario.js (sin romper filtros) ---
$invJs = Join-Path $RepoRoot 'docs\assets\inventario.js'
if(Test-Path $invJs){
  Backup-File $invJs
  $js = Get-Content -Raw -Encoding UTF8 $invJs

  # Si usa DataTables, establece pageLength y lengthMenu; si no, inserta controles simples (fallback)
  if($js -match 'DataTable\('){
    # Inyecta opciones si no existen
    if($js -notmatch 'pageLength'){
      $js = $js -replace 'DataTable\(\s*\{', 'DataTable({ pageLength: 25, lengthMenu: [[10,25,50,100,-1],[10,25,50,100,"All"]],'
    }
  } else {
    # Fallback: no DataTables -> añade un selector de paginación simple alrededor del render
    if($js -notmatch '/* PAGINACION SIMPLE */'){
      $pager = @"
;/* PAGINACION SIMPLE */
(function(){
  var page = 1, size = 25, rows = [];
  function render(){
    var start = (page-1)*size, end = start+size;
    var slice = rows.slice(start,end);
    window.__renderInventory(slice);
    var info = document.getElementById('page-info');
    if(info){ info.textContent = page + ' / ' + Math.max(1, Math.ceil(rows.length/size)); }
  }
  window.__initPagination = function(data){
    rows = data||[]; page = 1; render();
  }
  window.__nextPage = function(){ if(page*size < rows.length){ page++; render(); } }
  window.__prevPage = function(){ if(page>1){ page--; render(); } }
  window.__setPageSize = function(n){ size = parseInt(n)||25; page=1; render(); }
})();
"@
      $js = $js + "`r`n" + $pager
    }
  }

  Set-Content -Path $invJs -Value $js -Encoding UTF8
  Write-Host "[PATCH] $invJs (paginación) OK"
} else {
  Write-Warning "[SKIP] No existe $invJs (saltando paginación)"
}

# ---  D) Reintentar pipeline mínimo (si existen los scripts habituales) ---
# Normaliza HTML (parsea JSON embebido) -> genera data\inventory.json si aplica -> minifica/gzip si tienes esos scripts
$normalizedOk = $false
try {
  if(Test-Path $normalize){
    Write-Host "`n[RUN] Normalizando inventario HTML..."
    pwsh -NoProfile -ExecutionPolicy Bypass -File $normalize -RepoRoot $RepoRoot
    $normalizedOk = $true
  } else {
    Write-Warning "[SKIP] Falta $normalize"
  }
} catch {
  Write-Error "[ERROR] Normalización fallida: $($_.Exception.Message)"
}

# Si existe minify-and-gzip, lánzalo (sin bloquear si no está)
$minify = Join-Path $RepoRoot 'tools\minify-and-gzip-inventory.ps1'
if(Test-Path $minify){
  try{
    Write-Host "`n[RUN] Minify + Gzip inventario..."
    pwsh -NoProfile -ExecutionPolicy Bypass -File $minify
  } catch {
    Write-Warning "[WARN] Minify/Gzip falló: $($_.Exception.Message)"
  }
} else {
  Write-Host "[INFO] No se encontró tools\minify-and-gzip-inventory.ps1 (ok, no es crítico)."
}

# ---  E) Resumen final ---
Write-Host "`n==== RESUMEN ===="
Write-Host "Repo: $RepoRoot"
Write-Host "Normalize patched: " -NoNewline; if(Test-Path $normalize){ Write-Host "Sí" } else { Write-Host "No" }
Write-Host "Inventario paginación: " -NoNewline; if(Test-Path $invJs){ Write-Host "Aplicada (o ver fallback)" } else { Write-Host "No encontrado" }
Write-Host "Normalización ejecutada: " -NoNewline; Write-Host ($(if($normalizedOk){"Sí"}else{"No/Con avisos"}))
