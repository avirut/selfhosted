import assert from 'node:assert/strict';
import test from 'node:test';
import { applyConfiguration, reconcileHosts, REGISTRY_KEY, MANAGED_KEY } from './managed-hosts.mjs';

const host = (name, key = 'A'.repeat(43) + '=') => ({
  name, offer: { v: 2, serverId: `srv_${name}`, daemonPublicKeyB64: key,
    relay: { endpoint: 'relay.example.com:443', useTls: true } },
});
const config = { version: 1, hosts: [host('one'), host('two')] };
function storage(initial = {}) {
  const map = new Map(Object.entries(initial));
  return { getItem: key => map.get(key) ?? null, setItem: (key, value) => map.set(key, value) };
}

test('independent fresh browsers receive the same hosts without sharing client state', () => {
  const left = storage({ clientKey: 'left-only' });
  const right = storage({ clientKey: 'right-only' });
  assert.deepEqual(applyConfiguration(left, config).map(x => x.serverId), ['srv_one', 'srv_two']);
  assert.deepEqual(applyConfiguration(right, config).map(x => x.serverId), ['srv_one', 'srv_two']);
  assert.equal(left.getItem('clientKey'), 'left-only');
  assert.equal(right.getItem('clientKey'), 'right-only');
});

test('refresh updates configured identity while retaining local appearance and other hosts', () => {
  const browser = storage();
  const initial = applyConfiguration(browser, config);
  initial[0].appearance = { color: '#123456', badgeDisplay: 'label' };
  initial[0].password = 'local-only';
  const extra = { serverId: 'srv_extra', label: 'Personal', connections: [{ id: 'direct:local:1234', type: 'directTcp', endpoint: 'local:1234' }] };
  initial.push(extra);
  browser.setItem(REGISTRY_KEY, JSON.stringify(initial));
  const changed = { version: 1, hosts: [host('one', 'B'.repeat(43) + '='), host('two')] };
  const next = applyConfiguration(browser, changed);
  assert.equal(next.length, 3);
  assert.deepEqual(next[2], extra);
  assert.equal(next[0].connections[0].daemonPublicKeyB64, 'B'.repeat(43) + '=');
  assert.equal(next[0].password, 'local-only');
  assert.deepEqual(next[0].appearance, initial[0].appearance);
  assert.equal(applyConfiguration(browser, changed).length, 3);
});

test('removing a central host removes only previously managed entries', () => {
  const browser = storage();
  applyConfiguration(browser, config);
  const next = applyConfiguration(browser, { version: 1, hosts: [host('two')] });
  assert.deepEqual(next.map(x => x.serverId), ['srv_two']);
  assert.deepEqual(JSON.parse(browser.getItem(MANAGED_KEY)), ['srv_two']);
});

test('invalid config or malformed existing storage is preserved and blocks startup', () => {
  const browser = storage({ [REGISTRY_KEY]: 'not json' });
  assert.throws(() => applyConfiguration(browser, config));
  assert.equal(browser.getItem(REGISTRY_KEY), 'not json');
  assert.throws(() => reconcileHosts([], { version: 1, hosts: [host('one'), host('one')] }));
  assert.throws(() => reconcileHosts([], { version: 1, hosts: [{ ...host('one'), offer: { ...host('one').offer, relay: { endpoint: 'relay.example.com:80', useTls: false } } }] }));
});
