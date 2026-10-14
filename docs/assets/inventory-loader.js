// The published JSON is authoritative. Gzip is an optional offline fallback.
export async function loadInventory({ gzUrl = 'data/inventory.json.gz', jsonUrl = 'data/inventory.json' } = {}) {
  try {
    const response = await fetch(jsonUrl, { cache: 'no-cache' });
    if (!response.ok) throw new Error(`HTTP ${response.status} for ${jsonUrl}`);
    return await response.json();
  } catch (error) {
    console.warn('[loader] JSON unavailable; trying gzip:', error?.message || error);
  }
  const response = await fetch(gzUrl, { cache: 'no-cache' });
  if (!response.ok) throw new Error(`HTTP ${response.status} for ${gzUrl}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
    if (typeof DecompressionStream !== 'function') throw new Error('Gzip decompression unavailable; serve inventory.json.');
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
    return JSON.parse(await new Response(stream).text());
  }
  return JSON.parse(new TextDecoder('utf-8').decode(bytes));
}
