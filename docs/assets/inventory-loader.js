/* Loader robusto para inventory.json(.gz)
   - Detecta JSON plano vs GZIP
   - Solo descomprime si empieza por 0x1f 0x8b (gzip)
   - Fallback a JSON sin comprimir si falla
*/
export async function loadInventory({ gzUrl = "data/inventory.json.gz", jsonUrl = "data/inventory.json" } = {}) {
  // fflate para gunzip
  const { gunzipSync } = await import("https://cdn.jsdelivr.net/npm/fflate/esm/browser.js");

  async function fetchAsBytes(url) {
    const res = await fetch(url, { cache: "no-cache" });
    if (!res.ok) throw new Error(`HTTP ${res.status} al pedir ${url}`);
    return new Uint8Array(await res.arrayBuffer());
  }

  // 1) intenta .gz primero
  try {
    const bytes = await fetchAsBytes(gzUrl);

    // Si el primer byte es "{" o "[" => ya es JSON plano (servidor lo ha servido sin gzip a nivel de transporte o nos pasaron .json con .gz de nombre)
    const first = bytes[0];
    let text;
    if (first === 0x7B || first === 0x5B) {
      text = new TextDecoder("utf-8").decode(bytes);
    } else {
      // Si tiene cabecera gzip (1f 8b), descomprime
      const isGzip = bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
      if (!isGzip) throw new Error("No es gzip ni JSON plano");
      const decompressed = gunzipSync(bytes);
      text = new TextDecoder("utf-8").decode(decompressed);
    }
    return JSON.parse(text);
  } catch (e) {
    console.warn("[loader] gz falló o no era gzip/JSON plano:", e?.message || e);
  }

  // 2) fallback a JSON sin comprimir
  const res = await fetch(jsonUrl, { cache: "no-cache" });
  if (!res.ok) throw new Error(`HTTP ${res.status} al pedir ${jsonUrl}`);
  return await res.json();
}
