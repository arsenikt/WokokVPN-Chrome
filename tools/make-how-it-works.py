# Generates docs/img/how-it-works{,.ru}.svg.  Usage: python tools/make-how-it-works.py
import pathlib
root = pathlib.Path(__file__).resolve().parent.parent
T = {
 "en": dict(title="How it works", c=[
   ("🌐", "Chrome", "Wokok extension", ["Proxy / PAC script", "Smart · Except · All", "Native Messaging"]),
   ("⚙️", "Helper", "on your PC", ["xray · local SOCKS5", "127.0.0.1:10808", "checks generate_204"]),
   ("🔥", "Your server", ":443", ["Xray Reality", "own UUID per user", "one-command setup"]),
   ("🌍", "Internet", "any site", ["YouTube, ChatGPT…", "your server's IP", "no leaks"])],
   tun="VLESS + XTLS-Vision + Reality", dpi="DPI sees: TLS → www.microsoft.com",
   fb="Fallback", fbt="ssh -D 10808 → wokok@server  ·  port-forwarding only, no shell, no password",
   local="your computer", remote="the cloud"),
 "ru": dict(title="Как это работает", c=[
   ("🌐", "Chrome", "расширение Wokok", ["Прокси / PAC-скрипт", "Умный · Кроме · Всё", "Native Messaging"]),
   ("⚙️", "Помощник", "на вашем ПК", ["xray · локальный SOCKS5", "127.0.0.1:10808", "проверка generate_204"]),
   ("🔥", "Ваш сервер", ":443", ["Xray Reality", "свой UUID на человека", "ставится одной командой"]),
   ("🌍", "Интернет", "любой сайт", ["YouTube, ChatGPT…", "IP вашего сервера", "без утечек"])],
   tun="VLESS + XTLS-Vision + Reality", dpi="DPI видит: TLS → www.microsoft.com",
   fb="Запасной путь", fbt="ssh -D 10808 → wokok@server  ·  только проброс портов, без шелла и пароля",
   local="ваш компьютер", remote="облако"),
}
W, H = 1280, 600
X, CW, CY, CH = [40, 330, 720, 1010], 230, 170, 230
def svg(t):
    o = [f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="Segoe UI, Inter, Helvetica, Arial, sans-serif">
<defs>
 <radialGradient id="bg" cx=".5" cy=".35" r=".8"><stop offset="0" stop-color="#2a1a12"/><stop offset="1" stop-color="#0d0b0a"/></radialGradient>
 <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity=".10"/><stop offset="1" stop-color="#ffffff" stop-opacity=".03"/></linearGradient>
 <linearGradient id="fire" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#ff4d1a"/><stop offset="1" stop-color="#ffc23a"/></linearGradient>
 <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
 <marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="#ffb03a"/></marker>
 <marker id="ag" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="#8a8a94"/></marker>
</defs>
<rect width="{W}" height="{H}" rx="28" fill="url(#bg)"/>
<text x="{W//2}" y="62" text-anchor="middle" font-size="34" font-weight="800" fill="#f5e9d8">{t["title"]}</text>''']
    # zones
    for x0, x1, lab in ((24, 586, t["local"]), (700, 1256, t["remote"])):
        o.append(f'<rect x="{x0}" y="132" width="{x1-x0}" height="{CH+60}" rx="22" fill="none" stroke="#ffffff" stroke-opacity=".08" stroke-dasharray="6 6"/>')
        o.append(f'<text x="{x0+18}" y="152" font-size="13" fill="#9a8f86" letter-spacing="2">{lab.upper()}</text>')
    # arrows
    mid = CY + 70
    for a, b in ((0, 1), (2, 3)):
        o.append(f'<line x1="{X[a]+CW+8}" y1="{mid}" x2="{X[b]-10}" y2="{mid}" stroke="#ffb03a" stroke-width="4" marker-end="url(#ah)"/>')
    # tunnel
    x1, x2 = X[1] + CW + 6, X[2] - 6
    o.append(f'<rect x="{x1}" y="{mid-16}" width="{x2-x1}" height="32" rx="16" fill="url(#fire)" opacity=".9" filter="url(#glow)"/>')
    o.append(f'<text x="{(x1+x2)//2}" y="{mid+6}" text-anchor="middle" font-size="18">🔒</text>')
    o.append(f'<text x="{(x1+x2)//2}" y="{CY-48}" text-anchor="middle" font-size="16" font-weight="700" fill="#ffc23a">{t["tun"]}</text>')
    o.append(f'<rect x="{(x1+x2)//2-170}" y="{CY+CH+14}" width="340" height="34" rx="17" fill="#000" fill-opacity=".45" stroke="#ffffff" stroke-opacity=".12"/>')
    o.append(f'<text x="{(x1+x2)//2}" y="{CY+CH+37}" text-anchor="middle" font-size="14" fill="#cfc4ba">👁 {t["dpi"]}</text>')
    # cards
    for x, (ic, name, sub, lines) in zip(X, t["c"]):
        hot = name in ("Your server", "Ваш сервер")
        o.append(f'<rect x="{x}" y="{CY}" width="{CW}" height="{CH}" rx="20" fill="url(#glass)" stroke="{"#ff8a2a" if hot else "#ffffff"}" stroke-opacity="{.8 if hot else .16}" stroke-width="{2 if hot else 1.2}"{" filter=\"url(#glow)\"" if hot else ""}/>')
        o.append(f'<text x="{x+22}" y="{CY+58}" font-size="34">{ic}</text>')
        o.append(f'<text x="{x+72}" y="{CY+46}" font-size="21" font-weight="800" fill="#f5e9d8">{name}</text>')
        o.append(f'<text x="{x+72}" y="{CY+68}" font-size="13" fill="#ff9a3a">{sub}</text>')
        for i, l in enumerate(lines):
            y = CY + 112 + i * 34
            o.append(f'<circle cx="{x+26}" cy="{y-5}" r="3.5" fill="#ffb03a"/>')
            o.append(f'<text x="{x+40}" y="{y}" font-size="14.5" fill="#d9cfc6">{l}</text>')
    # fallback
    fy = H - 52
    o.append(f'<path d="M{X[1]+CW//2} {CY+CH} V{fy} H{X[2]+CW//2} V{CY+CH+4}" fill="none" stroke="#8a8a94" stroke-width="2.5" stroke-dasharray="8 7" marker-end="url(#ag)"/>')
    o.append(f'<rect x="{W//2-330}" y="{fy-18}" width="660" height="36" rx="18" fill="#17130f" stroke="#8a8a94" stroke-opacity=".6"/>')
    o.append(f'<text x="{W//2}" y="{fy+5}" text-anchor="middle" font-size="14" fill="#bdb3aa"><tspan font-weight="700" fill="#e8ddd2">{t["fb"]}:</tspan> {t["fbt"]}</text>')
    o.append("</svg>")
    return "\n".join(o)
for k, suf in (("en", ""), ("ru", ".ru")):
    (root / f"docs/img/how-it-works{suf}.svg").write_text(svg(T[k]), encoding="utf-8")
