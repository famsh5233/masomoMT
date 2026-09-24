// Drives the Flutter web build in Chromium like a learner would, against a live
// JARVIS server, and saves a screenshot at each step. Run via e2e.sh (E2E_UI=1).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const WEB = process.env.WEB_URL || 'http://127.0.0.1:8080';
const OUT = process.env.E2E_OUT || 'shots';
// Behind an outbound proxy (fonts load from Google), keep local servers direct.
const proxyArgs = process.env.HTTPS_PROXY
  ? ['--proxy-server=' + process.env.HTTPS_PROXY, '--proxy-bypass-list=127.0.0.1;localhost']
  : [];

let step = 0;
let current; // the open page, for a screenshot on failure
async function shot(page, name) {
  step += 1;
  const file = path.join(OUT, `${String(step).padStart(2, '0')}-${name}.png`);
  await page.waitForTimeout(400);
  await page.screenshot({ path: file });
  console.log('screenshot', file);
}

async function button(page, name) {
  const b = page.getByRole('button', { name, exact: false })
    .or(page.getByRole('tab', { name, exact: false }))
    .first();
  await b.waitFor({ timeout: 15000 });
  await b.click();
}

// Type like a person (focus, then keystrokes) and confirm Flutter received the text.
async function typeInto(page, label, text) {
  const box = page.getByRole('textbox', { name: label, exact: false }).first();
  await box.waitFor({ timeout: 15000 });
  for (let attempt = 0; attempt < 3; attempt++) {
    await box.click();
    await page.waitForTimeout(300);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(text, { delay: 15 });
    await page.waitForTimeout(200);
    if ((await box.inputValue()) === text) return;
  }
  throw new Error(`could not type into "${label}"`);
}

// Flutter exposes plain text through accessibility labels, not page text, so check both.
async function see(page, text, timeout = 15000) {
  await page.waitForFunction((t) => {
    const host = document.querySelector('flt-semantics-host');
    if (!host) return false;
    if (host.textContent.includes(t)) return true;
    return [...host.querySelectorAll('[aria-label]')].some((n) => n.getAttribute('aria-label').includes(t));
  }, text, { timeout });
}

async function tapText(page, text) {
  const node = page.locator(`flt-semantics[aria-label*="${text}"], flt-semantics:text("${text}")`).first();
  await node.waitFor({ timeout: 15000 });
  await node.click();
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined, args: proxyArgs });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  current = page;
  const errors = [];
  const external = new Set();
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => {
    if (m.type() === 'error' && !/ERR_CERT_AUTHORITY_INVALID/.test(m.text())) errors.push(m.text());
  });
  // Requests to our own servers must succeed. Outside hosts (Google Fonts fallbacks, the
  // sample video CDN) can fail behind a TLS-inspecting proxy; list them but don't fail.
  page.on('requestfailed', (r) => {
    const url = r.url();
    if (url.startsWith('http://127.0.0.1')) errors.push(`request failed: ${url} ${r.failure()?.errorText}`);
    else external.add(new URL(url).host);
  });

  await page.goto(WEB);
  // Flutter draws on a canvas; turning on its accessibility tree gives us real buttons and text boxes.
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());

  await see(page, 'Ongea Kiingereza kwa kujiamini', 30000);
  await shot(page, 'sign-in');

  const phone = '07' + String(Date.now() % 10000000).padStart(7, '0') + '1';
  await typeInto(page, 'Namba ya simu', phone);
  await button(page, 'Tuma namba ya uthibitisho');
  await see(page, 'Tumetuma namba');
  await shot(page, 'code');
  await button(page, 'Thibitisha');

  await see(page, 'Tukufahamu');
  await typeInto(page, 'Jina lako', 'Neema');
  await shot(page, 'profile');
  await button(page, 'Endelea');

  await see(page, 'Mwalimu');
  await shot(page, 'tutor');
  await typeInto(page, 'Au andika kwa Kiingereza', 'She go to the market every day');
  await button(page, 'Tuma');
  await see(page, 'She goes to the market every day');
  await shot(page, 'tutor-feedback');

  await button(page, 'Masomo');
  await see(page, 'Jitambulishe kwa Kiingereza');
  await shot(page, 'lessons');
  await tapText(page, 'Jitambulishe kwa Kiingereza');
  await see(page, 'Jitambulishe kwa Kiingereza');
  await shot(page, 'lesson-week-1');
  await button(page, 'Back');

  await button(page, 'Akaunti');
  await see(page, 'Mpango wa bure');
  await shot(page, 'account-free');
  await button(page, 'Jiunge na Pro');
  await see(page, 'Masomo Pro');
  await shot(page, 'paywall');
  await button(page, 'Lipa TSh 7,000');
  await see(page, 'Angalia simu yako');
  await shot(page, 'pay-pin-prompt');
  await see(page, 'Hongera! Pro imewashwa.', 30000);
  await shot(page, 'pay-success');
  await button(page, 'Sawa');
  await see(page, 'Pro hadi');
  await shot(page, 'account-pro');

  await browser.close();
  if (external.size) console.log('outside hosts that failed (not app errors):', [...external].join(', '));
  const real = errors.filter((e) => !/favicon|manifest/i.test(e));
  if (real.length) {
    console.error('Browser errors:\n' + real.join('\n'));
    process.exit(1);
  }
  console.log('UI journey passed');
})().catch(async (e) => {
  console.error(e);
  if (current) await current.screenshot({ path: path.join(OUT, 'failure.png') }).catch(() => {});
  process.exit(1);
});
