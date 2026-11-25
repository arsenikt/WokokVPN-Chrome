// Shared by the service worker, popup and options page.
export const HOST = "com.wokok.chrome";
export const SOCKS_PORT = 10808;
export const REPO = "https://github.com/arsenikt/WokokVPN-Chrome";
export const INSTALL_WIN = "irm https://raw.githubusercontent.com/arsenikt/WokokVPN-Chrome/main/client/install.ps1 | iex";
export const INSTALL_NIX = "curl -fsSL https://raw.githubusercontent.com/arsenikt/WokokVPN-Chrome/main/client/install.sh | bash";
export const INSTALL_SERVER = "curl -fsSL https://raw.githubusercontent.com/arsenikt/WokokVPN-Chrome/main/server/install.sh | sudo bash";
export const COMMUNITY_LIST = "https://community.antifilter.download/list/domains.lst";

export const PRESETS = {
  youtube:   { label: "YouTube",   domains: ["youtube.com", "youtu.be", "googlevideo.com", "ytimg.com", "ggpht.com", "youtube-nocookie.com", "youtubei.googleapis.com"] },
  instagram: { label: "Instagram", domains: ["instagram.com", "cdninstagram.com", "ig.me"] },
  facebook:  { label: "Facebook",  domains: ["facebook.com", "fb.com", "fbcdn.net", "messenger.com", "fbsbx.com"] },
  x:         { label: "X / Twitter", domains: ["x.com", "twitter.com", "twimg.com", "t.co"] },
  discord:   { label: "Discord",   domains: ["discord.com", "discord.gg", "discordapp.com", "discordapp.net", "discord.media", "discordcdn.com"] },
  ai:        { label: "ChatGPT · Claude · Gemini", domains: ["openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com", "claude.ai", "anthropic.com", "gemini.google.com", "aistudio.google.com", "perplexity.ai", "grok.com"] },
  linkedin:  { label: "LinkedIn",  domains: ["linkedin.com", "licdn.com"] },
  telegram:  { label: "Telegram Web", domains: ["telegram.org", "t.me", "web.telegram.org", "telegram.me"] },
  media:     { label: "Spotify · Netflix · SoundCloud", domains: ["spotify.com", "scdn.co", "netflix.com", "nflxvideo.net", "soundcloud.com", "sndcdn.com"] },
  dev:       { label: "Dev: Docker · npm · JetBrains", domains: ["docker.com", "docker.io", "jetbrains.com", "notion.so", "medium.com", "figma.com"] },
};

export const DEFAULTS = {
  enabled: false,
  servers: [],            // [{id,name,host,port,id,pbk,sid,sni,ssh}]
  activeId: null,
  mode: "smart",          // all | smart | except
  presets: ["youtube", "instagram", "x", "discord", "ai", "facebook", "linkedin"],
  smartSites: [],         // user-added sites routed via VPN
  exceptSites: ["sberbank.ru", "gosuslugi.ru", "tinkoff.ru", "tbank.ru", "vk.com", "ya.ru", "yandex.ru", "ozon.ru", "wildberries.ru", "mos.ru", "nalog.gov.ru", "avito.ru"],
  community: true,        // auto-updated antifilter community list in smart mode
  communityDomains: [],
  communityAt: 0,
  killSwitch: false,
  webrtc: true,
  autoBest: false,
  transport: "auto",      // auto | reality | ssh
  lang: "",               // "" = browser language
  since: null,
  lastMode: null,
  lastError: null,
  socksPort: SOCKS_PORT,  // actual local port reported by the helper (it skips busy ports)
};

export async function load() {
  const s = await chrome.storage.local.get(DEFAULTS);
  return s;
}
export const save = (patch) => chrome.storage.local.set(patch);

// ---------- links ----------
function b64urlDecode(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  return new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0)));
}

export function parseLink(text) {
  const t = (text || "").trim();
  if (t.startsWith("wokok://")) {
    const j = JSON.parse(b64urlDecode(t.slice(8).replace(/\/$/, "")));
    if (!j.host || !j.id || !j.pbk) throw new Error("bad wokok link");
    return { name: j.name || j.host, host: j.host, port: +j.port || 443, uuid: j.id, pbk: j.pbk, sid: j.sid || "", sni: j.sni, ssh: j.ssh || null };
  }
  if (t.startsWith("vless://")) {
    const u = new URL(t.replace(/^vless:/, "http:"));
    const q = u.searchParams;
    if (q.get("security") !== "reality") throw new Error("only VLESS + Reality links are supported");
    return { name: decodeURIComponent(u.hash.slice(1)) || u.hostname, host: u.hostname.replace(/^\[|\]$/g, ""), port: +u.port || 443,
      uuid: decodeURIComponent(u.username), pbk: q.get("pbk"), sid: q.get("sid") || "", sni: q.get("sni"), ssh: null };
  }
  throw new Error("paste a wokok:// or vless:// link");
}

export const toHostServer = (s) => ({ host: s.host, port: s.port, id: s.uuid, pbk: s.pbk, sid: s.sid, sni: s.sni, ssh: s.ssh });

