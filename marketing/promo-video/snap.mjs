// Usage: node snap.mjs out_dir t1 t2 ...   (renders stills for review)
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
import http from "http"; import fs from "fs"; import path from "path";
const root = path.dirname(new URL(import.meta.url).pathname);
const types = { ".html": "text/html", ".json": "application/json", ".png": "image/png", ".woff2": "font/woff2", ".css": "text/css" };
const server = http.createServer((q, s) => { const p = path.join(root, decodeURIComponent(q.url.split("?")[0])); fs.readFile(p, (e, b) => { if (e) { s.writeHead(404); s.end(); return; } s.writeHead(200, { "content-type": types[path.extname(p)] || "application/octet-stream" }); s.end(b); }); }).listen(0);
const port = server.address().port;
const [out, ...times] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
page.on("console", m => console.log("console:", m.text())); page.on("pageerror", e => console.log("pageerror:", e.message));
await page.goto(`http://127.0.0.1:${port}/index.html`);
await page.waitForFunction(() => window.READY === true, null, { timeout: 30000 });
for (const t of times) {
  await page.evaluate(t => window.renderAt(t), parseFloat(t));
  await page.locator("canvas").screenshot({ path: `${out}/t${String(t).padStart(5, "0")}.png` });
}
await browser.close(); server.close();
