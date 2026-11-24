import { load, save, lang, PRESETS, normDomain, addServer, INSTALL_WIN, INSTALL_NIX, HOST } from "./lib/core.js";

const $ = (id) => document.getElementById(id);
const send = (cmd, extra) => new Promise((r) => chrome.runtime.sendMessage({ cmd, ...extra }, r));
const T = {
  en: { tag: "Your own Reality VPN for Chrome · stir-fry your traffic", servers: "Servers", add: "Add", autoBest: "Auto-pick the fastest server",
    transport: "Transport", pingAll: "Ping all", serverHint: "Run the server installer, then paste the wokok:// link it prints. Give friends their own key with: wokok add NAME",
    routing: "Routing", all: "All sites", smart: "Smart", except: "All except",
    hint_all: "Every site goes through the VPN (local networks stay direct).",
    hint_smart: "Only the sites below go through the VPN. Banks, government services and everything else stay direct and fast.",
    hint_except: "Everything goes through the VPN except the sites below.",
    presets: "Presets", community: "Auto-updated blocklist (antifilter community)", refresh: "refresh", mySites: "My VPN sites (one per line)",
    exceptSites: "Always direct (one per line)", protection: "Leak protection", kill: "Kill switch: if the tunnel drops, block traffic instead of leaking it",
    webrtc: "Block WebRTC leaks (your real IP in video calls / WebRTC tests)",
    dnsHint: "DNS is resolved on your server (SOCKS5 remote DNS), so your provider can't see which sites you open.",
    extras: "Extras", keys: "Alt+Shift+V: VPN on/off · Alt+Shift+S: current site via VPN/direct · Alt+Shift+W: open popup. Right-click any page → Wokok.",
    editKeys: "Edit hotkeys", export: "Export backup", import: "Import backup", hostTitle: "Helper is not installed on this computer",
    hostText: "Wokok needs a tiny helper to run the tunnel. Run one command and reload this page:", del: "Delete", use: "Use",
    sites: "sites", imported: "Imported ✔" },
  ru: { tag: "Свой Reality VPN для Chrome · жарь трафик через свой вок", servers: "Серверы", add: "Добавить", autoBest: "Автоматически выбирать самый быстрый",
    transport: "Протокол", pingAll: "Пинг всех", serverHint: "Запустите установщик на сервере и вставьте ссылку wokok://, которую он выдаст. Ключ для друга: wokok add ИМЯ",
    routing: "Маршрутизация", all: "Все сайты", smart: "Умный", except: "Все, кроме",
    hint_all: "Все сайты идут через VPN (локальные сети напрямую).",
    hint_smart: "Через VPN идут только сайты ниже. Банки, Госуслуги и всё остальное работают напрямую и быстро.",
    hint_except: "Всё идёт через VPN, кроме сайтов ниже.",
    presets: "Пресеты", community: "Автообновляемый список блокировок (antifilter community)", refresh: "обновить", mySites: "Мои сайты через VPN (по одному в строке)",
    exceptSites: "Всегда напрямую (по одному в строке)", protection: "Защита от утечек", kill: "Kill switch: если туннель упал, блокировать трафик, а не пускать напрямую",
    webrtc: "Блокировать утечки WebRTC (реальный IP в видеозвонках и тестах WebRTC)",
    dnsHint: "DNS резолвится на вашем сервере (удалённый DNS через SOCKS5), поэтому провайдер не видит, какие сайты вы открываете.",
    extras: "Дополнительно", keys: "Alt+Shift+V: вкл/выкл VPN · Alt+Shift+S: текущий сайт через VPN/напрямую · Alt+Shift+W: открыть попап. Правый клик по странице → Wokok.",
    editKeys: "Горячие клавиши", export: "Экспорт бэкапа", import: "Импорт бэкапа", hostTitle: "Помощник не установлен на этом компьютере",
    hostText: "Wokok нужен маленький помощник для туннеля. Выполните одну команду и обновите страницу:", del: "Удалить", use: "Выбрать",
    sites: "сайтов", imported: "Импортировано ✔" },
};
let S, L;
const lines = (v) => [...new Set(v.split(/[\s,]+/).map(normDomain).filter(Boolean))];

function texts() {
  L = T[lang(S)];
  document.documentElement.lang = lang(S);
  document.querySelectorAll("[data-t]").forEach((e) => (e.textContent = L[e.dataset.t]));
  document.querySelectorAll("#mode button").forEach((b) => (b.textContent = L[b.dataset.mode]));
}

