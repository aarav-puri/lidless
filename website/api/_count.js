// Shared download counter. Every click on a Download button goes through /api/download,
// which bumps this counter before redirecting to the zip, so the number on the site is clicks
// that started a download. Stored on Abacus (a free counter service, no account needed).
const COUNTER = 'https://abacus.jasoncameron.dev';
const KEY = 'lidless-gamma/downloads';
const ZIP = 'https://github.com/aarav-puri/lidless/releases/latest/download/Lidless.zip';

async function call(path, ms = 2000) {
  const r = await fetch(`${COUNTER}/${path}/${KEY}`, { signal: AbortSignal.timeout(ms) });
  if (r.status === 404) return 0; // nobody has downloaded yet
  if (!r.ok) throw new Error('counter ' + r.status);
  const { value } = await r.json();
  return Number.isFinite(value) ? value : 0;
}

module.exports = { hit: () => call('hit'), get: () => call('get'), ZIP };
