(()=> {
  async function __loadFromEmbedded() {
    const el = document.getElementById('inventory-data');
    if (!el) return null;
    try {
      const txt = el.textContent?.trim() ?? '';
      if (!txt) return [];
      // Acepta array u objeto
      const first = txt[0];
      if (first === '[' || first === '{') return JSON.parse(txt);
    } catch (e) {
      console.warn('Embedded JSON parse error:', e);
    }
    return null;
  }
  async function __loadFromFile() {
    // Solo intentar fetch si NO estamos en file://
    if (location.protocol.startsWith('http')) {
      const resp = await window.loadInventorySafe();
    }
    console.warn('file:// sin servidor http: no se intentará fetch de docs/data/inventory.json');
    return [];
  }
  // Loader público
  window.loadInventorySafe = async function() {
    const emb = await __loadFromEmbedded();
    if (emb && (Array.isArray(emb) ? emb.length : Object.keys(emb).length)) return emb;
    return await __loadFromFile();
  }
})();
(function(){
  const $ = s=>document.querySelector(s), $$=s=>Array.from(document.querySelectorAll(s));
  const dataBlock=$("#inventory-data"), metaBlock=$("#inventory-meta");
  let ROWS=[]; try{ ROWS=JSON.parse(dataBlock?.textContent||"[]"); }catch{ ROWS=[]; }
  const META = (()=>{ try{ return JSON.parse(metaBlock?.textContent||"{}"); }catch{return {}} })();

  const state={search:"",chipsDrive:new Set(),chipsType:new Set(),sort:{field:"name",dir:1},colFilters:{}};

  const fmtSize=n=>{ n=+n||0; const u=["B","KB","MB","GB","TB"]; let i=0; while(n>=1024&&i<u.length-1){n/=1024;i++;} return n? n.toFixed(i?1:0)+" "+u[i] : "0 B"; };
  const humanDate=s=> s? (""+s).slice(0,19).replace("T"," ") : "";

  function applyFilters(rows){
    const q=state.search.trim().toLowerCase();
    return rows.filter(r=>{
      if(q && !(`${r.sha||""} ${r.type||""} ${r.name||""} ${r.path||""}`.toLowerCase().includes(q))) return false;
      if(state.chipsDrive.size && !state.chipsDrive.has((r.drive||"OTROS").toUpperCase())) return false;
      if(state.chipsType.size  && !state.chipsType.has((r.type||"").toLowerCase())) return false;
      for(const [k,v] of Object.entries(state.colFilters)){
        const val=(r[k]??"")+""; if(v && !val.toLowerCase().includes(v.toLowerCase())) return false;
      }
      return true;
    });
  }
  function sortRows(rows){
    const {field,dir}=state.sort;
    return rows.slice().sort((a,b)=>{
      if(field==="size") return ((+a.size||0)-(+b.size||0))*dir;
      const A=(a[field]??"")+"", B=(b[field]??"")+"";
      return A.localeCompare(B,"es",{numeric:true,sensitivity:"base"})*dir;
    });
  }
  function render(){
    const tbody=$("#inv-table tbody");
    const out=sortRows(applyFilters(ROWS));
    tbody.innerHTML = out.map(r=>{
      const href = r.path && /^[A-Za-z]:/.test(r.path) ? `file:///${r.path.replace(/\\/g,"/")}` : "#";
      return `<tr>
        <td>${r.sha||""}</td>
        <td>${r.type||""}</td>
        <td>${r.name||""}</td>
        <td><a class="path" href="${href}" target="_blank" rel="noopener">${r.path||""}</a></td>
        <td>${(r.drive||"").toUpperCase()}</td>
        <td>${fmtSize(r.size)}</td>
        <td>${humanDate(r.last)}</td>
      </tr>`;
    }).join("");
    $("#stat-total").textContent = ROWS.length;
    $("#stat-visible").textContent = out.length;
    $("#stat-size").textContent = fmtSize(out.reduce((s,r)=>s+(+r.size||0),0));
  }

  $("#search").addEventListener("input",e=>{ state.search=e.target.value; render(); });
  $$(".chip-drive").forEach(ch=>ch.addEventListener("click",()=>{ const v=ch.dataset.drive.toUpperCase(); ch.classList.toggle("active"); ch.classList.contains("active")?state.chipsDrive.add(v):state.chipsDrive.delete(v); render(); }));
  $$(".chip-type").forEach(ch=>ch.addEventListener("click",()=>{ const v=ch.dataset.type.toLowerCase(); ch.classList.toggle("active"); ch.classList.contains("active")?state.chipsType.add(v):state.chipsType.delete(v); render(); }));
  $$("#inv-table thead .column-filters input").forEach(inp=>inp.addEventListener("input",()=>{ state.colFilters[inp.dataset.filter]=inp.value; render(); }));
  $$("#inv-table thead th.sortable").forEach(th=>th.addEventListener("click",()=>{ const f=th.dataset.sort; const same=state.sort.field===f; state.sort={field:f,dir:same?-state.sort.dir:1}; $$("#inv-table thead th.sortable").forEach(x=>x.removeAttribute("data-direction")); th.setAttribute("data-direction",state.sort.dir===1?"asc":"desc"); render(); }));
  $("#reset").addEventListener("click",()=>{ state.search=""; $("#search").value=""; state.chipsDrive.clear(); state.chipsType.clear(); $$(".chip").forEach(c=>c.classList.remove("active")); state.colFilters={}; $$("#inv-table thead .column-filters input").forEach(i=>i.value=""); state.sort={field:"name",dir:1}; render(); });
  $("#download").addEventListener("click",()=>{ const rows=sortRows(applyFilters(ROWS)); const head=["sha","type","name","path","drive","size","last"].join(","); const body=rows.map(r=>[r.sha||"",r.type||"",r.name||"",r.path||"", (r.drive||"").toUpperCase(), r.size||0, r.last||""].map(x=>`"${(x+"").replace(/"/g,'""')}"`).join(",")); const csv="\uFEFF"+[head,...body].join("\r\n"); const a=document.createElement("a"); a.href=URL.createObjectURL(new Blob([csv],{type:"text/csv;charset=utf-8;"})); a.download="inventario_filtrado.csv"; a.click(); URL.revokeObjectURL(a.href); });

  render();
})();


