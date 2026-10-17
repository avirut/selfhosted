import { applyConfiguration } from './managed-hosts.mjs';

async function start() {
  const bundle = document.querySelector('script[data-paseo-bundle]')?.dataset.paseoBundle;
  if (!/^\/_expo\/static\/js\/web\/index-[a-f0-9]+\.js$/.test(bundle ?? '')) {
    throw new Error('Unsupported Paseo bundle');
  }
  const response = await fetch('/_kroacnet/hosts.json', {
    credentials: 'same-origin',
    cache: 'no-store',
    redirect: 'error',
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok || !response.headers.get('content-type')?.includes('application/json')) {
    throw new Error('Host configuration unavailable');
  }
  applyConfiguration(window.localStorage, await response.json());
  const script = document.createElement('script');
  script.src = bundle;
  script.onerror = showFailure;
  document.body.append(script);
}

function showFailure() {
  // No raw errors or configuration values in logs or in the page.
  const root = document.getElementById('root');
  root.replaceChildren();
  root.style.cssText = 'display:flex;align-items:center;justify-content:center;gap:12px;font:16px system-ui';
  const message = document.createElement('span');
  message.textContent = 'Couldn’t load hosts.';
  const retry = document.createElement('button');
  retry.textContent = 'Retry';
  retry.onclick = () => location.reload();
  root.append(message, retry);
}

start().catch(showFailure);
