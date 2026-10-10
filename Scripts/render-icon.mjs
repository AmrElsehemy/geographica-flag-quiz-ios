// Renders Design/app-icon.svg to the 1024x1024 app icon (opaque PNG, as the App Store requires).
//   NODE_PATH=$(npm root -g) node Scripts/render-icon.mjs
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');
const root = resolve(new URL('..', import.meta.url).pathname);
const svg = readFileSync(join(root, 'Design/app-icon.svg'), 'utf8');
const out = join(root, 'App/Assets.xcassets/AppIcon.appiconset/icon-1024.png');

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
await page.setContent(`<html><body style="margin:0">${svg}</body></html>`);
await page.screenshot({ path: out, clip: { x: 0, y: 0, width: 1024, height: 1024 } });
await browser.close();
console.log('wrote', out);
