import { HOST, SOCKS_PORT, COMMUNITY_LIST, load, save, pacScript, toHostServer, normDomain, routesViaVpn, t } from "./lib/core.js";

const BYPASS = ["localhost", "127.0.0.1", "::1", "<local>", "*.local", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"];
const BLOCK_ERRORS = /ERR_CONNECTION_RESET|ERR_CONNECTION_TIMED_OUT|ERR_TIMED_OUT|ERR_CONNECTION_CLOSED|ERR_SSL_PROTOCOL_ERROR|ERR_NAME_NOT_RESOLVED|ERR_CONNECTION_REFUSED|ERR_EMPTY_RESPONSE/;
let busy = null;

function native(msg) {
  return new Promise((resolve) => {
    chrome.runtime.sendNativeMessage(HOST, msg, (res) => {
      if (chrome.runtime.lastError) resolve({ ok: false, noHost: true, error: chrome.runtime.lastError.message });
      else resolve(res || { ok: false, error: "empty reply" });
    });
  });
}

async function applyProxy(s, up) {
  if (!s.enabled || (!up && !s.killSwitch)) {
    await chrome.proxy.settings.clear({ scope: "regular" });
  } else if (s.mode === "all") {
    await chrome.proxy.settings.set({ scope: "regular", value: { mode: "fixed_servers",
      rules: { singleProxy: { scheme: "socks5", host: "127.0.0.1", port: SOCKS_PORT }, bypassList: BYPASS } } });
  } else {
    await chrome.proxy.settings.set({ scope: "regular", value: { mode: "pac_script", pacScript: { data: pacScript(s) } } });
  }
  // WebRTC leak guard: no UDP outside the proxy while the VPN is on.
  try {
    if (s.enabled && s.webrtc) await chrome.privacy.network.webRTCIPHandlingPolicy.set({ value: "disable_non_proxied_udp" });
    else await chrome.privacy.network.webRTCIPHandlingPolicy.clear({});
  } catch {}
}

async function setIcon(on, s) {
  const v = on ? "on" : "off";
  await chrome.action.setIcon({ path: { 16: `icons/${v}16.png`, 32: `icons/${v}32.png` } });
  await chrome.action.setBadgeBackgroundColor({ color: on ? "#ff7a1a" : "#6b6b6b" });
  const badge = !s.enabled ? "" : !on ? "!" : s.mode === "smart" ? "" : s.mode === "all" ? "ALL" : "";
  await chrome.action.setBadgeText({ text: badge });
  await chrome.action.setTitle({ title: `Wokok VPN — ${on ? t(s).on : t(s).off}` });
}

const active = (s) => s.servers.find((x) => x._id === s.activeId) || s.servers[0];

async function pickFastest(s) {
  if (s.servers.length < 2) return active(s);
  const r = await native({ cmd: "ping", targets: s.servers.map((x) => ({ id: x._id, host: x.host, port: x.port })) });
  const best = (r.results || []).filter((x) => x.ms >= 0).sort((a, b) => a.ms - b.ms)[0];
  return s.servers.find((x) => x._id === best?.id) || active(s);
}

async function connect() {
  let s = await load();
  if (!s.servers.length) return { ok: false, error: "no server" };
  const order = [s.autoBest ? await pickFastest(s) : active(s), ...s.servers].filter((v, i, a) => v && a.indexOf(v) === i);
  let r;
  for (const srv of order) {
    r = await native({ cmd: "connect", server: toHostServer(srv), prefer: s.transport });
    if (r.ok && r.connected) {
      await save({ enabled: true, activeId: srv._id, since: Date.now(), lastMode: r.mode, lastError: null });
      break;
    }
    if (r.noHost || !s.autoBest) break;
  }
  s = await load();
  if (!(r.ok && r.connected)) await save({ lastError: r.error, ...(r.noHost ? { enabled: false } : {}) });
  await applyProxy(await load(), r.ok && r.connected);
  await setIcon(r.ok && r.connected, await load());
  return r;
}

async function disconnect() {
  await save({ enabled: false, since: null, lastError: null });
  const s = await load();
  await applyProxy(s, false);
  await setIcon(false, s);
  return native({ cmd: "disconnect" });
}

function serial(fn) {
  return async (...a) => { while (busy) await busy; busy = fn(...a); try { return await busy; } finally { busy = null; } };
}
const turnOn = serial(connect);
const turnOff = serial(disconnect);

// Keep proxy and tunnel in sync; reconnect if the tunnel dropped.
const heal = serial(async () => {
  const s = await load();
  if (!s.enabled) { await applyProxy(s, false); await setIcon(false, s); return; }
  const st = await native({ cmd: "status" });
  if (st.connected) { await applyProxy(s, true); await setIcon(true, s); return; }
  await applyProxy(s, false); // kill switch keeps the proxy set → traffic fails closed
  await setIcon(false, s);
  await connect();
});

async function refreshCommunity(force) {
  const s = await load();
  if (!s.community || (!force && Date.now() - s.communityAt < 12 * 3600e3)) return;
  try {
    const txt = await (await fetch(COMMUNITY_LIST, { cache: "no-store" })).text();
    const list = [...new Set(txt.split(/\r?\n/).map(normDomain).filter((d) => d && d.includes(".")))].slice(0, 20000);
    if (list.length) await save({ communityDomains: list, communityAt: Date.now() });
  } catch {}
}

function setupMenus() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({ id: "wokok-site", title: "Wokok: route this site via VPN / direct", contexts: ["page", "action"] });
  });
}

