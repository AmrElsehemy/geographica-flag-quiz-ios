// Puts each raw screenshot on a branded background with its caption, at the App Store size.
//   node Scripts/frame-screenshots.mjs <raw-dir> <out-dir>
// Captions and size live in Design/screenshots.json. Needs Playwright with Chromium.
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');
const root = resolve(new URL('..', import.meta.url).pathname);
const [rawDir, outDir] = process.argv.slice(2).map((p) => resolve(p));
if (!rawDir || !outDir) {
  console.error('usage: node Scripts/frame-screenshots.mjs <raw-dir> <out-dir>');
  process.exit(2);
}
const config = JSON.parse(readFileSync(join(root, 'Design/screenshots.json'), 'utf8'));
mkdirSync(outDir, { recursive: true });

const { width, height } = config;
const shotWidth = Math.round(width * 0.83);          // the app screenshot, scaled
const shotTop = Math.round(height * 0.155);          // leaves room for the caption above it
const radius = Math.round(width * 0.052);

const html = (caption, dataUri) => `<!doctype html><html><head><style>
  html, body { margin: 0; width: ${width}px; height: ${height}px; overflow: hidden; }
  body { position: relative; font-family: -apple-system, "SF Pro Display", "Helvetica Neue", Arial, sans-serif;
         background: linear-gradient(170deg, #1B4D9B 0%, #0E5C86 55%, #0A6E78 100%); }
  .caption { position: absolute; left: 0; right: 0; top: ${Math.round(height * 0.035)}px; text-align: center;
             color: #fff; font-weight: 800; font-size: ${Math.round(width * 0.082)}px; line-height: 1.08;
             padding: 0 ${Math.round(width * 0.07)}px; letter-spacing: -0.01em; text-wrap: balance; }
  .shot { position: absolute; left: ${Math.round((width - shotWidth) / 2)}px; top: ${shotTop}px;
          width: ${shotWidth}px; border-radius: ${radius}px; box-shadow: 0 40px 90px rgba(0,0,0,.45); }
</style></head><body>
  <div class="caption">${caption.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</div>
  <img class="shot" src="${dataUri}">
</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
let made = 0;
for (const { file, caption } of config.shots) {
  const raw = join(rawDir, `${file}.png`);
  if (!existsSync(raw)) {
    console.error(`missing ${raw}`);
    process.exitCode = 1;
    continue;
  }
  const dataUri = 'data:image/png;base64,' + readFileSync(raw).toString('base64');
  await page.setContent(html(caption, dataUri));
  await page.locator('img.shot').evaluate((img) => img.decode());
  await page.screenshot({ path: join(outDir, `${file}.png`), clip: { x: 0, y: 0, width, height } });
  made += 1;
}
await browser.close();
console.log(`framed ${made} screenshots into ${outDir}`);
