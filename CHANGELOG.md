# Changelog

## 2.1.12
- Default routing mode is now "All sites": everything goes through the VPN out of the box (Smart and All-except stay one click away)

## 2.1.11
- Auto-detect the real SSH port: if the port in the link is closed, the helper finds the SSH server by its banner (tries common ports) and the extension saves the right port
- The extension remembers when Reality is unreachable and goes straight to SSH next time (re-tests Reality every 6 h)

## 2.1.10
- Settings: editable SSH port per server (fix a wrong port without a new link)
- Clearer error when the SSH port is unreachable

## 2.1.9
- Re-running the server install command is now a one-step repair/update: pins and installs the latest `wokok`, keeps all keys, fixes the SSH port, prints the link
- `wokok link` / `add` auto-fix a wrong SSH port in links (detects what sshd really listens on), no manual `wokok sshport` needed

## 2.1.8
- Pasting a new link for an already added server now updates it (SSH port, SNI, keys) instead of silently keeping the old data

## 2.1.7
- `sudo wokok update` now updates everything: wokok itself, Xray-core and generated configs (keys and links stay); `--check` only looks
- `wokok version`, `wokok sshport N`; real SSH port detected via ss; foreign authorized_keys are preserved

## 2.1.6 (2.1.5)
- Helper reports the real cause: unreachable server port (VPS firewall) vs. tunnel without internet
- Firewall hint in server installer, `wokok status`, README (EN/RU)

## 2.1.4
- Local SOCKS port is picked automatically: if 10808 is busy (another VPN/proxy), the helper uses the next free port (10809…10857) and the extension follows it
- Leftover Wokok xray/ssh processes are cleaned up before connecting

## 2.1.3
- Server installer no longer dies silently: fixed abort when `sshd -T` fails (Ubuntu socket activation), clear error with line + log on any failure
- `sudo wokok link` shows your link again any time; all links saved to /root/wokok-links.txt
- Link recovery documented in README, website, client installers and the extension

## 2.1.2
- Client installers end with a clear 3-step guide: server command, Chrome, connect
- Extension onboarding shows the server install command (click to copy) before asking for the wokok:// link

## 2.1.1
- Website: install commands wrap instead of showing horizontal scrollbars
- Tip jar is now a tiny collapsible 🥡 link (website, README, extension settings), no big image

## 2.1.0
- 🥡 "Buy the author a wok": a low-key tip jar (EVM, Solana, TRON) in the README, on the website and in the extension settings
- New Gemini artwork: the wok tip jar
- GitHub Sponsor button via FUNDING.yml

## 2.0.0
- Public release: VLESS Reality + SSH fallback, one-command server and client installers
- Smart / All / Except routing, presets, antifilter community list, blocked-site detector
- WebRTC leak guard, kill switch, auto-reconnect, multi-server with fastest pick
- Popup dashboard (IP, ping, speed test, uptime), hotkeys, context menu, backup
- English + Russian UI
