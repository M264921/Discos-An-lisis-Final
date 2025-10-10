[CmdletBinding()]
param(
  [string]$JsonPath = "docs\data\inventory.json",
  [string]$HtmlPath = "docs\inventario_interactivo_offline.html",
  [bool]$EmbedBase64 = $true,
  [switch]$NoOpen
)

if (!(Test-Path $JsonPath)) {
  throw "No existe $JsonPath"
}

$bytes = [IO.File]::ReadAllBytes($JsonPath)
$b64   = [Convert]::ToBase64String($bytes)

# HTML interactivo con paginación, columnas reorganizables y enlaces locales
$tpl = @'
<!doctype html><html lang="es"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Inventario Interactivo</title>
<style>
*{box-sizing:border-box}
body{margin:0;padding:24px;font-family:"Inter","Segoe UI",Roboto,Ubuntu,Helvetica,Arial,sans-serif;background:#f4f6fb;color:#0f172a;line-height:1.5}
main{max-width:1280px;margin:0 auto}
h1{margin:0 0 12px;font-size:28px;font-weight:700;color:#0b1733}
#err{display:none;padding:12px 16px;border-radius:10px;background:#fee2e2;border:1px solid #fecaca;color:#7f1d1d;margin-bottom:16px}
.toolbar{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin-bottom:14px}
.toolbar .summary{display:flex;align-items:center;gap:6px;font-weight:600;color:#1f2937}
.toolbar .summary .sep{color:#94a3b8}
.toolbar .search{flex:1;min-width:220px}
.toolbar input[type="search"]{width:100%;padding:9px 12px;border:1px solid #cbd5f5;border-radius:10px;background:#fff;color:#0f172a;transition:border .15s ease,box-shadow .15s ease}
.toolbar input[type="search"]:focus{outline:none;border-color:#2563eb;box-shadow:0 0 0 3px rgba(37,99,235,.15)}
.toolbar select{padding:8px 10px;border:1px solid #cbd5f5;border-radius:10px;background:#fff;color:#0f172a}
.toolbar button{padding:8px 14px;border:none;border-radius:10px;background:#2563eb;color:#fff;font-weight:600;cursor:pointer;transition:background .15s ease,transform .15s ease}
.toolbar button:hover{background:#1d4ed8;transform:translateY(-1px)}
.toolbar button:disabled{background:#94a3b8;cursor:not-allowed;transform:none}
.btn-secondary{background:#fff;color:#1f2937;border:1px solid #cbd5f5}
.btn-secondary:hover{color:#2563eb;border-color:#2563eb}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:6px 0 18px}
.chips button{padding:6px 12px;border-radius:999px;border:1px solid #cbd5f5;background:#fff;color:#1f2937;font-size:13px;cursor:pointer;transition:all .15s ease}
.chips button[data-active="true"]{background:#1d4ed8;border-color:#1d4ed8;color:#fff;box-shadow:0 8px 18px -10px rgba(29,78,216,.85)}
.chips button:hover{border-color:#1d4ed8;color:#1d4ed8}
.chips .chip-all{font-weight:600}
.insights{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin:12px 0 22px}
.insights .card{background:#fff;border:1px solid #d7dff5;border-radius:14px;padding:16px;box-shadow:0 20px 46px -40px rgba(15,23,42,.45)}
.insights .card h2{margin:0 0 10px;font-size:15px;font-weight:700;color:#0b1733}
.insights .card ul{margin:0;padding-left:18px;color:#475569;font-size:13px}
.insights .card li{margin-bottom:6px}
.table-shell{background:#fff;border:1px solid #d7dff5;border-radius:16px;box-shadow:0 26px 54px -40px rgba(15,23,42,.45);overflow:auto;position:relative}
.table-shell.drag-active::after{content:"";position:absolute;inset:0;border:2px dashed rgba(37,99,235,.35);pointer-events:none}
table{width:100%;border-collapse:separate;border-spacing:0;min-width:840px}
thead tr:first-child th{position:sticky;top:0;background:#ecf1ff;color:#0f172a;font-size:13px;font-weight:600;z-index:2}
thead tr.filters th{position:sticky;top:46px;background:rgba(236,241,255,0.96);backdrop-filter:blur(3px);z-index:1}
th,td{padding:10px 12px;border-bottom:1px solid #e2e8f0;text-align:left;font-size:13px;vertical-align:top}
tbody tr:nth-child(even){background:#f8faff}
tbody tr:hover{background:#e8f1ff}
.muted{color:#475569;font-size:12px}
.wrap{text-overflow:ellipsis;overflow:hidden;white-space:nowrap}
.col-size{text-align:right;font-variant-numeric:tabular-nums}
.col-date{white-space:nowrap}
.th-content{display:flex;align-items:center;gap:6px}
.th-label{flex:1}
.resize-handle{position:absolute;right:0;top:0;width:6px;height:100%;cursor:col-resize}
.resize-handle::after{content:"";display:block;width:2px;height:60%;margin:auto;background:#9ca3af;border-radius:2px;opacity:0;transition:opacity .15s ease}
th:hover .resize-handle::after{opacity:.65}
th{position:relative;border-right:1px solid #dbe4ff}
th:last-child{border-right:none}
th.drag-source{opacity:.6}
th.drop-target{box-shadow:inset 0 0 0 2px #2563eb}
thead input{width:100%;padding:7px 8px;border:1px solid #cbd5f5;border-radius:8px;font-size:12px;background:#fff;color:#0f172a}
.cell-link{color:#2563eb;text-decoration:none;word-break:break-word}
.cell-link:hover{text-decoration:underline}
.pagination{display:flex;justify-content:space-between;align-items:center;margin:16px 0 8px}
.pagination .controls{display:flex;gap:8px}
.pagination button{padding:7px 12px;border-radius:10px;border:1px solid #cbd5f5;background:#fff;color:#0f172a;font-weight:500;cursor:pointer}
.pagination button:hover:not(:disabled){border-color:#2563eb;color:#2563eb}
.pagination button:disabled{opacity:.45;cursor:not-allowed}
.pagination .info{font-size:13px;color:#475569}
</style></head><body>
<main>
<h1>Inventario interactivo</h1>
<div id="err"></div>
<div class="toolbar">
  <div class="summary"><span id="count">0</span> archivos <span class="sep">&middot;</span> <span id="size">0</span> visibles</div>
  <div class="search"><input id="q" type="search" placeholder="Buscar por ruta, nombre o hash"/></div>
  <select id="pageSize">
    <option value="25">25 por página</option>
    <option value="50" selected>50 por página</option>
    <option value="100">100 por página</option>
    <option value="250">250 por página</option>
    <option value="0">Todos</option>
  </select>
  <button class="btn-secondary" id="resetColumns">Reset columnas</button>
  <button id="downloadBtn" disabled>Descargar CSV</button>
</div>
<div class="insights">
  <div class="card">
    <h2>Unidades visibles</h2>
    <ul id="unitSummary"></ul>
  </div>
  <div class="card">
    <h2>Extensiones principales</h2>
    <ul id="extSummary"></ul>
  </div>
  <div class="card">
    <h2>Carpetas destacadas</h2>
    <ul id="pathSummary"></ul>
  </div>
</div>
<div class="chips" id="unitChips"></div>
<div class="table-shell" id="tableShell">
  <table id="tbl">
    <thead>
      <tr id="headerRow"></tr>
      <tr class="filters" id="filterRow"></tr>
    </thead>
    <tbody></tbody>
  </table>
</div>
<div class="pagination">
  <div class="info" id="pageInfo"></div>
  <div class="controls">
    <button id="prevPage">Anterior</button>
    <button id="nextPage">Siguiente</button>
  </div>
</div>

<script id="INV_B64" type="application/octet-stream" data-src="data/inventory.json">
__B64__
</script>
<script>
(function(){
  const showErr=function(msg){const box=document.getElementById("err");box.textContent="[!] "+msg;box.style.display="block";console.error(msg);};
  const baseNode=document.getElementById("INV_B64");
  let DATA=[];

  loadData().then(function(raw){
    DATA=normalizeData(raw);
    buildHeaders();
    render();
  }).catch(function(err){
    const message=err && err.message ? err.message : String(err);
    showErr(message);
  });

  function loadData(){
    if(baseNode){
      const raw=(baseNode.textContent||"").trim();
      if(raw){
        try{
          return Promise.resolve(decodeBase64(raw));
        }catch(err){
          return Promise.reject(err);
        }
      }
      const src=baseNode.getAttribute("data-src");
      if(src){return fetchJson(src);}
    }
    return fetchJson("data/inventory.json");
  }

  function decodeBase64(raw){
    const bin=atob(raw);
    const bytes=new Uint8Array(bin.length);
    for(let i=0;i<bin.length;i++){bytes[i]=bin.charCodeAt(i);}
    const txt=new TextDecoder("utf-8",{fatal:false}).decode(bytes);
    const parsed=JSON.parse(txt);
    return Array.isArray(parsed)?parsed:(parsed.data||[]);
  }

  function fetchJson(url){
    return fetch(url,{cache:"no-store"}).then(function(res){
      if(!res.ok){throw new Error("No se pudo cargar "+url+" ("+res.status+")");}
      return res.json();
    });
  }

  function normalizeData(source){
    return (source||[]).map(function(row){
      return {
        sha:row.sha||"",
        tipo:row.tipo||row.type||"",
        nombre:row.nombre||row.name||"",
        ruta:row.ruta||row.dir||row.path||"",
        unidad:(row.unidad||row.drive||"").toString().trim(),
        tamano:Number((row.tamano??row.size??row.length) || 0),
        fecha:row.fecha||row.date||row.lastWriteTime||""
      };
    });
  }

  const elements={
    tableShell:document.getElementById("tableShell"),
    headerRow:document.getElementById("headerRow"),
    filterRow:document.getElementById("filterRow"),
    tbody:document.querySelector("#tbl tbody"),
    q:document.getElementById("q"),
    chips:document.getElementById("unitChips"),
    count:document.getElementById("count"),
    size:document.getElementById("size"),
    pageSize:document.getElementById("pageSize"),
    prev:document.getElementById("prevPage"),
    next:document.getElementById("nextPage"),
  pageInfo:document.getElementById("pageInfo"),
  download:document.getElementById("downloadBtn"),
  resetCols:document.getElementById("resetColumns"),
  unitSummary:document.getElementById("unitSummary"),
  extSummary:document.getElementById("extSummary"),
  pathSummary:document.getElementById("pathSummary")
};

  const defaultOrder=["sha","tipo","nombre","ruta","unidad","tamano","fecha"];
  const defaultWidths={sha:240,tipo:120,nombre:260,ruta:320,unidad:90,tamano:130,fecha:160};

  const columns={
    sha:{id:"sha",label:"SHA",type:"text",className:"muted wrap",get:r=>r.sha||"",filterPlaceholder:"Filtrar hash",csv:r=>r.sha||""},
    tipo:{id:"tipo",label:"Tipo",type:"text",get:r=>r.tipo||"",filterPlaceholder:"Filtrar tipo"},
    nombre:{id:"nombre",label:"Nombre",type:"text",get:r=>r.nombre||"",render:r=>cellFileLink(r),filterPlaceholder:"Filtrar nombre",csv:r=>r.nombre||""},
    ruta:{id:"ruta",label:"Ruta/Carpeta",type:"text",get:r=>r.ruta||"",render:r=>cellFolderLink(r),filterPlaceholder:"Filtrar ruta",csv:r=>r.ruta||""},
    unidad:{id:"unidad",label:"Unidad",type:"text",get:r=>r.unidad||"",filterPlaceholder:"Filtrar unidad"},
    tamano:{id:"tamano",label:"Tama&ntilde;o",type:"number",className:"col-size",get:r=>Number(r.tamano||0),render:r=>escapeHtml(human(r.tamano)),filterPlaceholder:">=, <=, =",csv:r=>Number(r.tamano||0)},
    fecha:{id:"fecha",label:"Fecha",type:"date",className:"col-date",get:r=>r.fecha||"",render:r=>escapeHtml(formatDate(r.fecha)),filterPlaceholder:"YYYY-MM-DD",csv:r=>r.fecha||""}
  };

  const state={order:defaultOrder.slice(),widths:Object.assign({},defaultWidths),filters:Object.create(null),search:"",pageSize:50,page:1,activeUnit:""};
  let dragSource=null;

  function human(bytes){
    if(!bytes||Number.isNaN(bytes)){return "0 B";}
    const units=["B","KB","MB","GB","TB","PB"];
    let value=Number(bytes);
    let idx=0;
    while(value>=1024 && idx<units.length-1){value/=1024;idx++;}
    return value.toFixed(idx===0?0:1)+" "+units[idx];
  }
  function formatDate(value){return value?(value.replace("T"," ").replace("Z","")):"";}
  function escapeHtml(text){return (text??"").toString().replace(/[&<>"]/g,function(ch){switch(ch){case"&":return"&amp;";case"<":return"&lt;";case">":return"&gt;";case"\"":return"&quot;";default:return ch;}});}
  function joinWinPath(dir,name){if(!dir){return name||"";}if(!name){return dir;}const sep=(dir.endsWith("\\")||dir.endsWith("/"))?"":"\\";return dir+sep+name;}
  function toFileUrl(path){
    if(!path){return"";}
    let normalized=path.replace(/\\/g,"/").replace(/^\.\/+/,"");
    const driveMatch=normalized.match(/^([A-Za-z]):\/?(.*)$/);
    let prefix="file:///";
    let rest=normalized;
    if(driveMatch){
      prefix+=driveMatch[1].toUpperCase()+":/";
      rest=driveMatch[2];
    }
    const encoded=rest.split("/").filter(Boolean).map(function(part){return encodeURIComponent(part);}).join("/");
    return prefix+encoded;
  }
  function cellFileLink(row){
    const full=joinWinPath(row.ruta,row.nombre);
    const url=toFileUrl(full);
    const label=escapeHtml(row.nombre||"");
    if(!url){return label;}
    return "<a class=\"cell-link\" href=\""+url+"\" title=\"Abrir archivo\" target=\"_blank\" rel=\"noopener\">"+label+"</a>";
  }
  function cellFolderLink(row){
    const url=toFileUrl(row.ruta||"");
    const label=escapeHtml(row.ruta||"");
    if(!url){return label;}
    return "<a class=\"cell-link\" href=\""+url+"\" title=\"Abrir carpeta\" target=\"_blank\" rel=\"noopener\">"+label+"</a>";
  }

  function buildHeaders(){
    elements.headerRow.innerHTML="";
    elements.filterRow.innerHTML="";
    state.order.forEach(function(colId){
      const col=columns[colId];
      const th=document.createElement("th");
      th.dataset.col=colId;
      th.draggable=true;
      const width=state.widths[colId]||defaultWidths[colId]||150;
      th.style.width=width+"px";
      const wrapper=document.createElement("div");
      wrapper.className="th-content";
      const label=document.createElement("span");
      label.className="th-label";
      label.innerHTML=col.label;
      wrapper.appendChild(label);
      th.appendChild(wrapper);
      const handle=document.createElement("span");
      handle.className="resize-handle";
      th.appendChild(handle);

      handle.addEventListener("pointerdown",function(ev){
        ev.preventDefault();ev.stopPropagation();
        const startX=ev.clientX;
        const startWidth=th.getBoundingClientRect().width;
        function onMove(moveEvent){
          const delta=moveEvent.clientX-startX;
          const newWidth=Math.max(80,startWidth+delta);
          th.style.width=newWidth+"px";
          state.widths[colId]=newWidth;
        }
        function onUp(){window.removeEventListener("pointermove",onMove);window.removeEventListener("pointerup",onUp);}
        window.addEventListener("pointermove",onMove);
        window.addEventListener("pointerup",onUp,{once:true});
      });

      th.addEventListener("dragstart",function(ev){
        dragSource=colId;
        th.classList.add("drag-source");
        elements.tableShell.classList.add("drag-active");
        ev.dataTransfer.effectAllowed="move";
      });
      th.addEventListener("dragend",function(){
        dragSource=null;
        th.classList.remove("drag-source");
        elements.tableShell.classList.remove("drag-active");
        Array.from(elements.headerRow.children).forEach(function(node){node.classList.remove("drop-target");});
      });
      th.addEventListener("dragover",function(ev){
        ev.preventDefault();
        if(!dragSource || dragSource===colId){return;}
        th.classList.add("drop-target");
      });
      th.addEventListener("dragleave",function(){th.classList.remove("drop-target");});
      th.addEventListener("drop",function(ev){
        ev.preventDefault();
        th.classList.remove("drop-target");
        if(!dragSource || dragSource===colId){return;}
        const order=state.order.slice();
        const fromIdx=order.indexOf(dragSource);
        const toIdx=order.indexOf(colId);
        order.splice(fromIdx,1);
        order.splice(toIdx,0,dragSource);
        state.order=order;
        buildHeaders();
        render();
      });

      elements.headerRow.appendChild(th);

      const filterCell=document.createElement("th");
      let placeholder="Filtrar";
      if(col.type==="number"){placeholder=">=, <=, =";}
      else if(col.type==="date"){placeholder="YYYY-MM-DD";}
      else if(col.filterPlaceholder){placeholder=col.filterPlaceholder;}
      filterCell.innerHTML="<input data-col=\""+colId+"\" placeholder=\""+placeholder+"\"/>";
      const input=filterCell.querySelector("input");
      if(input){
        input.value=state.filters[colId]||"";
        input.addEventListener("input",function(ev){
          state.filters[colId]=ev.target.value.trim();
          state.page=1;
          render();
        });
      }
      elements.filterRow.appendChild(filterCell);
    });
  }

  function applyFilters(skipUnit){
    const searchTerm=state.search.toLowerCase();
    const hasSearch=searchTerm.length>0;
    return DATA.filter(function(row){
      if(!skipUnit && state.activeUnit && row.unidad!==state.activeUnit){return false;}
      if(hasSearch){
        const hay=(row.nombre+" "+row.ruta+" "+row.sha+" "+row.tipo+" "+row.unidad).toLowerCase();
        if(!hay.includes(searchTerm)){return false;}
      }
      for(const key in state.filters){
        if(!Object.prototype.hasOwnProperty.call(state.filters,key)){continue;}
        const raw=state.filters[key];
        if(!raw){continue;}
        if(key==="tamano"){
          const match=raw.match(/^\s*(>=|<=|=)\s*(\d+)\s*$/);
          const current=Number(row.tamano||0);
          if(match){
            const op=match[1];
            const val=Number(match[2]);
            if(op===">=" && !(current>=val)){return false;}
            if(op==="<=" && !(current<=val)){return false;}
            if(op==="=" && current!==val){return false;}
          }else{
            if(human(current).toLowerCase().indexOf(raw.toLowerCase())===-1){return false;}
          }
        }else if(key==="fecha"){
          if(!(row.fecha||"").toLowerCase().startsWith(raw.toLowerCase())){return false;}
        }else{
          const compare=(row[key]||"").toString().toLowerCase();
          if(!compare.includes(raw.toLowerCase())){return false;}
        }
      }
      return true;
    });
  }

  function renderChips(rows){
    elements.chips.innerHTML="";
    const counts=new Map();
    rows.forEach(function(row){
      if(!row.unidad){return;}
      counts.set(row.unidad,(counts.get(row.unidad)||0)+1);
    });
    const allBtn=document.createElement("button");
    allBtn.textContent="Todas ("+rows.length+")";
    allBtn.className="chip-all";
    allBtn.dataset.active=state.activeUnit===""?"true":"false";
    allBtn.addEventListener("click",function(){state.activeUnit="";state.page=1;render();});
    elements.chips.appendChild(allBtn);
    const entries=Array.from(counts.entries());
    if(state.activeUnit && !counts.has(state.activeUnit)){
      entries.push([state.activeUnit,0]);
    }
    entries.sort(function(a,b){
      return a[0].localeCompare(b[0],undefined,{numeric:true,sensitivity:"base"});
    }).forEach(function(entry){
      const btn=document.createElement("button");
      btn.textContent=entry[0]+" ("+entry[1]+")";
      btn.dataset.unit=entry[0];
      btn.dataset.active=state.activeUnit===entry[0]?"true":"false";
      btn.addEventListener("click",function(){
        state.activeUnit=state.activeUnit===entry[0]?"":entry[0];
        state.page=1;
        render();
      });
      elements.chips.appendChild(btn);
    });
  }

  function renderTableBody(rows){
    elements.tbody.innerHTML="";
    const fragment=document.createDocumentFragment();
    rows.forEach(function(row){
      const tr=document.createElement("tr");
      state.order.forEach(function(colId){
        const col=columns[colId];
        const td=document.createElement("td");
        if(col.className){td.className=col.className;}
        let html="";
        if(col.render){html=col.render(row);}else{html=escapeHtml((col.get?col.get(row):row[colId])||"");}
        td.innerHTML=html;
        tr.appendChild(td);
      });
      fragment.appendChild(tr);
    });
    elements.tbody.appendChild(fragment);
  }

  function renderInsights(rows){
    const empty="<li>Sin datos</li>";
    elements.unitSummary.innerHTML=empty;
    elements.extSummary.innerHTML=empty;
    elements.pathSummary.innerHTML=empty;
    if(!rows.length){return;}

    const byUnit=new Map();
    const byExt=new Map();
    const byPath=new Map();

    rows.forEach(function(row){
      const unit=(row.unidad||"(sin unidad)").toString();
      const unitStats=byUnit.get(unit)||{count:0,size:0};
      unitStats.count+=1;
      unitStats.size+=Number(row.tamano||0);
      byUnit.set(unit,unitStats);

      const name=row.nombre||"";
      const ext=name.includes(".")?name.split(".").pop().toLowerCase():"(sin extensión)";
      const extStats=byExt.get(ext)||{count:0};
      extStats.count+=1;
      byExt.set(ext,extStats);

      const path=(row.ruta||"(sin ruta)").toString();
      const pathStats=byPath.get(path)||{count:0};
      pathStats.count+=1;
      byPath.set(path,pathStats);
    });

    const unitItems=Array.from(byUnit.entries()).sort(function(a,b){
      return b[1].count-a[1].count || b[1].size-a[1].size;
    }).slice(0,6).map(function(entry){
      const key=escapeHtml(entry[0]);
      const stats=entry[1];
      return "<li>"+key+": "+stats.count.toLocaleString("es-ES")+" archivos ("+escapeHtml(human(stats.size))+")</li>";
    }).join("");

    const extItems=Array.from(byExt.entries()).sort(function(a,b){
      return b[1].count-a[1].count;
    }).slice(0,6).map(function(entry){
      const key=escapeHtml(entry[0]);
      return "<li>"+key+": "+entry[1].count.toLocaleString("es-ES")+" archivos</li>";
    }).join("");

    const pathItems=Array.from(byPath.entries()).sort(function(a,b){
      return b[1].count-a[1].count;
    }).slice(0,6).map(function(entry){
      const key=escapeHtml(entry[0]);
      return "<li>"+key+": "+entry[1].count.toLocaleString("es-ES")+" archivos</li>";
    }).join("");

    elements.unitSummary.innerHTML=unitItems||empty;
    elements.extSummary.innerHTML=extItems||empty;
    elements.pathSummary.innerHTML=pathItems||empty;
  }

  function computeBytes(rows){return rows.reduce((sum,row)=>sum+Number(row.tamano||0),0);}
  function getCurrentSlice(rows){
    const perPage=state.pageSize;
    if(perPage===0){return rows.slice();}
    const totalPages=Math.max(1,Math.ceil(rows.length/perPage));
    if(state.page>totalPages){state.page=totalPages;}
    const start=(state.page-1)*perPage;
    return rows.slice(start,start+perPage);
  }
  function renderSummary(totalRows,totalBytes){
    elements.count.textContent=totalRows.toLocaleString("es-ES");
    elements.size.textContent=human(totalBytes);
    const perPage=state.pageSize;
    const totalPages=perPage===0?1:Math.max(1,Math.ceil(totalRows/perPage));
    if(state.page>totalPages){state.page=totalPages;}
    const safePage=state.page;
    const start=perPage===0?1:((safePage-1)*perPage)+1;
    const end=perPage===0?totalRows:Math.min(totalRows,safePage*perPage);
    elements.pageInfo.textContent=totalRows===0?"Sin resultados":`Mostrando ${start.toLocaleString("es-ES")} - ${end.toLocaleString("es-ES")} de ${totalRows.toLocaleString("es-ES")}`;
    elements.prev.disabled=safePage<=1;
    elements.next.disabled=safePage>=totalPages;
  }
  function downloadCsv(rows){
    if(!rows.length){return;}
    const headers=state.order.map(colId=>columns[colId].label.replace(/&ntilde;/g,"ñ").replace(/<[^>]+>/g,""));
    const lines=[headers.join(";")];
    rows.forEach(function(row){
      const values=state.order.map(function(colId){
        const col=columns[colId];
        const raw=col.csv?col.csv(row):(col.get?col.get(row):row[colId]);
        const text=(raw??"").toString().replace(/"/g,'""');
        return "\""+text+"\"";
      });
      lines.push(values.join(";"));
    });
    const blob=new Blob([lines.join("\r\n")],{type:"text/csv;charset=utf-8;"});
    const url=URL.createObjectURL(blob);
    const link=document.createElement("a");
    link.href=url;
    link.download="inventario_filtrado.csv";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    setTimeout(()=>URL.revokeObjectURL(url),200);
  }

  elements.q.addEventListener("input",function(ev){state.search=ev.target.value.trim();state.page=1;render();});
  elements.pageSize.addEventListener("change",function(ev){state.pageSize=Number(ev.target.value);state.page=1;render();});
  elements.prev.addEventListener("click",function(){if(state.page>1){state.page--;render();}});
  elements.next.addEventListener("click",function(){state.page++;render();});
  elements.download.addEventListener("click",function(){downloadCsv(applyFilters(false));});
  elements.resetCols.addEventListener("click",function(){state.order=defaultOrder.slice();state.widths=Object.assign({},defaultWidths);buildHeaders();state.page=1;render();});

  function render(){
    const filteredWithoutUnit=applyFilters(true);
    const filtered=applyFilters(false);
    const bytes=computeBytes(filtered);
    renderChips(filteredWithoutUnit);
    renderInsights(filtered);
    const pageRows=getCurrentSlice(filtered);
    renderTableBody(pageRows);
    renderSummary(filtered.length,bytes);
    elements.download.disabled=filtered.length===0;
  }

})();
</script></main></body></html>
'@

$payload = if ($EmbedBase64) {
  [Regex]::Escape($b64) -replace "\\Q|\\E",""
} else {
  ""
}

$tpl = $tpl.Replace("__B64__", $payload)
Set-Content -Encoding UTF8 $HtmlPath $tpl
Write-Host "? HTML: $HtmlPath" -ForegroundColor Green

if (-not $NoOpen) {
  Start-Process $HtmlPath
}


