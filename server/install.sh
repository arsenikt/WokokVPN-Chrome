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

LOG=/tmp/wokok-install.log; : > "$LOG"
on_err() {
  printf '
%s✖ Install stopped at line %s: %s%s
' "$ERR" "$1" "$2" "$R" >&2
  [ -s "$LOG" ] && { printf '%s--- last lines of %s ---%s
' "$DIM" "$LOG" "$R" >&2; tail -n 15 "$LOG" >&2; }
  printf '
  Re-run the same command after fixing it. If Wokok was already set up, your link is still there:
    %ssudo wokok link%s
  Please report it: https://github.com/%s/issues
' "$C1" "$R" "$REPO" >&2
}
trap 'on_err $LINENO "$BASH_COMMAND"' ERR

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
# Only install what is missing; never hide errors; survive a half-broken dpkg.
REQ=(curl jq openssl unzip); OPT=(qrencode)
missing=(); for t in "${REQ[@]}" "${OPT[@]}"; do command -v "$t" >/dev/null || missing+=("$t"); done

apt_try() {
  apt-get -o DPkg::Lock::Timeout=180 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" >>"$LOG" 2>&1
}
pkg_install() {  # $@ = package names
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    apt_try update || true
    apt_try install -y --no-install-recommends "$@" ca-certificates && return 0
    say "apt failed, repairing the package manager (dpkg --configure -a, apt -f install)…"
    dpkg --configure -a >>"$LOG" 2>&1 || true
    apt_try install -f -y || true
    apt_try install -y --no-install-recommends "$@" ca-certificates
  elif command -v dnf >/dev/null; then
    dnf install -y -q epel-release >>"$LOG" 2>&1 || true; dnf install -y -q "$@" >>"$LOG" 2>&1
  elif command -v yum >/dev/null; then
    yum install -y -q epel-release >>"$LOG" 2>&1 || true; yum install -y -q "$@" >>"$LOG" 2>&1
  elif command -v apk >/dev/null; then
    apk add -q bash "${@/qrencode/libqrencode-tools}" >>"$LOG" 2>&1
  else
    return 1
  fi
}

if [ ${#missing[@]} -eq 0 ]; then
  ok "Packages already present"
else
  say "Installing: ${missing[*]}…"
  if ! pkg_install "${missing[@]}"; then
    # retry without optional tools (QR is nice-to-have)
    req_missing=(); for t in "${REQ[@]}"; do command -v "$t" >/dev/null || req_missing+=("$t"); done
    [ ${#req_missing[@]} -eq 0 ] || pkg_install "${req_missing[@]}" || true
  fi
  # Package manager is broken? Fetch a static jq so a bad dpkg can't block us.
  if ! command -v jq >/dev/null && command -v curl >/dev/null; then
    case "$(uname -m)" in aarch64|arm64) JQA=arm64 ;; armv7*) JQA=armhf ;; *) JQA=amd64 ;; esac
    say "Package manager failed, downloading static jq ($JQA)…"
    curl -fsSL "https://github.com/jqlang/jq/releases/latest/download/jq-linux-$JQA" -o /usr/local/bin/jq >>"$LOG" 2>&1 \
      && chmod 755 /usr/local/bin/jq && /usr/local/bin/jq --version >/dev/null 2>&1 || rm -f /usr/local/bin/jq
    hash -r
  fi
  # No unzip and no working apt: tiny python3 stand-in (enough for the Xray installer: unzip -q FILE -d DIR).
  if ! command -v unzip >/dev/null && command -v python3 >/dev/null; then
    cat > /usr/local/bin/unzip <<'PY'
#!/usr/bin/env python3
import sys, zipfile
a = [x for x in sys.argv[1:] if not x.startswith('-') or x == '-d']
d = a[a.index('-d') + 1] if '-d' in a else '.'
f = [x for x in a if x != '-d' and x != d][0]
zipfile.ZipFile(f).extractall(d)
PY
    chmod 755 /usr/local/bin/unzip; hash -r
  fi
  for t in "${REQ[@]}"; do
    if ! command -v "$t" >/dev/null; then
      printf '%s\n--- last lines of %s ---%s\n' "$ERR" "$LOG" "$R" >&2; tail -n 25 "$LOG" >&2
      die "Could not install '$t'. Fix the package manager (see log above), e.g.:  sudo dpkg --configure -a && sudo apt -f install   then re-run."
    fi
  done
  command -v qrencode >/dev/null || printf '%s! qrencode not installed: links will be shown without QR codes%s\n' "$C2" "$R"
  ok "Packages ready"
fi

# ---------- xray ----------
if ! command -v xray >/dev/null; then
  say "Installing Xray-core (official XTLS installer)…"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >>"$LOG" 2>&1
fi
XRAY="$(command -v xray || echo /usr/local/bin/xray)"
[ -x "$XRAY" ] || die "Xray install failed (see $LOG)"
ok "Xray $("$XRAY" version | head -1 | awk '{print $2}' || true)"

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
  KEYS="$("$XRAY" x25519 2>&1)"
  PRIV="$(printf '%s\n' "$KEYS" | awk -F': *' '/^Private ?[Kk]ey/{print $2; exit}')"
  PUB="$(printf '%s\n' "$KEYS" | awk -F': *' '/^(Public ?[Kk]ey|Password)/{print $2; exit}')"
  [ -n "$PRIV" ] && [ -n "$PUB" ] || die "Could not parse 'xray x25519' output: $KEYS"
  SID="$(openssl rand -hex 8)"
  IP="${WOKOK_HOST:-}"; [ -n "$IP" ] || IP="$(curl -4 -fsS --max-time 8 https://api.ipify.org || curl -4 -fsS --max-time 8 https://ifconfig.me || hostname -I | awk '{print $1}' || true)"
  [ -n "$IP" ] || die "Could not detect the public IP. Re-run with WOKOK_HOST=1.2.3.4"
  [ -n "$NAME" ] || NAME="Wokok $(hostname -s)"
  # sshd -T fails on many Ubuntu images (socket activation, no /run/sshd) - never let that abort us.
  SSHPORT="$( (sshd -T 2>/dev/null || true) | awk '/^port /{print $2; exit}')"
  [ -n "$SSHPORT" ] || SSHPORT="$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/{print $2; exit}' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true)"
  SSHPORT="${SSHPORT:-22}"
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
systemctl restart xray || true
sleep 1
systemctl is-active --quiet xray || { journalctl -u xray -n 15 --no-pager >&2 || true; die "Xray failed to start (log above). Your link still works once it starts: sudo wokok link"; }
ok "Xray Reality is listening on :$(jq -r .port "$ETC/server.json") (disguised as $(jq -r .sni "$ETC/server.json"))"

trap - ERR
echo
wokok link me
cat <<EOF
${C2}════════════════════════════════════════════════════════════${R}
${C2}  Lost the link? Get it again any time on this server:${R}
     ${C1}sudo wokok link${R}            (also saved in /root/wokok-links.txt)

${C2}  Next:${R}
  1. On your PC install the helper:  https://github.com/$REPO#-2-your-computer
  2. Click the wok icon in Chrome → paste the ${C1}wokok://${R} link above.
  ⚠ Cloud firewall! Many VPS providers block ports in their web panel (not on the server).
     Make sure TCP $(jq -r .port "$ETC/server.json") is open there, otherwise the extension cannot connect.
  3. Key for a friend:  ${C1}sudo wokok add alice${R}   (revoke: ${C1}sudo wokok del alice${R})

  ${DIM}The vless:// link also works in v2rayN, Hiddify, Streisand, NekoBox — phones included.${R}
${C2}════════════════════════════════════════════════════════════${R}
EOF
