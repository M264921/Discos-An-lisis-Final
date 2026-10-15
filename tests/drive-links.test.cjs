const test = require('node:test');
const assert = require('node:assert/strict');
const { createDriveLinks, decorateLink } = require('../tools/templates/inventory-drive-links.js');

function fixture(protocol = 'file:') {
  let snapshot = ['C', 'K'];
  let reachable = true;
  const state = createDriveLinks({
    protocol, candidates: ['http://127.0.0.1:8765'],
    fetch: async () => {
      if (!reachable) throw new Error('offline');
      return { ok: true, json: async () => ({ service: 'MingoMedia.files', drives: snapshot }) };
    }
  });
  return { state, mounted(value) { snapshot = value; }, offline() { reachable = false; } };
}

function anchor(href, title = 'Abrir archivo') {
  const attributes = new Map([['href', href], ['title', title]]);
  return {
    textContent: 'Documento de ejemplo',
    getAttribute: key => attributes.has(key) ? attributes.get(key) : null,
    setAttribute: (key, value) => attributes.set(key, value),
    removeAttribute: key => attributes.delete(key)
  };
}

test('no links before detection; only currently mounted letters afterwards', async () => {
  const { state } = fixture();
  assert.equal(state.url('file:///C:/demo.txt'), '');
  await state.refresh();
  assert.equal(state.url('file:///C:/demo.txt'), 'file:///C:/demo.txt');
  assert.equal(state.url('file:///K:/demo.txt'), 'file:///K:/demo.txt');
  for (const drive of ['H', 'I', 'J']) assert.equal(state.url(`file:///${drive}:/demo.txt`), '');
});

test('refresh drops disconnected drives and enables newly mounted ones without remapping', async () => {
  const f = fixture();
  await f.state.refresh();
  f.mounted(['C', 'L']);
  await f.state.refresh();
  assert.equal(f.state.url('file:///K:/demo.txt'), '');
  assert.equal(f.state.url('file:///H:/demo.txt'), '');
  assert.equal(f.state.url('file:///L:/demo.txt'), 'file:///L:/demo.txt');
});

test('an unreachable service clears stale links', async () => {
  const f = fixture();
  await f.state.refresh();
  f.offline();
  await f.state.refresh();
  assert.equal(f.state.url('file:///C:/demo.txt'), '');
});

test('HTTP pages use the file service with escaped paths; folders have no broken HTTP links', async () => {
  const { state } = fixture('https:');
  await state.refresh();
  assert.equal(state.url('file:///C:/mi%20archivo.txt'), 'http://127.0.0.1:8765/files/C/mi%20archivo.txt');
  assert.equal(state.url('file:///C:/folder', { folder: true }), '');
  assert.equal(state.url('file:///C:/'), '');
});

test('unknown paths, UNC hosts and non-file schemes are not treated as mounted letters', async () => {
  const { state } = fixture();
  await state.refresh();
  for (const url of ['file://server/share/a.txt', 'https://example.test/a.txt', 'javascript:alert(1)', 'not-a-url']) {
    assert.equal(state.url(url), '');
  }
});

test('unavailable links become text and are restored only for their own mounted letter', async () => {
  const f = fixture();
  const a = anchor('file:///H:/demo.txt');
  decorateLink(a, f.state);
  assert.equal(a.getAttribute('href'), null);
  assert.equal(a.textContent, 'Documento de ejemplo');
  await f.state.refresh();
  decorateLink(a, f.state);
  assert.equal(a.getAttribute('href'), null);
  f.mounted(['H']);
  await f.state.refresh();
  decorateLink(a, f.state);
  assert.equal(a.getAttribute('href'), 'file:///H:/demo.txt');
  f.mounted([]);
  await f.state.refresh();
  decorateLink(a, f.state);
  assert.equal(a.getAttribute('href'), null);
});

test('external links are preserved and local folders remain local in file viewers', async () => {
  const f = fixture();
  await f.state.refresh();
  const remote = anchor('https://example.test');
  decorateLink(remote, f.state);
  assert.equal(remote.getAttribute('href'), 'https://example.test');
  const folder = anchor('file:///C:/folder', 'Abrir carpeta');
  decorateLink(folder, f.state);
  assert.equal(folder.getAttribute('href'), 'file:///C:/folder');
});
