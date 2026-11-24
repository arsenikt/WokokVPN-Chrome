// Tiny local receiver for generated artwork → assets/gemini/.
//   node tools/receiver.js
// POST /save?name=x.png   (raw bytes or form field "data" with a data: URL)
// GET  /grab              page that accepts window.postMessage({name, data}) from another tab
//                         (for sites whose CSP blocks fetch/forms to localhost)
const http = require("http"), fs = require("fs"), path = require("path");
const OUT = path.join(__dirname, "..", "assets", "gemini");
fs.mkdirSync(OUT, { recursive: true });

const GRAB = `<!doctype html><title>wokok receiver</title><body style="background:#111;color:#fc8;font:14px monospace">ready
<script>
// Hand-off via window.name: set it on the source page, then navigate this tab to /grab.
(async () => {
  try {
    const { name, data } = JSON.parse(window.name || "{}");
    window.name = "";
    if (!name) return;
    const b = await (await fetch(data)).blob();
    const r = await fetch("/save?name=" + encodeURIComponent(name), { method: "POST", body: b });
    document.title = "saved " + name + " " + r.status;
    document.body.append(" saved " + name);
  } catch (e) { document.body.append(" " + e); }
})();
addEventListener("message", async (e) => {
  const { name, data } = e.data || {};
  if (!name || !data) return;
  const b = await (await fetch(data)).blob();
  const r = await fetch("/save?name=" + encodeURIComponent(name), { method: "POST", body: b });
  document.body.append(" " + name + ":" + r.status);
  e.source && e.source.postMessage({ saved: name }, "*");
});
</script>`;

http.createServer((req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "*");
  res.setHeader("Access-Control-Allow-Private-Network", "true");
  if (req.method === "OPTIONS") return res.end();
  const u = new URL(req.url, "http://x");
  if (req.method === "GET" && u.pathname === "/grab") { res.setHeader("Content-Type", "text/html"); return res.end(GRAB); }
  if (req.method !== "POST" || u.pathname !== "/save") { res.statusCode = 404; return res.end(); }
  const name = path.basename(u.searchParams.get("name") || "image.png").replace(/[^\w.-]/g, "_");
  const chunks = [];
  req.on("data", (c) => chunks.push(c));
  req.on("end", () => {
    let buf = Buffer.concat(chunks);
    if ((req.headers["content-type"] || "").includes("urlencoded")) {
      const f = new URLSearchParams(buf.toString());
      buf = Buffer.from((f.get("data") || "").replace(/^data:[^,]*,/, ""), "base64");
    }
    fs.writeFileSync(path.join(OUT, name), buf);
    console.log("saved", name, buf.length);
    res.end(JSON.stringify({ ok: true, name, bytes: buf.length }));
  });
}).listen(8765, "127.0.0.1", () => console.log("receiver on http://127.0.0.1:8765 ->", OUT));
