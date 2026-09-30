// Renders every frame of index.html and pipes PNGs into ffmpeg with the soundtrack.
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
import http from "http"; import fs from "fs"; import path from "path"; import { spawn, execSync } from "child_process";
const root = path.dirname(new URL(import.meta.url).pathname);
const FF = execSync(`python3 -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"`).toString().trim();
const FPS = 30, DURATION = 26, OUT = process.argv[2] || "stringmap-promo.mp4";
const types = { ".html": "text/html", ".json": "application/json", ".png": "image/png", ".woff2": "font/woff2", ".css": "text/css" };
const server = http.createServer((q, s) => { const p = path.join(root, decodeURIComponent(q.url.split("?")[0])); fs.readFile(p, (e, b) => { if (e) { s.writeHead(404); s.end(); return; } s.writeHead(200, { "content-type": types[path.extname(p)] || "application/octet-stream" }); s.end(b); }); }).listen(0);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
page.on("pageerror", e => console.log("pageerror:", e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
await page.waitForFunction(() => window.READY === true, null, { timeout: 30000 });
const ff = spawn(FF, ["-y", "-f", "image2pipe", "-framerate", String(FPS), "-i", "-",
  "-i", path.join(root, "soundtrack.wav"),
  "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-profile:v", "high", "-movflags", "+faststart",
  "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-shortest", OUT], { stdio: ["pipe", "ignore", "pipe"] });
let ffErr = ""; ff.stderr.on("data", d => { ffErr = (ffErr + d).slice(-4000); });
const total = FPS * DURATION, t0 = Date.now();
const canvas = page.locator("canvas");
for (let f = 0; f < total; f++) {
  await page.evaluate(t => window.renderAt(t), f / FPS);
  const buf = await canvas.screenshot({ type: "png" });
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once("drain", r));
  if (f % 150 === 0) console.log(`frame ${f}/${total}  ${((Date.now() - t0) / 1000).toFixed(0)}s`);
}
ff.stdin.end();
await new Promise(r => ff.on("close", code => { console.log("ffmpeg exit", code); if (code) console.log(ffErr); r(); }));
await browser.close(); server.close();
console.log("done in", ((Date.now() - t0) / 1000).toFixed(0), "s");
