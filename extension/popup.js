import { load, save, t, routesViaVpn, normDomain, addServer, fmtTime, flag, REPO, INSTALL_WIN, INSTALL_NIX } from "./lib/core.js";

const $ = (id) => document.getElementById(id);
const body = document.body;
const send = (cmd, extra) => new Promise((r) => chrome.runtime.sendMessage({ cmd, ...extra }, r));
let S, L, st = {}, tick, host = "";

function texts() {
  L = t(S);
  $("modes").querySelectorAll("button").forEach((b) => (b.textContent = L[b.dataset.mode]));
  $("lIp").textContent = L.ip; $("lPing").textContent = L.ping; $("lSpeed").textContent = L.speed; $("lUp").textContent = L.uptime;
  $("speedHint").textContent = L.test; $("wTitle").textContent = L.welcome; $("addBtn").textContent = L.add;
  $("howTo").textContent = L.howTo; $("howTo").href = REPO + "#-quick-start"; $("repo").href = REPO;
  $("nhText").textContent = L.noHost; $("copyCmd").textContent = L.copy; $("bYes").textContent = L.yes;
  $("opts").title = L.settings; $("wok").title = L.wok;
}

function renderServers() {
  const sel = $("server");
  sel.innerHTML = "";
  for (const x of S.servers) sel.add(new Option(x.name, x._id, false, x._id === S.activeId));
  sel.hidden = !S.servers.length;
}

function render(err) {
  const on = S.enabled && st.connected;
  body.classList.toggle("on", on);
  body.classList.toggle("off", !on);
  body.classList.toggle("err", !!err);
  $("title").textContent = on ? L.on : L.off;
  $("sub").textContent = err || (S.enabled && !st.connected ? (S.killSwitch ? L.killOn : L.reconnecting) : on ? L.tapOff : L.tapOn);
  $("modes").querySelectorAll("button").forEach((b) => b.classList.toggle("on", b.dataset.mode === S.mode));
  $("mode").textContent = on ? (st.mode === "ssh" ? "SSH fallback" : "VLESS Reality") : "—";
  const via = routesViaVpn(S, host);
  $("site").classList.toggle("via", via);
  $("siteHost").textContent = host || "—";
  $("siteBtn").textContent = via ? L.viaVpn : L.direct;
  $("siteBtn").disabled = !host;
  clearInterval(tick);
  const upd = () => ($("timer").textContent = on && S.since ? fmtTime(Date.now() - S.since) : "—");
  upd();
  if (on) tick = setInterval(upd, 1000);
  if (!on) { $("ip").textContent = "—"; $("geo").textContent = ""; $("ping").textContent = "—"; }
}

async function info() {
  if (!(S.enabled && st.connected)) return;
  const r = await send("info");
  if (!r?.ok) return;
  $("ip").textContent = r.ip || "—";
  $("geo").textContent = [flag(r.cc), r.city || r.country].filter(Boolean).join(" ");
  $("ping").textContent = r.ping + " ms";
}

function screen() {
  const noHost = st.noHost;
  $("nohost").hidden = !noHost;
  $("welcome").hidden = noHost || !!S.servers.length;
  $("main").hidden = noHost || !S.servers.length;
}

async function refresh() {
  S = await load();
  st = await send("status");
  texts(); renderServers(); screen();
  render(st.ok === false && !st.noHost ? st.error : S.enabled ? null : S.lastError);
  const { blocked } = await chrome.storage.session.get("blocked");
  const show = blocked && host && normDomain(host) === blocked.host && !routesViaVpn(S, host);
  $("blocked").hidden = !show;
  if (show) $("bText").textContent = `${blocked.host} ${L.blocked}`;
  info();
}

$("toggle").addEventListener("click", async () => {
  $("toggle").disabled = true;
  body.classList.add("busy");
  $("sub").textContent = S.enabled ? L.cooling : L.lighting;
  const r = await send(S.enabled ? "off" : "on");
  body.classList.remove("busy");
  $("toggle").disabled = false;
  await refresh();
  if (r && r.ok === false) render(r.error);
});

$("modes").addEventListener("click", async (e) => {
  const m = e.target.dataset.mode;
  if (!m) return;
  await save({ mode: m });
  S.mode = m;
  render();
});

async function routeSite() {
  await send("toggleSite", { host });
  await chrome.storage.session.remove("blocked");
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab) chrome.tabs.reload(tab.id);
  await refresh();
}
$("siteBtn").addEventListener("click", routeSite);
$("bYes").addEventListener("click", routeSite);

$("speedTile").addEventListener("click", async () => {
  if (!(S.enabled && st.connected)) return;
  $("speed").textContent = L.testing;
  const r = await send("speed");
  $("speed").textContent = r?.ok ? r.mbps + " Mbit/s" : "—";
});

$("server").addEventListener("change", async (e) => {
  body.classList.add("busy");
  await send("switch", { id: e.target.value });
  body.classList.remove("busy");
  refresh();
});

$("opts").addEventListener("click", () => chrome.runtime.openOptionsPage());
$("wok").addEventListener("click", (e) => { e.preventDefault(); chrome.tabs.create({ url: chrome.runtime.getURL("options.html#wok") }); });

$("addBtn").addEventListener("click", async () => {
  try { await addServer($("link").value); $("wErr").textContent = ""; await refresh(); }
  catch (e) { $("wErr").textContent = e.message; }
});

let os = navigator.userAgent.includes("Windows") ? "win" : "nix";
function showCmd() {
  $("cmd").textContent = os === "win" ? INSTALL_WIN : INSTALL_NIX;
  document.querySelectorAll(".os button").forEach((b) => b.classList.toggle("on", b.dataset.os === os));
}
document.querySelector(".os").addEventListener("click", (e) => { if (e.target.dataset.os) { os = e.target.dataset.os; showCmd(); } });
$("copyCmd").addEventListener("click", async () => {
  await navigator.clipboard.writeText($("cmd").textContent);
  $("copyCmd").textContent = L.copied;
  setTimeout(() => ($("copyCmd").textContent = L.copy), 1500);
});
showCmd();

(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  try { const u = new URL(tab.url); if (/^https?:$/.test(u.protocol)) host = normDomain(u.hostname); } catch {}
  await refresh();
})();
