// Read a response once: a failed response.json() also consumes a gzip body.
export async function fetchInventoryJson(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) throw new Error(`No se pudo cargar ${url} (${response.status})`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  let text;
  if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
    if (typeof globalThis.DecompressionStream === 'function') {
      const stream = new Blob([bytes]).stream().pipeThrough(new globalThis.DecompressionStream('gzip'));
      text = await new Response(stream).text();
    } else if (globalThis.pako && typeof globalThis.pako.ungzip === 'function') {
      text = globalThis.pako.ungzip(bytes, { to: 'string' });
    } else {
      throw new Error('Este navegador no puede descomprimir el inventario. Usa un navegador actualizado.');
    }
  } else {
    // Some servers transparently decompress .gz resources during transport.
    text = new TextDecoder('utf-8').decode(bytes);
  }
  text = text.replace(/^\uFEFF/, '');
  if (text.startsWith('version https://git-lfs.github.com/spec/v1')) {
    throw new Error(`${url} es una referencia Git LFS; se necesita el archivo de datos.`);
  }
  return JSON.parse(text);
}

// Prefer JSON locally; Pages may serve its LFS pointer, so retain the full gzip.
export async function loadInventory({ gzUrl = 'data/inventory.json.gz', jsonUrl = 'data/inventory.json' } = {}) {
  let lastError;
  for (const url of [...new Set([jsonUrl, gzUrl])]) {
    try {
      const data = await fetchInventoryJson(url);
      if (Array.isArray(data) || (data && Array.isArray(data.data))) return data;
      throw new Error(`El archivo ${url} no contiene un inventario valido.`);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}
