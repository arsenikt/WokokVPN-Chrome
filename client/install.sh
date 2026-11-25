#!/usr/bin/env bash
# Wokok VPN — macOS / Linux client installer (no sudo, no Node, no Python).
#   curl -fsSL https://raw.githubusercontent.com/arsenikt/WokokVPN-Chrome/main/client/install.sh | bash
#   … | bash -s -- --uninstall
set -euo pipefail
REPO="${WOKOK_REPO:-arsenikt/WokokVPN-Chrome}"
BRANCH="${WOKOK_BRANCH:-main}"
HOSTNAME_="com.wokok.chrome"
EXT_IDS="pkimbklalingmifhjiojgcckpfinfjdo${WOKOK_EXT_IDS:+,$WOKOK_EXT_IDS}"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
C1=$'\e[38;5;208m'; OK=$'\e[32m'; R=$'\e[0m'
say() { printf '%s  %s%s\n' "$C1" "$*" "$R"; }
ok()  { printf '%s  [ok] %s%s\n' "$OK" "$*" "$R"; }

OS="$(uname -s)"; ARCH="$(uname -m)"
if [ "$OS" = Darwin ]; then
  D="$HOME/Library/Application Support/WokokVPN"; B="$HOME/Library/Application Support"
  DIRS=("Google/Chrome" "Google/Chrome Beta" "Chromium" "Microsoft Edge" "BraveSoftware/Brave-Browser" "Vivaldi" "Yandex/YandexBrowser")
  case "$ARCH" in arm64) PKG=macos-arm64-v8a ;; *) PKG=macos-64 ;; esac
else
  D="${XDG_DATA_HOME:-$HOME/.local/share}/wokokvpn"; B="${XDG_CONFIG_HOME:-$HOME/.config}"
  DIRS=("google-chrome" "google-chrome-beta" "chromium" "microsoft-edge" "BraveSoftware/Brave-Browser" "vivaldi" "yandex-browser")
  case "$ARCH" in aarch64|arm64) PKG=linux-arm64-v8a ;; armv7*) PKG=linux-arm32-v7a ;; *) PKG=linux-64 ;; esac
fi

if [ "${1:-}" = "--uninstall" ]; then
  pkill -f "$D/bin/xray" 2>/dev/null || true
  for d in "${DIRS[@]}"; do rm -f "$B/$d/NativeMessagingHosts/$HOSTNAME_.json"; done
  rm -rf "$D"; ok "Wokok VPN removed. Remove the extension in chrome://extensions"; exit 0
fi

printf '\n%s   W O K O K   V P N   for Chrome%s\n\n' "$C1" "$R"
for t in curl unzip perl; do command -v "$t" >/dev/null || { echo "Please install '$t' first"; exit 1; }; done
mkdir -p "$D/bin" "$D/host" "$D/run"
HERE=""; [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/host/wokok-host.pl" ] && HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$D/bin/xray" ] || [ -n "${WOKOK_UPDATE:-}" ]; then
  say "Downloading Xray-core ($PKG)…"
  tmp="$(mktemp -d)"; curl -fsSL "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-$PKG.zip" -o "$tmp/x.zip"
  unzip -oq "$tmp/x.zip" -d "$D/bin"; rm -rf "$tmp"; chmod +x "$D/bin/xray"
  [ "$OS" = Darwin ] && xattr -dr com.apple.quarantine "$D/bin" 2>/dev/null || true
fi
ok "Xray $("$D/bin/xray" version | head -1 | awk '{print $2}')"

if [ -n "$HERE" ]; then cp "$HERE/host/wokok-host.pl" "$D/host/"; else curl -fsSL "$RAW/client/host/wokok-host.pl" -o "$D/host/wokok-host.pl"; fi
chmod +x "$D/host/wokok-host.pl"
ORIGINS="$(printf '%s' "$EXT_IDS" | tr ',' '\n' | sed 's|.*|    "chrome-extension://&/"|' | paste -sd, -)"
MANIFEST="{
  \"name\": \"$HOSTNAME_\",
  \"description\": \"Wokok VPN helper\",
  \"path\": \"$D/host/wokok-host.pl\",
  \"type\": \"stdio\",
  \"allowed_origins\": [
$ORIGINS
  ]
}"
n=0
for d in "${DIRS[@]}"; do
  if [ -d "$B/$d" ] || [ "$d" = "Google/Chrome" ] || [ "$d" = "google-chrome" ]; then
    mkdir -p "$B/$d/NativeMessagingHosts"; printf '%s\n' "$MANIFEST" > "$B/$d/NativeMessagingHosts/$HOSTNAME_.json"; n=$((n+1))
  fi
done
ok "Helper registered in $n browser(s)"

EXT="$D/extension"; rm -rf "$EXT"
if [ -n "$HERE" ] && [ -f "$HERE/../extension/manifest.json" ]; then cp -R "$HERE/../extension" "$EXT"
else tmp="$(mktemp -d)"; curl -fsSL "https://github.com/$REPO/releases/latest/download/wokok-extension.zip" -o "$tmp/e.zip"; unzip -oq "$tmp/e.zip" -d "$EXT"; rm -rf "$tmp"; fi
ok "Extension unpacked to $EXT"

Y=$'\e[33m'; D=$'\e[2m'; G=$'\e[32m'
LINE="${D}  ------------------------------------------------------------${R}"
cat <<EOF

${G}  This computer is ready. 3 steps left:${R}

${C1}  [1/3] SERVER: get your wokok:// link${R}
$LINE
      You need a VPS outside your country (Ubuntu/Debian, 512 MB RAM, ~\$3/mo).
      Connect to it over SSH and run ONE command:

${Y}      ssh root@YOUR_SERVER_IP
      curl -fsSL $RAW/server/install.sh | sudo bash${R}

      After ~30 s it prints a link that starts with  wokok://  - copy it.
${D}      Already installed?  Show the link again:   sudo wokok link me
      Link for a friend:                       sudo wokok add alice${R}

${C1}  [2/3] CHROME: load the extension (once)${R}
$LINE
      1. Open  chrome://extensions
      2. Turn on  Developer mode  (top right)
      3. Click  Load unpacked  and choose:
${Y}      $EXT${R}
${D}      Updating? Just press the reload button on the Wokok card.${R}

${C1}  [3/3] CONNECT${R}
$LINE
      Click the wok icon in Chrome -> paste the wokok:// link -> tap the wok.

${D}  Help: https://github.com/$REPO#-quick-start${R}

EOF
[ "$OS" = Darwin ] && open "$EXT" 2>/dev/null || true
