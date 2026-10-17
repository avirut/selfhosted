// Run against a private prepared release. Only a loopback test server is opened;
// the five real daemons are read through their normal encrypted relay connections.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE ?? 'playwright-core');
const root = path.resolve(process.argv[2]);
const config = JSON.parse(await readFile(path.join(root, '_kroacnet/hosts.json'), 'utf8'));
const ids = config.hosts.map(host => host.offer.serverId);
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.css': 'text/css', '.png': 'image/png', '.svg': 'image/svg+xml' };
const server = createServer(async (request, response) => {
  try {
    const requested = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    let file = path.resolve(root, '.' + requested);
    if (!file.startsWith(root + path.sep) && file !== root) throw new Error('Outside root');
    try { if (!(await stat(file)).isFile()) file = path.join(root, 'index.html'); }
    catch { file = path.join(root, 'index.html'); }
    response.setHeader('Content-Type', mime[path.extname(file)] ?? 'application/octet-stream');
    response.setHeader('Cache-Control', 'private, no-store');
    response.end(await readFile(file));
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
let browser;
try {
  browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH, headless: true });
  const contexts = await Promise.all([browser.newContext(), browser.newContext()]);
  const pages = await Promise.all(contexts.map(context => context.newPage()));
  for (let index = 0; index < pages.length; index++) {
    const page = pages[index];
    await page.goto(origin);
    await page.waitForFunction(expected => {
      const runtime = globalThis.__paseoHostRuntimeStore;
      return runtime && expected.every(id => runtime.getSnapshot(id)?.connectionStatus === 'online');
    }, ids, { timeout: 45000 });
    const observed = await page.evaluate(() => {
      const runtime = globalThis.__paseoHostRuntimeStore;
      return runtime.getHosts().map(host => ({ name: host.label, serverId: host.serverId,
        status: runtime.getSnapshot(host.serverId).connectionStatus }));
    });
    assert.equal(observed.length, config.hosts.length);
    for (const host of config.hosts) assert(observed.some(row => row.name === host.name && row.serverId === host.offer.serverId));
    console.log(JSON.stringify({ freshBrowser: index + 1, hosts: observed.map(row => ({ name: row.name, status: row.status })) }));
  }
  const clientIds = await Promise.all(pages.map(page => page.evaluate(() => localStorage.getItem('@paseo:client-id-v1'))));
  assert(clientIds[0] && clientIds[1] && clientIds[0] !== clientIds[1]);
  console.log('Independent browser identities preserved.');

  // A protected configuration failure must not run Paseo with a partially seeded list.
  const page = pages[0];
  const saved = await page.evaluate(() => localStorage.getItem('@paseo:daemon-registry'));
  await page.route('**/_kroacnet/hosts.json', route => route.fulfill({ status: 503, body: '' }));
  await page.reload();
  await page.getByText('Couldn’t load hosts.', { exact: true }).waitFor();
  assert.equal(await page.evaluate(() => localStorage.getItem('@paseo:daemon-registry')), saved);
  assert.equal(await page.evaluate(() => Boolean(globalThis.__paseoHostRuntimeStore)), false);
  console.log('Unavailable configuration preserves stored hosts and blocks app startup.');
  await page.unroute('**/_kroacnet/hosts.json');
  await page.reload();
  await page.waitForFunction(expected => globalThis.__paseoHostRuntimeStore?.getHosts().length === expected,
    config.hosts.length);
  console.log('Reload recovers without duplicate hosts.');
} catch (error) {
  // Do not print source snippets, page contents, offers or private agent titles.
  console.error(`Browser verification failed: ${error.name}`);
  process.exitCode = 1;
} finally {
  await browser?.close();
  await new Promise(resolve => server.close(resolve));
}
