# viewer simple (docs\view.html)
$h = "docs\view.html"
@"
<!doctype html><meta charset="utf-8">
<title>Inventario (viewer)</title>
<style>
 body{font-family:system-ui,Segoe UI,Roboto,Inter;background:#111;color:#eee;margin:20px}
 h1{margin:0 0 10px} table{width:100%;border-collapse:collapse}
 th,td{padding:8px;border-bottom:1px solid #222} th{position:sticky;top:0;background:#0f0f0f}
 .muted{opacity:.75}
</style>
<h1>Inventario (viewer)</h1>
<p><span id="count">0</span> archivos · <span id="size">0</span> visibles</p>
<input id="q" placeholder="Buscar (ruta/nombre/sha)" style="min-width:260px;padding:6px;background:#161616;border:1px solid #333;color:#eee">
<table><thead><tr>
<th>SHA</th><th>Tipo</th><th>Nombre</th><th>Ruta/Carpeta</th><th>Unidad</th><th>Tamaño</th><th>Fecha</th>
</tr></thead><tbody id="tb"></tbody></table>
<script>
(async function(){
  const human=n=>{if(!n||isNaN(n))return"0";const u=["B","KB","MB","GB","TB"];let i=0,x=+n||0;while(x>=1024&&i<u.length-1){x/=1024;i++}return x.toFixed(1)+" "+u[i]};
  const res = await fetch("data/inventory.json?ts="+Date.now());
  const DATA = await res.json();
  const q=document.getElementById('q'), tb=document.getElementById('tb');
  function render(){
    const v=(q.value||"").toLowerCase();
    let rows = v? DATA.filter(r => (r.ruta||"").toLowerCase().includes(v) || (r.nombre||"").toLowerCase().includes(v) || (r.sha||"").toLowerCase().includes(v)) : DATA;
    tb.innerHTML=""; let total=0; const frag=document.createDocumentFragment();
    for(const r of rows){
      total += +r.tamano||0;
      const tr=document.createElement('tr');
      tr.innerHTML = `<td class="muted">${r.sha||""}</td><td>${r.tipo||""}</td><td>${r.nombre||""}</td>
        <td class="muted">${r.ruta||""}</td><td>${r.unidad||""}</td><td>${human(r.tamano)}</td>
        <td>${(r.fecha||"").replace("T"," ").replace("Z","")}</td>`;
      frag.appendChild(tr);
    }
    tb.appendChild(frag);
    document.getElementById('count').textContent = rows.length.toLocaleString();
    document.getElementById('size').textContent = human(total);
  }
  q.addEventListener('input', render); render();
})();
</script>
"@ | Set-Content -Encoding UTF8 $h

# offline interactivo (reutilizamos tu HTML si existe; si no, creamos uno mínimo)
$h2 = "docs\inventario_interactivo_offline.html"
if(!(Test-Path $h2)){
  @"
<!doctype html><meta charset="utf-8">
<title>Inventario (standalone)</title>
<div id="err" style="display:none;color:#f55"></div>
<h1>Inventario (standalone)</h1>
<div><span id="count">0</span> archivos · <span id="size">0</span> (visibles)</div>
<table id="tbl" style="width:100%;border-collapse:collapse">
  <thead><tr>
    <th>SHA</th><th>Tipo</th><th>Nombre</th><th>Ruta/Carpeta</th><th>Unidad</th><th>Tamaño</th><th>Fecha</th>
  </tr></thead><tbody></tbody>
</table>
<script>
const human=n=>{if(!n||isNaN(n))return"0";const u=["B","KB","MB","GB","TB"];let i=0,x=+n||0;while(x>=1024&&i<u.length-1){x/=1024;i++}return x.toFixed(1)+" "+u[i]};
fetch("data/inventory.json?ts="+Date.now())
  .then(r=>r.json())
  .then(DATA=>{
    const tb=document.querySelector("#tbl tbody");
    tb.innerHTML=""; let total=0; const frag=document.createDocumentFragment();
    for(const r of DATA){
      total+=+r.tamano||0; const tr=document.createElement("tr");
      tr.innerHTML = `<td>${r.sha||""}</td><td>${r.tipo||""}</td><td>${r.nombre||""}</td>
      <td>${r.ruta||""}</td><td>${r.unidad||""}</td><td>${human(r.tamano)}</td>
      <td>${(r.fecha||"").replace("T"," ").replace("Z","")}</td>`;
      frag.appendChild(tr);
    }
    tb.appendChild(frag);
    document.getElementById('count').textContent = DATA.length.toLocaleString();
    document.getElementById('size').textContent = human(total);
  })
  .catch(e=>{const b=document.getElementById("err");b.textContent="⚠ "+e.message;b.style.display="block";});
</script>
"@ | Set-Content -Encoding UTF8 $h2
}else{
  # Si ya existe, elimina bloque Base64 (si hubiera) y pásalo a fetch JSON externo
  $raw = Get-Content -LiteralPath $h2 -Raw
  $raw = [regex]::Replace($raw,'(?s)<script id="INV_B64"[^>]*>.*?</script>','')
  if($raw -notmatch 'fetch\("data/inventory.json'){
    $raw = $raw -replace '</body>','<script>fetch("data/inventory.json?ts="+Date.now()).then(r=>r.json()).then(DATA=>{window.DATA=DATA;if(typeof chips==="function")chips(DATA);if(typeof render==="function")render();}).catch(console.error);</script></body>'
  }
  Set-Content -LiteralPath $h2 -Encoding UTF8 $raw
}
