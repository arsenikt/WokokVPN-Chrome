#!/usr/bin/env bash
# Wokok VPN — server installer.
#   curl -fsSL https://raw.githubusercontent.com/arsenikt/WokokVPN-Chrome/main/server/install.sh | sudo bash
# Options (env or flags):
#   --port 443            Reality port (default 443, falls back to 8443 if busy)
#   --sni www.microsoft.com   Site Reality pretends to be
#   --name myserver       Display name in the extension
#   --no-ssh              Do not create the SSH fallback account
#   --uninstall           Remove everything Wokok installed
set -euo pipefail

REPO="${WOKOK_REPO:-arsenikt/WokokVPN-Chrome}"
BRANCH="${WOKOK_BRANCH:-main}"
PORT="${WOKOK_PORT:-443}"
SNI="${WOKOK_SNI:-www.microsoft.com}"
NAME="${WOKOK_NAME:-}"
SSH_FALLBACK="${WOKOK_SSH:-1}"
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --sni) SNI="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --no-ssh) SSH_FALLBACK=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

C1=$'\e[38;5;208m'; C2=$'\e[38;5;220m'; OK=$'\e[32m'; ERR=$'\e[31m'; DIM=$'\e[2m'; R=$'\e[0m'
say()  { printf '%s🥡 %s%s\n' "$C1" "$*" "$R"; }
ok()   { printf '%s✔ %s%s\n' "$OK" "$*" "$R"; }
die()  { printf '%s✖ %s%s\n' "$ERR" "$*" "$R" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: curl -fsSL ... | sudo bash"

if [ "$UNINSTALL" = 1 ]; then
  if command -v wokok >/dev/null; then exec wokok uninstall --yes; fi
  die "wokok CLI not found, nothing to uninstall"
fi

cat <<EOF
${C1}
 __        __    _         _      __     ______  _   _
 \ \      / /__ | | _____ | | __  \ \   / /  _ \| \ | |
  \ \ /\ / / _ \| |/ / _ \| |/ /   \ \ / /| |_) |  \| |
   \ V  V / (_) |   < (_) |   <     \ V / |  __/| |\  |
    \_/\_/ \___/|_|\_\___/|_|\_\     \_/  |_|   |_| \_|
${C2}        stir-fry your traffic · Reality + SSH fallback${R}

EOF

# ---------- packages ----------
say "Installing packages (curl, jq, qrencode, openssl)…"
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq curl jq qrencode openssl ca-certificates unzip >/dev/null
elif command -v dnf >/dev/null; then
  dnf install -y -q epel-release >/dev/null 2>&1 || true
  dnf install -y -q curl jq qrencode openssl unzip >/dev/null
elif command -v yum >/dev/null; then
  yum install -y -q epel-release >/dev/null 2>&1 || true
  yum install -y -q curl jq qrencode openssl unzip >/dev/null
elif command -v apk >/dev/null; then
  apk add -q curl jq libqrencode-tools openssl bash unzip >/dev/null
else
  die "Unsupported distro: install curl jq qrencode openssl manually"
fi
ok "Packages ready"

# ---------- xray ----------
if ! command -v xray >/dev/null; then
  say "Installing Xray-core (official XTLS installer)…"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null
fi
XRAY="$(command -v xray || echo /usr/local/bin/xray)"
ok "Xray $("$XRAY" version | head -1 | awk '{print $2}')"

# ---------- port ----------
port_busy() { ss -ltnH "sport = :$1" 2>/dev/null | grep -q .; }
if port_busy "$PORT" && ! ss -ltnpH "sport = :$PORT" | grep -q xray; then
  say "Port $PORT is busy, trying 8443"
  PORT=8443
  port_busy "$PORT" && die "Ports 443 and 8443 are busy. Use --port N"
fi

# ---------- keys & config ----------
ETC=/etc/wokok
mkdir -p "$ETC/users"
chmod 700 "$ETC"
if [ ! -f "$ETC/server.json" ]; then
  KEYS="$("$XRAY" x25519)"
  PRIV="$(printf '%s\n' "$KEYS" | awk -F': *' '/^Private ?[Kk]ey/{print $2; exit}')"
  PUB="$(printf '%s\n' "$KEYS" | awk -F': *' '/^(Public ?[Kk]ey|Password)/{print $2; exit}')"
  [ -n "$PRIV" ] && [ -n "$PUB" ] || die "Could not parse 'xray x25519' output"
  SID="$(openssl rand -hex 8)"
  IP="$(curl -4 -fsS --max-time 8 https://api.ipify.org || curl -4 -fsS --max-time 8 https://ifconfig.me || hostname -I | awk '{print $1}')"
  [ -n "$NAME" ] || NAME="Wokok $(hostname -s)"
  SSHPORT="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')"; SSHPORT="${SSHPORT:-22}"
  jq -n --arg ip "$IP" --argjson port "$PORT" --arg sni "$SNI" --arg priv "$PRIV" --arg pub "$PUB" \
        --arg sid "$SID" --arg name "$NAME" --argjson ssh "$SSH_FALLBACK" --argjson sshport "$SSHPORT" \
    '{host:$ip,port:$port,sni:$sni,privateKey:$priv,publicKey:$pub,shortId:$sid,name:$name,ssh:($ssh==1),sshPort:$sshport}' \
    > "$ETC/server.json"
  chmod 600 "$ETC/server.json"
fi

# ---------- SSH fallback account ----------
if [ "$(jq -r .ssh "$ETC/server.json")" = "true" ] && ! id wokok >/dev/null 2>&1; then
  NOLOGIN="$(command -v nologin || echo /usr/sbin/nologin)"
  useradd -m -s "$NOLOGIN" wokok 2>/dev/null || adduser -D -s "$NOLOGIN" wokok
  passwd -l wokok >/dev/null 2>&1 || true
  install -d -m 700 -o wokok -g wokok /home/wokok/.ssh
  install -m 600 -o wokok -g wokok /dev/null /home/wokok/.ssh/authorized_keys
  ok "SSH fallback user 'wokok' (port-forwarding only, no shell)"
fi

# ---------- CLI ----------
say "Installing the 'wokok' command…"
SRC=""
[ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ] && SRC="$(dirname "${BASH_SOURCE[0]}")/wokok"
if [ -n "$SRC" ] && [ -f "$SRC" ]; then install -m 755 "$SRC" /usr/local/bin/wokok
else curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/server/wokok" -o /usr/local/bin/wokok && chmod 755 /usr/local/bin/wokok
fi

[ -n "$(ls -A "$ETC/users")" ] || wokok add me --quiet
wokok render

# ---------- firewall ----------
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow "$PORT"/tcp >/dev/null; fi
if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd -q --permanent --add-port="$PORT"/tcp && firewall-cmd -q --reload
fi

systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 1
systemctl is-active --quiet xray || die "Xray failed to start: journalctl -u xray -n 50"
ok "Xray Reality is listening on :$(jq -r .port "$ETC/server.json") (disguised as $(jq -r .sni "$ETC/server.json"))"

echo
wokok link me
cat <<EOF

${C2}Next:${R}
  1. Install the Chrome helper on your PC:   ${DIM}https://github.com/$REPO#-2-your-computer${R}
  2. Open the Wokok extension → paste the ${C1}wokok://${R} link above.
  3. Give friends their own key:  ${C1}wokok add alice${R}   (revoke: ${C1}wokok del alice${R})

  ${DIM}The vless:// link also works in v2rayN, Hiddify, Streisand, NekoBox — phones included.${R}
EOF