async function toggleSite(host) {
  const d = normDomain(host);
  if (!d) return;
  const s = await load();
  if (s.mode === "except") {
    const has = s.exceptSites.includes(d);
    await save({ exceptSites: has ? s.exceptSites.filter((x) => x !== d) : [...s.exceptSites, d] });
  } else {
    if (s.mode === "all") await save({ mode: "smart" });
    const via = routesViaVpn(await load(), d);
    await save({ smartSites: via ? s.smartSites.filter((x) => x !== d) : [...s.smartSites, d] });
  }
}

chrome.runtime.onInstalled.addListener(async (e) => {
  setupMenus();
  if (e.reason === "install") chrome.runtime.openOptionsPage();
  refreshCommunity(true);
  heal();
});
chrome.runtime.onStartup.addListener(() => { setupMenus(); heal(); refreshCommunity(); });
chrome.alarms.create("wokok-heal", { periodInMinutes: 1 });
chrome.alarms.create("wokok-lists", { periodInMinutes: 360 });
chrome.alarms.onAlarm.addListener((a) => (a.name === "wokok-heal" ? heal() : refreshCommunity()));

let lastProxyErr = 0;
chrome.proxy.onProxyError.addListener(() => { if (Date.now() - lastProxyErr > 5000) { lastProxyErr = Date.now(); heal(); } });

// Re-apply routing whenever settings change (mode, lists, presets…).
chrome.storage.onChanged.addListener(async (ch) => {
  const keys = ["mode", "presets", "smartSites", "exceptSites", "community", "communityDomains", "webrtc", "killSwitch"];
  if (!keys.some((k) => k in ch)) return;
  if ("community" in ch && ch.community.newValue) refreshCommunity(true);
  const s = await load();
  if (s.enabled) { await applyProxy(s, true); await setIcon(true, s); }
});

// Smart mode helper: a page failed in a way that smells like blocking → offer one-click routing.
chrome.webNavigation.onErrorOccurred.addListener(async (d) => {
  if (d.frameId !== 0 || !BLOCK_ERRORS.test(d.error)) return;
  const s = await load();
  let host; try { host = new URL(d.url).hostname; } catch { return; }
  if (!s.enabled || routesViaVpn(s, host)) return;
  await chrome.storage.session.set({ blocked: { host: normDomain(host), tabId: d.tabId, at: Date.now() } });
  chrome.action.setBadgeText({ tabId: d.tabId, text: "?" });
});

chrome.commands.onCommand.addListener(async (cmd, tab) => {
  if (cmd === "toggle-vpn") { const s = await load(); s.enabled ? turnOff() : turnOn(); }
  if (cmd === "toggle-site" && tab?.url) { await toggleSite(new URL(tab.url).hostname); chrome.tabs.reload(tab.id); }
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const url = info.pageUrl || tab?.url;
  if (url) { await toggleSite(new URL(url).hostname); if (tab?.id) chrome.tabs.reload(tab.id); }
});

chrome.runtime.onMessage.addListener((msg, _s, reply) => {
  (async () => {
    switch (msg.cmd) {
      case "on": return reply(await turnOn());
      case "off": return reply(await turnOff());
      case "toggleSite": await toggleSite(msg.host); return reply({ ok: true });
      case "info": return reply(await native({ cmd: "info" }));
      case "speed": return reply(await native({ cmd: "speed" }));
      case "ping": { const s = await load(); return reply(await native({ cmd: "ping", targets: s.servers.map((x) => ({ id: x._id, host: x.host, port: x.port })) })); }
      case "refreshLists": await refreshCommunity(true); return reply({ ok: true });
      case "switch": { await save({ activeId: msg.id }); const s = await load(); return reply(s.enabled ? await turnOn() : { ok: true }); }
      default: {
        const s = await load();
        const st = await native({ cmd: "status" });
        return reply({ ...st, enabled: s.enabled });
      }
    }
  })();
  return true;
});
