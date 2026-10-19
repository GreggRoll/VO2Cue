// Render the share card from HTML/CSS and actual app screenshots. Requires Playwright.
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '..');
const asset = (file, type = 'png') => `data:image/${type};base64,${fs.readFileSync(path.join(root, 'docs', file)).toString('base64')}`;

(async () => {
  const browser = await chromium.launch({ headless: true, ...(process.env.CHROME_PATH ? { executablePath: process.env.CHROME_PATH } : {}) });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
    await page.setContent(`<!doctype html><html lang="en"><head><meta charset="utf-8"><title>VO2Cue share preview</title><style>
      *{box-sizing:border-box}body{margin:0;width:1200px;height:630px;overflow:hidden;background:#f5f5ed;color:#162323;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
      .copy{position:absolute;left:64px;top:46px;width:610px}.brand{display:flex;gap:12px;align-items:center;font-size:30px;font-weight:750;letter-spacing:-1px}.brand img{width:48px;height:48px;border-radius:11px}
      h1{margin:34px 0 20px;font-size:66px;font-weight:750;letter-spacing:-3px;line-height:1.06}h1 em{font-style:normal;color:#596e21}.intro{font-size:23px;line-height:1.45;max-width:550px;color:#566260}.footer{margin-top:28px;font-size:18px;font-weight:600}.small{margin-top:14px;font-size:16px;color:#566260}
      .orbit{position:absolute;right:22px;top:128px;width:435px;height:435px;border-radius:50%;background:#d8f06b}.phone{position:absolute;right:98px;top:48px;width:238px;border:7px solid #202a29;border-radius:38px;overflow:hidden;transform:rotate(7deg);box-shadow:0 22px 35px #17212026}.phone img{display:block;width:100%}.watch{position:absolute;right:282px;top:395px;width:130px;border:6px solid #414744;border-radius:31px;overflow:hidden;transform:rotate(-9deg);box-shadow:0 12px 24px #17212030}.watch img{display:block;width:100%}
    </style></head><body><div class="copy"><div class="brand"><img alt="" src="${asset('assets/app-icon-132.png')}">VO2Cue</div><h1>Your eyes-free<br><em>4×4 interval coach.</em></h1><p class="intro">Norwegian 4×4 and custom intervals.<br>Haptics, tones, and optional voice cues.</p><p class="footer">For iPhone &amp; Apple Watch</p><p class="small">No account. No ads. No tracking.</p></div><div class="orbit"></div><div class="phone"><img alt="VO2Cue live interval timer" src="${asset('demo/assets/timer.jpg', 'jpeg')}"></div><div class="watch"><img alt="VO2Cue on Apple Watch" src="${asset('demo/assets/watch.jpg', 'jpeg')}"></div></body></html>`);
    await page.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(im => im.decode())); });
    await page.screenshot({ path: path.join(root, 'docs/assets/social-preview.png') });
    console.log('Built docs/assets/social-preview.png (1200 × 630).');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
