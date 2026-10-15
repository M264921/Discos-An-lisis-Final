const {spawn} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const base = process.env.MINGO_TEST_OUTPUT;
const browser = spawn(process.env.MINGO_TEST_BROWSER, [
  '--headless', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
  '--remote-debugging-pipe', '--window-size=390,844', '--user-data-dir=' + path.join(base, 'browser-profile')
], {stdio: ['ignore', 'ignore', 'pipe', 'pipe', 'pipe'], windowsHide: true});
let sequence = 0, pending = new Map(), buffer = '';
browser.stdio[4].on('data', chunk => {
  buffer += chunk.toString();
  let end;
  while ((end = buffer.indexOf('\0')) >= 0) {
    const raw = buffer.slice(0, end); buffer = buffer.slice(end + 1);
    if (!raw) continue;
    const reply = JSON.parse(raw);
    if (pending.has(reply.id)) {
      const {resolve, reject} = pending.get(reply.id); pending.delete(reply.id);
      reply.error ? reject(new Error(JSON.stringify(reply.error))) : resolve(reply.result);
    }
  }
});
function send(method, params = {}, sessionId) {
  return new Promise((resolve, reject) => {
    const id = ++sequence; pending.set(id, {resolve, reject});
    browser.stdio[3].write(JSON.stringify({id, method, params, ...(sessionId ? {sessionId} : {})}) + '\0');
  });
}
const sleep = ms => new Promise(r => setTimeout(r, ms));
let session;
async function evaluate(expression) {
  const result = await send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true}, session);
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
}
async function until(expression) {
  for (let i=0; i<100; i++) { const value = await evaluate(expression); if (value) return value; await sleep(100); }
  throw new Error('Timed out: ' + expression + ' BODY=' + await evaluate('document.body.innerText.slice(0,1000)'));
}
(async () => {
  const target = await send('Target.createTarget', {url:'about:blank'});
  session = (await send('Target.attachToTarget', {targetId:target.targetId, flatten:true})).sessionId;
  await send('Page.enable', {}, session);
  await send('Emulation.setDeviceMetricsOverride', {width:390,height:844,deviceScaleFactor:1,mobile:true}, session);
  await send('Page.navigate', {url:process.env.MINGO_TEST_URL}, session);
  await until('Boolean(document.querySelector("input[name=password]"))');
  await evaluate(`document.querySelector('input[name=password]').value=${JSON.stringify(process.env.MINGO_TEST_PASSWORD)};document.querySelector('form').requestSubmit();true`);
  await until('Boolean(document.querySelector("a[data-mingo-local-url][href]"))');
  const results = [];
  async function click(name) {
    await evaluate(`Array.from(document.querySelectorAll('a[data-mingo-local-url][href]')).find(a=>a.textContent.trim()===${JSON.stringify(name)}).click();true`);
    await until('Boolean(document.querySelector(".mingo-preview"))');
  }
  async function close() {
    await evaluate(`document.querySelector('.mingo-preview button').click();true`);
    if (await evaluate('Boolean(document.querySelector(".mingo-preview"))')) throw new Error('Did not close');
  }
  await click('preview.svg');
  await until('Boolean(document.querySelector(".mingo-preview img")?.naturalWidth)');
  const screenshot = await send('Page.captureScreenshot', {format:'png'}, session);
  fs.writeFileSync(path.join(base,'preview-mobile.png'), Buffer.from(screenshot.data,'base64'));
  results.push('image renders after clicking filename'); await close();
  await click('preview.txt');
  await until('Boolean(document.querySelector(".mingo-preview pre"))');
  if (!(await evaluate('document.querySelector(".mingo-preview pre").textContent.includes("<script>") && !window.previewInjected'))) throw new Error('Unsafe text');
  results.push('text renders literally without executing markup'); await close();
  await click('preview.wav');
  await until('Boolean(document.querySelector(".mingo-preview audio")?.readyState >= 1)');
  results.push('audio loads metadata and controls'); await close();
  await click('preview.pdf');
  await until('Boolean(document.querySelector(".mingo-preview iframe"))');
  results.push('PDF frame opens'); await close();
  await click('missing.txt');
  await until('document.querySelector(".mingo-preview")?.textContent.includes("ya no existe")');
  results.push('missing files show clear error'); await close();
  await click('preview.bin');
  await until('document.querySelector(".mingo-preview")?.textContent.includes("no tiene vista previa")');
  results.push('unsupported format offers download');
  await send('Input.dispatchKeyEvent', {type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27},session);
  if (await evaluate('Boolean(document.querySelector(".mingo-preview"))')) throw new Error('Escape did not close');
  results.push('Escape closes and returns to inventory');
  console.log(JSON.stringify({passed:results,screenshot:path.join(base,'preview-mobile.png')}));
})().catch(e=>{console.error(e.stack);process.exitCode=1;}).finally(async()=>{
  try {await send('Browser.close');} catch(_){}
  browser.kill();
});
