// Renders every Lidless brand asset from logo.svg with headless Chromium (Playwright).
// Usage: node app/brand/render.js
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const here = __dirname, root = path.join(here, '..', '..');
const svg = fs.readFileSync(path.join(here, 'logo.svg'), 'utf8').replace(/<!--[\s\S]*?-->/, '');
const font = "-apple-system, 'SF Pro Display', Inter, system-ui, sans-serif";

// The mark sits roughly in x 150..875, y 420..660 of the 1024 canvas.
const crop = (w, h, s) => `<div style="width:${w}px;height:${h}px;overflow:hidden;position:relative">
  <div style="position:absolute;left:${-150 * s + (w - 725 * s) / 2}px;top:${-385 * s + (h - 310 * s) / 2}px;width:${1024 * s}px;height:${1024 * s}px">${svg.replace('width="1024" height="1024"', 'width="100%" height="100%"')}</div></div>`;
// App icon: the mark on a black glass tile.
const tile = (size, radius) => `<div style="width:${size}px;height:${size}px;border-radius:${radius}px;overflow:hidden;position:relative;
  background:radial-gradient(120% 90% at 50% 0%, #16203a 0%, #05070d 60%, #000 100%);
  box-shadow:inset 0 0 0 ${size / 256}px rgba(255,255,255,.14)">
  <div style="position:absolute;inset:0;transform:scale(1.32) translateY(-4%)">${svg.replace('width="1024" height="1024"', 'width="100%" height="100%"')}</div></div>`;
const wordmark = dark => `<div style="display:flex;align-items:center;gap:22px;padding:0 6px;height:128px;font:600 78px/1 ${font};letter-spacing:-.035em;color:${dark ? '#f5f5f7' : '#0b0b0f'}">
  ${tile(112, 26)}<span style="transform:translateY(-4px)">lidless</span></div>`;

const jobs = [
  // [output, html, width, height, background]
  ['website/logo.png', crop(440, 188, 0.6), 440, 188],
  ['website/icon.png', `<div style="padding:0">${tile(512, 114)}</div>`, 512, 512],
  ['app/brand/icon.png', `<div style="padding:100px">${tile(824, 185)}</div>`, 1024, 1024],
  ['app/Resources/AppIcon.icon/Assets/lidless.png', `<div style="transform:scale(1.32) translateY(-4%)">${svg}</div>`, 1024, 1024],
  ['app/brand/logo-dark.png', wordmark(true), 470, 128],
  ['app/brand/logo-light.png', wordmark(false), 470, 128],
];

(async () => {
  const browser = await chromium.launch();
  for (const [out, html, width, height, bg] of jobs) {
    const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: out.includes('logo-') ? 2 : 1 });
    await page.setContent(`<html><body style="margin:0;background:${bg || 'transparent'}">${html}</body></html>`);
    await page.screenshot({ path: path.join(root, out), omitBackground: !bg, clip: { x: 0, y: 0, width, height } });
    await page.close();
    console.log('Wrote', out);
  }
  // Menubar icon previews for the README: a canvas port of app/Sources/StatusIcon.swift (20x18 pt, y up), at 8x on white.
  const page = await browser.newPage({ viewport: { width: 160, height: 144 } });
  for (const state of ['working', 'waiting', 'paused']) {
    await page.setContent('<canvas width="160" height="144"></canvas>');
    const png = await page.evaluate(state => {
      const c = document.querySelector('canvas'), g = c.getContext('2d');
      g.fillStyle = '#fff'; g.fillRect(0, 0, 160, 144);
      g.setTransform(8, 0, 0, -8, 0, 144); g.fillStyle = g.strokeStyle = '#000'; g.lineJoin = g.lineCap = 'round';
      const rr = (x, y, w, h, r) => { g.beginPath(); g.roundRect(x, y, w, h, r); g.fill(); };
      g.beginPath(); g.moveTo(4.6, 7.6); g.lineTo(15.4, 7.6); g.lineTo(18.4, 4.3); g.lineTo(1.6, 4.3); g.closePath(); g.lineWidth = 1.3; g.stroke();
      rr(1.4, 1.2, 17.2, 1.7, 0.85);
      if (state === 'working') {
        g.beginPath(); g.moveTo(6.2, 16.6); g.lineTo(9.2, 13.8); g.lineTo(6.2, 11.0); g.lineWidth = 1.6; g.stroke();
        rr(10.6, 10.3, 4.2, 1.6, 0.8);
      } else if (state === 'paused') {
        rr(9.2, 12.4, 1.6, 4.8, 0.8); g.beginPath(); g.ellipse(10, 10.45, 0.85, 0.85, 0, 0, 7); g.fill();
      } else rr(8, 10.3, 4, 1.6, 0.8);
      return c.toDataURL('image/png').split(',')[1];
    }, state);
    fs.writeFileSync(path.join(root, `docs/status-${state}.png`), Buffer.from(png, 'base64'));
    console.log(`Wrote docs/status-${state}.png`);
  }

  // Website screenshot for the README.
  const site = await browser.newPage({ viewport: { width: 1280, height: 860 } });
  await site.emulateMedia({ reducedMotion: 'reduce' });
  await site.goto('file://' + path.join(root, 'website/index.html'), { waitUntil: 'load' });
  await site.waitForTimeout(800);
  await site.screenshot({ path: path.join(root, 'docs/website.png') });
  console.log('Wrote docs/website.png');

  await browser.close();
})();
