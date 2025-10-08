[CmdletBinding()]
param([string]$JsonPath="docs\data\inventory.json",
      [string]$HtmlPath="docs\inventario_interactivo_offline.html")
if(!(Test-Path $JsonPath)){ throw "No existe $JsonPath" }
$bytes = [IO.File]::ReadAllBytes($JsonPath)
$b64   = [Convert]::ToBase64String($bytes)

# HTML: corregido chips() y render(); filtros completos
$tpl = @"
<!doctype html><html lang="es"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Inventario (standalone)</title>
<style>
body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Inter,Helvetica,Arial,sans-serif;background:#111;color:#eee;margin:20px}
h1{margin:0 0 10px 0}.chips{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0 12px 0}
.chip{padding:6px 10px;border:1px solid #444;border-radius:999px;cursor:pointer;background:#1b1b1b}.chip:hover{opacity:.85}
.toolbar{display:flex;gap:10px;align-items:center;margin:8px 0 16px 0}
.toolbar input{background:#161616;color:#eee;border:1px solid #333;border-radius:6px;padding:6px 8px}
table{width:100%;border-collapse:collapse}th,td{padding:8px;border-bottom:1px solid #222}th{position:sticky;top:0;background:#0f0f0f}
.muted{opacity:.75;font-size:.9em}#err{background:#331111;border:1px solid #552222;padding:10px;border-radius:8px;margin:10px 0;display:none}
.kpi{opacity:.8}
</style></head><body>
<h1>Inventario (standalone)</h1><div id="err"></div>
<div class="toolbar"><div><span id="count" class="kpi">0</span> archivos · <span id="size" class="kpi">0</span> (visibles)</div>
<input id="q" placeholder="Buscar (ruta/nombre/sha)" style="min-width:260px"/></div>
<div class="chips" id="unitChips"></div>
<table id="tbl"><thead><tr>
<th>SHA</th><th>Tipo</th><th>Nombre</th><th>Ruta/Carpeta</th><th>Unidad</th><th>Tamaño</th><th>Fecha</th>
</tr><tr class="filters">
<th><input data-col="sha" placeholder="filtrar"></th>
<th><input data-col="tipo" placeholder="filtrar"></th>
<th><input data-col="nombre" placeholder="filtrar"></th>
<th><input data-col="ruta" placeholder="filtrar"></th>
<th><input data-col="unidad" placeholder="filtrar"></th>
<th><input data-col="tamano" placeholder=">=, <=, ="></th>
<th><input data-col="fecha" placeholder="YYYY-MM-DD"></th>
</tr></thead><tbody></tbody></table>

<script id="INV_B64" type="application/octet-stream">
__B64__
</script>
<script>
(function(){
  const showErr=m=>{const b=document.getElementById('err');b.textContent="⚠️ "+m;b.style.display='block';console.error(m)};
  function decode(){
    try{
      const b64=(document.getElementById('INV_B64')?.textContent||"").trim();
      if(!b64){ showErr("sin datos incrustados"); return []; }
      const bin=atob(b64), bytes=new Uint8Array(bin.length); for(let i=0;i<bin.length;i++) bytes[i]=bin.charCodeAt(i);
      const txt=new TextDecoder("utf-8").decode(bytes);
      const j=JSON.parse(txt);
      return Array.isArray(j)?j:(j.data||[]);
    }catch(e){ showErr("decode:"+e.message); return []; }
  }
  const SRC = decode();
  const DATA = (SRC||[]).map(r=>({sha:r.sha||"",tipo:r.tipo||r.type||"",nombre:r.nombre||r.name||"",ruta:r.ruta||r.dir||"",unidad:r.unidad||r.unit||"",tamano:Number((r.tamano??r.size??r.length)||0),fecha:r.fecha||r.date||r.lastWriteTime||""}));

  const $$=s=>document.querySelector(s), $$$=s=>Array.from(document.querySelectorAll(s)), tbody=$$("#tbl tbody"), q=$$("#q"), filters={};
  $$$(".filters input").forEach(i=>i.addEventListener("input",()=>{filters[i.dataset.col]=i.value.trim();render();})); q.addEventListener("input",render);

  function human(n){if(!n||isNaN(n))return"0";const u=["B","KB","MB","GB","TB"];let i=0,x=Number(n);while(x>=1024&&i<u.length-1){x/=1024;i++;}return x.toFixed(1)+" "+u[i]}

  function chips(rows){
    const bar=$$("#unitChips"); bar.innerHTML="";
    const units=[...new Set(rows.map(r=>(r.unidad||"").trim()).filter(Boolean))].sort();
    for(const u of units){ const b=document.createElement("button"); b.className="chip"; b.textContent=u;
      b.onclick=()=>{ filters.unidad=u; $$(`.filters input[data-col="unidad"]`).value=u; render(); };
      bar.appendChild(b);
    }
    const r=document.createElement("button"); r.className="chip"; r.textContent="Todos";
    r.onclick=()=>{ filters.unidad=""; $$(`.filters input[data-col="unidad"]`).value=""; render(); };
    bar.appendChild(r);
  } // <--- cierre OK

  function render(){
    const qv=(q.value||"").toLowerCase(); let rows=DATA;
    if(qv){ rows=rows.filter(r=>(r.ruta||"").toLowerCase().includes(qv)||(r.nombre||"").toLowerCase().includes(qv)||(r.sha||"").toLowerCase().includes(qv)); }
    for(const [k,v] of Object.entries(filters)){ if(!v) continue;
      if(k==="tamano"){ const m=v.match(/^\s*(>=|<=|=)\s*(\d+)\s*$/); if(m){const op=m[1],num=Number(m[2]); rows=rows.filter(r=>{const n=Number(r.tamano||0);return op===">="?n>=num:op==="<="?n<=num:n===num;});}}
      else if(k==="fecha"){ rows=rows.filter(r=>(r.fecha||"").startsWith(v)); }
      else { const vv=v.toLowerCase(); rows=rows.filter(r=>((r[k]||"")+"").toLowerCase().includes(vv)); }
    }
    tbody.innerHTML=""; const frag=document.createDocumentFragment(); let total=0;
    for(const r of rows){ total+=Number(r.tamano||0); const tr=document.createElement("tr"); tr.innerHTML=
      `<td class="muted">${r.sha}</td><td>${r.tipo}</td><td>${r.nombre}</td><td class="muted">${r.ruta}</td><td>${r.unidad}</td><td>${human(r.tamano)}</td><td>${(r.fecha||"").replace("T"," ").replace("Z","")}</td>`;
      frag.appendChild(tr);
    }
    tbody.appendChild(frag); $$("#count").textContent=rows.length.toLocaleString(); $$("#size").textContent=human(total);
  }

  chips(DATA); render();
})();
</script></body></html>
"@

$tpl = $tpl -replace "__B64__", [Regex]::Escape($b64) -replace "\\Q|\\E",""
Set-Content -Encoding UTF8 $HtmlPath $tpl
Write-Host "✔ HTML: $HtmlPath" -ForegroundColor Green
Start-Process $HtmlPath
