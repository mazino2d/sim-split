// Loads a served web build in headless Chromium, waits for the first screen
// and fails on uncaught errors or failed requests. Writes a screenshot.
// Usage: node smoke_web.cjs <url> <screenshot.png>
const { chromium } = require('playwright');

(async () => {
  const [url, shot] = process.argv.slice(2);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 412, height: 900 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(`console: ${m.text()}`);
  });
  page.on('requestfailed', (r) =>
    errors.push(`request failed: ${r.url()} (${r.failure()?.errorText})`));
  page.on('response', (r) => {
    if (r.status() >= 400) errors.push(`HTTP ${r.status()}: ${r.url()}`);
  });

  await page.goto(url, { waitUntil: 'load', timeout: 60000 });
  // Flutter renders into <flutter-view>; give the first frame and the
  // Drift worker time to start.
  await page.waitForSelector('flutter-view', { timeout: 30000 });
  await page.waitForTimeout(8000);
  await page.screenshot({ path: shot });
  await browser.close();

  if (errors.length) {
    console.error(errors.join('\n'));
    process.exit(1);
  }
  console.log(`OK: ${url} loaded without errors; screenshot at ${shot}`);
})();
