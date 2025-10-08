(() => {
  function readEmbedded() {
    const el = document.getElementById('inventory-data');
    if (!el) return null;
    try { return JSON.parse(el.textContent); } catch { return null; }
  }
  function driveFrom(p) {
    if (!p) return 'OTROS';
    const m = String(p).match(/^([A-Za-z]):/);
    return m ? m[1].toUpperCase() : 'OTROS';
  }
  function toInt(x) {
    if (typeof x === 'number') return x|0;
    const s = (x ?? '').toString().replace(/[^\d]/g,'');
    const n = parseInt(s,10);
    return Number.isFinite(n) ? n : 0;
  }
  function mapRow(r) {
    // admite tanto el esquema estándar como {tipo,nombre,ruta,unidad,tamano,fecha}
    const path  = r.path  ?? r.ruta  ?? r.full_path ?? r.location ?? '';
    const name  = r.name  ?? r.nombre ?? r.file     ?? '';
    const type  = r.type  ?? r.tipo   ?? r.category ?? 'otro';
    const size  = r.size  ?? r.bytes  ?? r.length   ?? r.tamano ?? 0;
    const drive = (r.drive ?? r.unidad) || driveFrom(path);
    const last  = r.last  ?? r.fecha  ?? r.modified ?? r.mtime ?? r.date ?? '';
    return {
      sha:  r.sha ?? r.hash ?? r.md5 ?? r.sha1 ?? r.sha256 ?? null,
      type, name, path, drive,
      size: toInt(size),
      last
    };
  }

  const embedded = (readEmbedded() || []).map(mapRow);

  // Si estamos abriendo con file://, interceptamos el fetch al JSON externo
  if (location.protocol === 'file:') {
    const origFetch = window.fetch.bind(window);
    window.fetch = async (url, opts) => {
      const u = (typeof url === 'string') ? url : (url?.url ?? '');
      if (/\/data\/inventory\.json(\?|$)/i.test(u)) {
        return new Response(JSON.stringify(embedded), {
          headers: { 'Content-Type': 'application/json' }
        });
      }
      return origFetch(url, opts);
    };
    // Señal útil para diagnóstico
    window.__INV_OFFLINE_BRIDGE__ = { rows: embedded.length };
  }
})();