;(() => {
  // === DOM Pagination (auto-inyectado) ===
  const PAGER_NS = 'INVENTARIO_PAGER';
  if (window[PAGER_NS]) return; // evitar doble carga

  const state = {
    page: 1,
    pageSize: parseInt(localStorage.getItem('inv.pageSize') || '25', 10),
    total: 0, from: 0, to: 0, lastPage: 1
  };

  function findTbody(){
    // Intenta encontrar un tbody 'oficial'; si hay data-attr úsalo.
    const byData = document.querySelector('table[data-inventario] tbody, [data-table="inventario"] tbody');
    if (byData) return byData;
    // fallback: primer tbody visible con filas
    const all = Array.from(document.querySelectorAll('table tbody'));
    const candidate = all.find(tb => tb && tb.children && tb.children.length >= 0);
    return candidate || null;
  }

  function countVisibleRows(tbody){
    // Cuenta filas "visibles" según CSS (no display:none)
    const rows = Array.from(tbody.children);
    return rows.filter(tr => (tr.offsetParent !== null) || (getComputedStyle(tr).display !== 'none')).length;
  }

  function sliceDom(tbody){
    const rows = Array.from(tbody.children);
    // filtradas actuales = las que no están 'display:none' por otros filtros
    const filtered = rows.filter(tr => (tr.dataset.hiddenByFilter !== '1')); // si tu código marca algo así
    // si no existe tal marca, usa visibilidad real
    const effective = filtered.length ? filtered : rows.filter(tr => (tr.style.display !== 'none'));

    state.total = effective.length;
    state.lastPage = Math.max(1, Math.ceil(state.total / state.pageSize));
    if (state.page > state.lastPage) state.page = state.lastPage;
    const start = (state.page - 1) * state.pageSize;
    const end   = Math.min(start + state.pageSize, state.total);
    state.from = state.total ? (start + 1) : 0;
    state.to   = end;

    // Oculta todas y muestra solo el rango
    // Primero: asegura que no interfiera con ocultaciones por filtro
    rows.forEach(tr => tr.dataset.hiddenByPager = '1'); // marca previa
    effective.forEach((tr, idx) => {
      if (idx >= start && idx < end) {
        tr.style.display = '';
        tr.dataset.hiddenByPager = '0';
      } else {
        tr.style.display = 'none';
        tr.dataset.hiddenByPager = '1';
      }
    });

    // Si hay filas fuera de 'effective', respeta su display tal cual
    rows.forEach(tr => {
      if (!effective.includes(tr) && tr.dataset.hiddenByFilter === '1') {
        tr.style.display = 'none';
      }
    });
  }

  function ensureControls(){
    if (document.getElementById('pager-controls')) return;

    const host =
      document.getElementById('toolbar') ||
      document.querySelector('.toolbar') ||
      document.body;

    const wrap = document.createElement('div');
    wrap.id = 'pager-controls';
    wrap.className = 'pager';
    wrap.innerHTML = [
      '<label>Mostrar ',
      '<select id="page-size">',
      '<option>10</option><option>25</option><option>50</option><option>100</option>',
      '</select> filas</label>',
      '<button id="first-page" title="Primera">«</button>',
      '<button id="prev-page"  title="Anterior">‹</button>',
      '<span id="page-info">0–0 de 0</span>',
      '<button id="next-page"  title="Siguiente">›</button>',
      '<button id="last-page"  title="Última">»</button>'
    ].join('');

    // Inserta al inicio del host
    if (host.firstChild) host.insertBefore(wrap, host.firstChild);
    else host.appendChild(wrap);

    // Set inicial selector
    const sel = wrap.querySelector('#page-size');
    sel.value = String(state.pageSize);
    sel.addEventListener('change', () => {
      state.pageSize = parseInt(sel.value, 10);
      localStorage.setItem('inv.pageSize', String(state.pageSize));
      state.page = 1;
      window[PAGER_NS].apply();
    });

    wrap.querySelector('#first-page').onclick = () => { state.page = 1; window[PAGER_NS].apply(); };
    wrap.querySelector('#prev-page').onclick  = () => { state.page = Math.max(1, state.page-1); window[PAGER_NS].apply(); };
    wrap.querySelector('#next-page').onclick  = () => { state.page = Math.min(state.lastPage, state.page+1); window[PAGER_NS].apply(); };
    wrap.querySelector('#last-page').onclick  = () => { state.page = state.lastPage; window[PAGER_NS].apply(); };
  }

  function updateControls(){
    const info = document.getElementById('page-info');
    const b1 = document.getElementById('first-page');
    const b2 = document.getElementById('prev-page');
    const b3 = document.getElementById('next-page');
    const b4 = document.getElementById('last-page');
    if (!info || !b1) return;
    info.textContent = ${state.from}– de ;
    b1.disabled = b2.disabled = (state.page === 1);
    b3.disabled = b4.disabled = (state.page === state.lastPage);
  }

  // Observa el tbody para re-aplicar paginación después de renders/filtrados
  let observer;
  function observeTbody(tbody){
    if (observer) observer.disconnect();
    observer = new MutationObserver(() => {
      // reset a pág. 1 si cambió el número de filas visiblemente
      state.page = 1;
      window[PAGER_NS].apply();
    });
    observer.observe(tbody, { childList: true, subtree: false, attributes: true, attributeFilter: ['style','data-hidden-by-filter'] });
  }

  function apply(){
    const tbody = findTbody();
    if (!tbody) return;
    sliceDom(tbody);
    updateControls();
  }

  function init(){
    ensureControls();
    const tbody = findTbody();
    if (tbody) observeTbody(tbody);
    apply();
  }

  window[PAGER_NS] = { init, apply, _state: state };
  window.addEventListener('DOMContentLoaded', () => {
    // Inicia cuando la página esté lista
    setTimeout(init, 0);
  });
})();


