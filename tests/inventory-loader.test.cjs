const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { gzipSync } = require('node:zlib');
const source = readFileSync(join(__dirname, '../tools/inventory-loader.template.js'));
const reader = import('data:text/javascript;base64,' + source.toString('base64'));
const originalFetch = globalThis.fetch;
const originalDecompression = globalThis.DecompressionStream;
const rows = [{ nombre: 'ejemplo.txt', ruta: 'C:\\demo' }];
test.afterEach(() => {
  globalThis.fetch = originalFetch;
  globalThis.DecompressionStream = originalDecompression;
});

test('plain JSON is read from the response body once', async () => {
  const { fetchInventoryJson } = await reader;
  let reads = 0;
  globalThis.fetch = async () => ({
    ok: true,
    arrayBuffer: async () => { reads++; return Buffer.from(JSON.stringify(rows)); },
    json: () => { throw new Error('Would consume the response before gzip detection'); }
  });
  assert.deepEqual(await fetchInventoryJson('inventory.json'), rows);
  assert.equal(reads, 1);
});

test('real gzip works without pako or a CDN', async () => {
  const { fetchInventoryJson } = await reader;
  globalThis.fetch = async () => new Response(gzipSync(JSON.stringify(rows)));
  assert.deepEqual(await fetchInventoryJson('inventory.json.gz'), rows);
});

test('a transparently decompressed .gz response is parsed as JSON', async () => {
  const { fetchInventoryJson } = await reader;
  globalThis.fetch = async () => new Response(JSON.stringify(rows));
  assert.deepEqual(await fetchInventoryJson('inventory.json.gz'), rows);
});

test('Pages LFS pointer falls back to the complete compressed inventory', async () => {
  const { loadInventory } = await reader;
  const requested = [];
  globalThis.fetch = async url => {
    requested.push(url);
    return new Response(url.endsWith('.gz') ? gzipSync(JSON.stringify(rows)) : 'version https://git-lfs.github.com/spec/v1\noid sha256:example\nsize 100\n');
  };
  assert.deepEqual(await loadInventory(), rows);
  assert.deepEqual(requested, ['data/inventory.json', 'data/inventory.json.gz']);
});

test('HTTP failures and invalid JSON do not become a silent empty inventory', async () => {
  const { loadInventory } = await reader;
  globalThis.fetch = async url => url.endsWith('.gz') ? new Response('bad json') : new Response('', { status: 404 });
  await assert.rejects(loadInventory(), SyntaxError);
});

test('invalid inventory structure still tries the other source', async () => {
  const { loadInventory } = await reader;
  globalThis.fetch = async url => new Response(url.endsWith('.gz') ? gzipSync(JSON.stringify(rows)) : '{}');
  assert.deepEqual(await loadInventory(), rows);
});

test('missing decompression support gives an explicit error', async () => {
  const { fetchInventoryJson } = await reader;
  globalThis.DecompressionStream = undefined;
  globalThis.fetch = async () => new Response(gzipSync(JSON.stringify(rows)));
  await assert.rejects(fetchInventoryJson('inventory.json.gz'), /no puede descomprimir/);
});
