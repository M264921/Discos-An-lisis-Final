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