function renderServers(pings = {}) {
  const ul = $("servers");
  ul.innerHTML = "";
  for (const x of S.servers) {
    const li = document.createElement("li");
    li.className = x._id === S.activeId ? "active" : "";
    li.innerHTML = `<b></b><small></small><span class="tag">Reality${x.ssh ? " + SSH" : ""}</span><span class="ms"></span><button class="use"></button><button class="del"></button>`;
    li.querySelector("b").textContent = x.name;
    li.querySelector("small").textContent = `${x.host}:${x.port}`;
    const p = pings[x._id];
    li.querySelector(".ms").textContent = p == null ? "" : p < 0 ? "✖" : p + " ms";
    li.querySelector(".use").textContent = L.use;
    li.querySelector(".del").textContent = L.del;
    li.querySelector(".use").onclick = async () => { await send("switch", { id: x._id }); init(); };
    li.querySelector(".del").onclick = async () => {
      const servers = S.servers.filter((y) => y._id !== x._id);
      await save({ servers, activeId: S.activeId === x._id ? servers[0]?._id || null : S.activeId });
      init();
    };
    ul.append(li);
  }
}

function render() {
  texts();
  renderServers();
  $("lang").value = S.lang;
  $("autoBest").checked = S.autoBest; $("transport").value = S.transport;
  $("killSwitch").checked = S.killSwitch; $("webrtc").checked = S.webrtc; $("community").checked = S.community;
  document.querySelectorAll("#mode button").forEach((b) => b.classList.toggle("on", b.dataset.mode === S.mode));
  $("modeHint").textContent = L["hint_" + S.mode];
  $("smartBox").hidden = S.mode !== "smart";
  $("exceptBox").hidden = S.mode !== "except";
  $("presets").innerHTML = "";
  for (const [k, p] of Object.entries(PRESETS)) {
    const l = document.createElement("label");
    l.innerHTML = `<input type="checkbox"> <span></span>`;
    l.querySelector("span").textContent = p.label;
    const cb = l.querySelector("input");
    cb.checked = S.presets.includes(k);
    cb.onchange = () => save({ presets: cb.checked ? [...S.presets, k] : S.presets.filter((x) => x !== k) }).then(init);
    $("presets").append(l);
  }
  $("cCount").textContent = S.communityDomains.length ? `· ${S.communityDomains.length.toLocaleString()} ${L.sites}` : "";
  $("smartSites").value = S.smartSites.join("\n");
  $("exceptSites").value = S.exceptSites.join("\n");
  $("ver").textContent = "v" + chrome.runtime.getManifest().version;
}

async function init() { S = await load(); render(); }

$("add").onclick = async () => {
  try { await addServer($("link").value); $("link").value = ""; $("addErr").textContent = ""; init(); }
  catch (e) { $("addErr").textContent = e.message; }
};
$("link").addEventListener("keydown", (e) => e.key === "Enter" && $("add").click());
$("pingAll").onclick = async () => {
  const r = await send("ping");
  renderServers(Object.fromEntries((r.results || []).map((x) => [x.id, x.ms])));
};
$("mode").onclick = (e) => e.target.dataset.mode && save({ mode: e.target.dataset.mode }).then(init);
for (const id of ["autoBest", "killSwitch", "webrtc", "community"]) $(id).onchange = (e) => save({ [id]: e.target.checked }).then(init);
$("transport").onchange = (e) => save({ transport: e.target.value });
$("lang").onchange = (e) => save({ lang: e.target.value }).then(init);
$("smartSites").onchange = (e) => save({ smartSites: lines(e.target.value) }).then(init);
$("exceptSites").onchange = (e) => save({ exceptSites: lines(e.target.value) }).then(init);
$("cRefresh").onclick = async (e) => { e.preventDefault(); await send("refreshLists"); init(); };
$("shortcuts").onclick = () => chrome.tabs.create({ url: "chrome://extensions/shortcuts" });

$("export").onclick = async () => {
  const { communityDomains, ...rest } = await load();
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([JSON.stringify(rest, null, 2)], { type: "application/json" }));
  a.download = "wokok-backup.json";
  a.click();
};
$("import").onchange = async (e) => {
  const f = e.target.files[0];
  if (!f) return;
  const data = JSON.parse(await f.text());
  delete data.enabled; delete data.since;
  await save(data);
  init();
  alert(L.imported);
};

for (const [id, cmd] of [["cmdWin", INSTALL_WIN], ["cmdNix", INSTALL_NIX]]) {
  $(id).textContent = cmd;
  $(id).onclick = () => navigator.clipboard.writeText(cmd);
}
chrome.runtime.sendNativeMessage(HOST, { cmd: "status" }, () => { $("hostWarn").hidden = !chrome.runtime.lastError; });

init();
