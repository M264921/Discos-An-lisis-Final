param(
  [string]$JsonPath = "docs\data\inventory.json",
  [int]$Port = 8080
)
$ErrorActionPreference = "Stop"

function Log([string]$m,[string]$c="Gray"){
  Write-Host $m -ForegroundColor $c
}

# A) Validación del JSON
if (!(Test-Path $JsonPath)) { throw "No existe $JsonPath" }
try {
  $DATA = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json
} catch {
  throw "JSON inválido: $($_.Exception.Message)"
}
if (-not ($DATA -is [System.Collections.IEnumerable])) { throw "JSON no es un array" }
$cnt = $DATA.Count
$sum = ($DATA | Measure-Object -Property tamano -Sum).Sum
$nulls = ($DATA | Where-Object { -not $_.nombre -and -not $_.ruta -and -not $_.tipo }).Count
Log ("✓ JSON ok → {0} filas · bytes totales: {1:n0} · filas con campos vacíos: {2}" -f $cnt,$sum,$nulls) "Green"

# B) Arranca server HTTP en 8080 si no está
$busy = Test-NetConnection -ComputerName localhost -Port $Port | Select-Object -ExpandProperty TcpTestSucceeded
if (-not $busy) {
  Log "Lanzando http.server en $Port..." "DarkCyan"
  Start-Process powershell -ArgumentList @('-NoExit','-Command',"cd `"$pwd`"; python -m http.server $Port") | Out-Null
  Start-Sleep -Seconds 2
}

# C) Genera un viewer mínimo que lee el JSON
$h = "docs\view.html"
$content = @"
<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Inventario (viewer)</title>
<style>
body{font-family:system-ui,Segoe UI,Roboto,Inter,Arial;background:#111;color:#eee;margin:16px}
table{width:100%;border-collapse:collapse;margin-top:8px}
th,td{border-bottom:1px solid #222;padding:8px} th{position:sticky;top:0;background:#0f0f0f}
.muted{opacity:.75}
</style>
<h1>Inventario (viewer)</h1>
<div><span id="count">0</span> archivos · <span id="size">0</span> (visibles) <input id="q" placeholder="Buscar (ruta/nombre/sha)" style="min-width:260px"></div>
<table id="t"><thead><tr>
  <th>SHA</th><th>Tipo</th><th>Nombre</th><th>Ruta/Carpeta</th><th>Unidad</th><th>Tamaño</th><th>Fecha</th>
</tr></thead><tbody></tbody></table>
<script>
(async ()=>{
  const human=n=>{if(!n||isNaN(n))return "0";const u=["B","KB","MB","GB","TB"];let i=0,x=Number(n);while(x>=1024&&i<u.length-1){x/=1024;i++;}return x.toFixed(1)+" "+u[i]};
  const res = await fetch("data/inventory.json?ts="+Date.now());
  const DATA = await res.json();
  const tb=document.querySelector("#t tbody"), q=document.querySelector("#q");
  const draw = (rows)=>{
    tb.innerHTML=""; let total=0;
    for(const r of rows){
      total += Number(r.tamano||0);
      const tr=document.createElement("tr");
      tr.innerHTML = `<td class="muted">\${r.sha||""}</td>
                      <td>\${r.tipo||""}</td>
                      <td>\${r.nombre||""}</td>
                      <td class="muted">\${r.ruta||""}</td>
                      <td>\${r.unidad||""}</td>
                      <td>\${human(r.tamano)}</td>
                      <td>\${(r.fecha||"").replace("T"," ").replace("Z","")}</td>`;
      tb.appendChild(tr);
    }
    document.querySelector("#count").textContent = rows.length.toLocaleString();
    document.querySelector("#size").textContent = human(total);
  };
  const filter=()=>{
    const s=(q.value||"").toLowerCase();
    if(!s){ draw(DATA); return; }
    draw(DATA.filter(r => 
      (r.ruta||"").toLowerCase().includes(s) ||
      (r.nombre||"").toLowerCase().includes(s) ||
      (r.sha||"").toLowerCase().includes(s)
    ));
  };
  q.addEventListener("input", filter);
  draw(DATA);
})();
</script>
"@
Set-Content -LiteralPath $h -Encoding UTF8 -Value $content
Log "Viewer escrito en $h" "DarkGray"

# D) Abre viewer (bust cache)
Start-Process ("http://localhost:{0}/docs/view.html?ts={1}" -f $Port, (Get-Date -Format yyyyMMddHHmmss))