// ---------- domains & PAC ----------
export function normDomain(input) {
  let d = (input || "").trim().toLowerCase();
  if (!d) return "";
  try { if (d.includes("/")) d = new URL(d.includes("://") ? d : "http://" + d).hostname; } catch { return ""; }
  return d.replace(/^\*\./, "").replace(/^www\./, "").replace(/\.$/, "");
}

export function smartSet(s) {
  const set = new Set(s.smartSites);
  for (const p of s.presets) for (const d of PRESETS[p]?.domains || []) set.add(d);
  if (s.community) for (const d of s.communityDomains) set.add(d);
  return set;
}

export function matches(set, host) {
  let d = (host || "").toLowerCase();
  while (d) {
    if (set.has(d)) return true;
    const i = d.indexOf(".");
    if (i < 0) return false;
    d = d.slice(i + 1);
  }
  return false;
}

export function routesViaVpn(s, host) {
  if (!host) return false;
  if (s.mode === "all") return true;
  if (s.mode === "except") return !matches(new Set(s.exceptSites), host);
  return matches(smartSet(s), host);
}

export function pacScript(s) {
  const P = `SOCKS5 127.0.0.1:${s.socksPort || SOCKS_PORT}`;
  const list = s.mode === "except" ? s.exceptSites : [...smartSet(s)];
  const hit = s.mode === "except" ? '"DIRECT"' : `"${P}"`;
  const miss = s.mode === "except" ? `"${P}"` : '"DIRECT"';
  return `var L=${JSON.stringify(Object.fromEntries(list.map((d) => [d, 1])))};
function FindProxyForURL(url,host){host=host.toLowerCase();
if(isPlainHostName(host)||/\\.(local|lan|home|internal)$/.test(host)||/^(127\\.|10\\.|192\\.168\\.|172\\.(1[6-9]|2\\d|3[01])\\.)/.test(host)||host==="localhost")return "DIRECT";
var d=host;while(d){if(L[d])return ${hit};var i=d.indexOf(".");if(i<0)break;d=d.slice(i+1);}return ${miss};}`;
}

// ---------- i18n ----------
export const STR = {
  en: {
    off: "Wok is cold", on: "Wok is on fire!", tapOn: "Tap the wok to light it up", tapOff: "Your traffic is stir-fried through your server",
    lighting: "Lighting the wok…", cooling: "Cooling down…", all: "All sites", smart: "Smart", except: "All except",
    viaVpn: "via VPN", direct: "direct", ip: "IP", ping: "Ping", speed: "Speed", uptime: "On fire", transport: "Transport",
    test: "test", testing: "…", noHost: "Install the helper on this computer (one command):", copy: "Copy", copied: "Copied!",
    welcome: "2. Paste the wokok:// link it printed:", step1: "1. On your VPS (over SSH) run:", srvHint: "Click to copy. Lost the link? Run on the server: sudo wokok link", add: "Add server", howTo: "How do I get a server?", settings: "Settings",
    blocked: "looks blocked. Route it via VPN?", yes: "Yes", killOn: "Kill switch: tunnel dropped, traffic blocked", fastest: "Fastest",
    reconnecting: "Tunnel dropped, reconnecting…", wok: "Buy the author a wok",
  },
  ru: {
    off: "Вок остыл", on: "Вок горит!", tapOn: "Нажми на вок, чтобы разжечь", tapOff: "Трафик жарится через ваш сервер",
    lighting: "Разжигаем вок…", cooling: "Гасим огонь…", all: "Все сайты", smart: "Умный", except: "Все, кроме",
    viaVpn: "через VPN", direct: "напрямую", ip: "IP", ping: "Пинг", speed: "Скорость", uptime: "На огне", transport: "Протокол",
    test: "тест", testing: "…", noHost: "Установите помощник на этот компьютер (одна команда):", copy: "Копировать", copied: "Скопировано!",
    welcome: "2. Вставьте ссылку wokok://, которую он выдал:", step1: "1. На вашем VPS (по SSH) выполните:", srvHint: "Нажмите, чтобы скопировать. Потеряли ссылку? На сервере: sudo wokok link", add: "Добавить сервер", howTo: "Где взять сервер?", settings: "Настройки",
    blocked: "похоже, заблокирован. Открыть через VPN?", yes: "Да", killOn: "Kill switch: туннель упал, трафик заблокирован", fastest: "Самый быстрый",
    reconnecting: "Туннель упал, переподключаемся…", wok: "На покупку вока",
  },
};
export function lang(s) { return s.lang || (chrome.i18n.getUILanguage().startsWith("ru") ? "ru" : "en"); }
export function t(s) { return STR[lang(s)]; }

export async function addServer(text) {
  const p = parseLink(text);
  const s = await load();
  const existing = s.servers.find((x) => x.host === p.host && x.port === p.port && x.uuid === p.uuid);
  if (existing) { await save({ activeId: existing._id }); return existing; }
  const srv = { _id: crypto.randomUUID(), ...p };
  await save({ servers: [...s.servers, srv], activeId: s.activeId || srv._id });
  return srv;
}

export function fmtTime(ms) {
  const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), x = s % 60;
  return (h ? h + ":" : "") + String(m).padStart(2, "0") + ":" + String(x).padStart(2, "0");
}

export const flag = (cc) => (cc && cc.length === 2 ? String.fromCodePoint(...[...cc.toUpperCase()].map((c) => 127397 + c.charCodeAt(0))) : "");
