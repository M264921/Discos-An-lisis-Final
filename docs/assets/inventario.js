<<<<<<< HEAD
﻿(()=> {
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
=======
﻿/**
 * inventario.js (auto-patched)
 * Soporta:
 * 1) JSON embebido:  <script id="inventory-data" type="application/json">…</script>
 * 2) data/inventory.json
 * 3) data/inventory.min.json
 * 4) data/inventory.json.gz (requiere que el servidor añada Content-Encoding:gzip
 *    o bien que exista window.pako.ungzip para descomprimir en cliente)
 */
(function () {
  "use strict";
>>>>>>> main

  async function tryFetchJson(url) {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) throw new Error("HTTP " + res.status + " @ " + url);

    // Si el servidor ya descomprime (Content-Encoding:gzip), res.json() funciona.
    // Si realmente viene .gz sin cabeceras (p.ej. http.server), necesitamos pako.
    if (url.endsWith(".gz")) {
      // Intenta primero como JSON "normal" (por si el server ya lo descomprimió)
      try {
        return await res.json();
      } catch (_) {
        // Intento con pako si está presente
        if (window.pako && typeof window.pako.ungzip === "function") {
          const buf = await res.arrayBuffer();
          const uint = new Uint8Array(buf);
          const text = window.pako.ungzip(uint, { to: "string" });
          return JSON.parse(text);
        }
        throw new Error(
          "El archivo " + url + " está comprimido y el servidor no envía Content-Encoding:gzip.\n" +
          "Opciones:\n" +
          "  a) Servirlo con cabecera Content-Encoding:gzip (nginx/Apache/Express) o\n" +
          "  b) Incluir pako (https://github.com/nodeca/pako) antes de este script para descomprimir en cliente,\n" +
          "  c) Usar data/inventory.json o data/inventory.min.json."
        );
      }
    }

    // Caso normal: JSON llano
    return await res.json();
  }

  async function loadInventoryData() {
    // 1) Embebido
    const embedded = document.getElementById("inventory-data");
    if (embedded && embedded.textContent && embedded.textContent.trim().length > 0) {
      console.log("📦 Cargando datos embebidos en el HTML…");
      return JSON.parse(embedded.textContent);
    }

    // 2) Rutas externas candidatas (orden de preferencia)
    const candidates = [
      "data/inventory.json",
      "data/inventory.min.json",
      "data/inventory.json.gz"
    ];

    let lastErr = null;
    for (const url of candidates) {
      try {
        console.log("🌐 Probando:", url);
        const data = await tryFetchJson(url);
        console.log("✅ OK:", url);
        return data;
      } catch (e) {
        console.warn("⚠️ Falló", url, "→", e.message);
        lastErr = e;
      }
    }
    throw lastErr || new Error("No se pudo cargar ningún origen de datos.");
  }

  function render(data) {
    // Usa la función de tu tabla si existe.
    if (typeof renderInventory === "function") return renderInventory(data);
    if (typeof buildTable === "function") return buildTable(data);

    console.error("❌ No se encontró renderInventory() ni buildTable(). Ajusta aquí tu inicialización.");
    // Ejemplo mínimo si no hay renderer:
    // console.table(data.slice(0, 10));
  }

  document.addEventListener("DOMContentLoaded", async () => {
    try {
      const data = await loadInventoryData();
      render(data);
    } catch (err) {
      console.error("❌ Error cargando inventario:", err);
      alert("No se pudo cargar el inventario.\n" + err.message);
    }
  });
})();


