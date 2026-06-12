#!/usr/bin/env sh
set -eu

CONFIG_DIR="/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
META_PATH="${CONFIG_DIR}/entry.env"
INFO_ENTRY="/root/singbox-entry-info.txt"
INFO_HOME="/root/singbox-home-info.txt"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "Please run as root."
}

need_tty() {
  [ -r /dev/tty ] || die "Please run from an interactive SSH terminal."
}

ask() {
  prompt="$1"
  default="${2:-}"
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default" > /dev/tty
  else
    printf "%s: " "$prompt" > /dev/tty
  fi
  read -r value < /dev/tty
  printf '%s' "${value:-$default}"
}

detect_os() {
  [ -r /etc/os-release ] || die "Cannot read /etc/os-release."
  OS_ID="$(. /etc/os-release && printf '%s' "${ID}")"
  case "$OS_ID" in
    debian|ubuntu) OS_FAMILY="debian" ;;
    alpine) OS_FAMILY="alpine" ;;
    *) die "Unsupported OS: $OS_ID. Supported: Debian/Ubuntu/Alpine." ;;
  esac
}

install_deps() {
  case "$OS_FAMILY" in
    debian)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y bash curl ca-certificates openssl python3 nftables
      ;;
    alpine)
      apk update
      apk add --no-cache bash curl ca-certificates openssl python3 openrc
      ;;
  esac
}

install_singbox() {
  if command -v sing-box >/dev/null 2>&1; then
    SINGBOX_BIN="$(command -v sing-box)"
    return
  fi

  log "Installing sing-box from official installer..."
  if command -v bash >/dev/null 2>&1; then
    bash -c "$(curl -fsSL https://sing-box.app/install.sh)"
  else
    sh -c "$(curl -fsSL https://sing-box.app/install.sh)"
  fi

  command -v sing-box >/dev/null 2>&1 || die "sing-box install failed."
  SINGBOX_BIN="$(command -v sing-box)"
}

random_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
  fi
}

random_hex8() {
  openssl rand -hex 4
}

random_ss2022_password() {
  openssl rand -base64 32 | tr -d '\n\r'
}

public_ip() {
  for u in https://api.ipify.org https://icanhazip.com https://ifconfig.me https://ipinfo.io/ip; do
    ip="$(curl -fsSL --max-time 5 "$u" 2>/dev/null | tr -d '[:space:]' || true)"
    [ -n "$ip" ] && { printf '%s' "$ip"; return; }
  done
  printf 'YOUR_SERVER_IP'
}

reality_keypair() {
  out="$(sing-box generate reality-keypair)"
  REALITY_PRIVATE_KEY="$(printf '%s\n' "$out" | awk -F: '/PrivateKey/ {gsub(/^[ \t]+/,"",$2); print $2}')"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "$out" | awk -F: '/PublicKey/ {gsub(/^[ \t]+/,"",$2); print $2}')"
  [ -n "$REALITY_PRIVATE_KEY" ] && [ -n "$REALITY_PUBLIC_KEY" ] || die "Failed to generate Reality keypair."
}

write_systemd_service() {
  cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SINGBOX_BIN} run -c ${CONFIG_PATH}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=3
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now sing-box
}

write_openrc_service() {
  cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
name="sing-box"
command="${SINGBOX_BIN}"
command_args="run -c ${CONFIG_PATH}"
command_background=true
pidfile="/run/sing-box.pid"
respawn_delay=3
respawn_max=0
depend() {
  need net
}
EOF
  chmod +x /etc/init.d/sing-box
  rc-update add sing-box default
  rc-service sing-box restart
}

restart_singbox() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sing-box
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box restart
  else
    die "No supported service manager found."
  fi
}

check_config() {
  sing-box check -c "$CONFIG_PATH"
}

enable_only_443_firewall() {
  [ "$OS_FAMILY" = "debian" ] || return 0

  ssh_port="$(printf '%s' "${SSH_CONNECTION:-}" | awk '{print $4}')"
  if [ "${FORCE_ONLY_443_FIREWALL:-0}" != "1" ] && [ "$ssh_port" != "443" ]; then
    log ""
    log "WARNING: DMIT/HK firewall will allow inbound TCP 443 only."
    log "Current SSH server port looks like: ${ssh_port:-unknown}."
    log "After enabling this firewall, normal SSH may be cut off unless you use console access."
    printf "Type ONLY443 to continue: " > /dev/tty
    read -r confirm < /dev/tty
    [ "$confirm" = "ONLY443" ] || die "Cancelled firewall setup."
  elif [ "${FORCE_ONLY_443_FIREWALL:-0}" != "1" ]; then
    log ""
    log "WARNING: This will enable an inbound TCP 443-only firewall."
    log "If SSH is also using TCP 443, it will conflict with sing-box Reality on TCP 443."
    log "Make sure you have provider console/rescue access before continuing."
    printf "Type ONLY443 to continue: " > /dev/tty
    read -r confirm < /dev/tty
    [ "$confirm" = "ONLY443" ] || die "Cancelled firewall setup."
  fi

  cat > /etc/nftables.conf <<'EOF'
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;

    ct state established,related accept
    iif lo accept
    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept
    tcp dport 443 accept
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
EOF
  systemctl enable --now nftables
  nft -f /etc/nftables.conf
}

entry_config() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  cat > "$CONFIG_PATH" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [{ "type": "local", "tag": "dns_local" }],
    "final": "dns_local",
    "strategy": "prefer_ipv4"
  },
  "inbounds": [{
    "type": "vless",
    "tag": "reality-in",
    "listen": "::",
    "listen_port": 443,
    "tcp_fast_open": true,
    "users": [{
      "name": "me",
      "uuid": "$ME_UUID",
      "flow": "xtls-rprx-vision"
    }],
    "tls": {
      "enabled": true,
      "server_name": "$REALITY_SNI",
      "reality": {
        "enabled": true,
        "handshake": { "server": "$REALITY_SNI", "server_port": 443 },
        "private_key": "$REALITY_PRIVATE_KEY",
        "short_id": ["$ME_SID"],
        "max_time_difference": "1m"
      }
    }
  }],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "default_domain_resolver": "dns_local",
    "auto_detect_interface": true,
    "rules": [],
    "final": "direct"
  }
}
EOF
  chmod 600 "$CONFIG_PATH"
}

write_entry_meta() {
  cat > "$META_PATH" <<EOF
NODE_ROLE="$NODE_ROLE"
NODE_PREFIX="$NODE_PREFIX"
ACCESS_HOST="$ACCESS_HOST"
REALITY_SNI="$REALITY_SNI"
REALITY_PUBLIC_KEY="$REALITY_PUBLIC_KEY"
REALITY_PRIVATE_KEY="$REALITY_PRIVATE_KEY"
EOF
  chmod 600 "$META_PATH"
}

write_entry_manager() {
  cat > /usr/local/bin/sb <<'PYEOF'
#!/usr/bin/env python3
import base64, json, os, re, shutil, subprocess, sys, time, uuid
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

CONFIG = Path("/etc/sing-box/config.json")
META = Path("/etc/sing-box/entry.env")

def load_meta():
    data = {}
    if META.exists():
        for line in META.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                data[k] = v.strip().strip('"')
    return data

def load_cfg():
    return json.loads(CONFIG.read_text())

def save_cfg(cfg, reason):
    ts = time.strftime("%Y%m%d%H%M%S")
    backup = CONFIG.with_suffix(f".json.bak.{reason}.{ts}")
    shutil.copy2(CONFIG, backup)
    tmp = CONFIG.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n")
    os.chmod(tmp, 0o600)
    tmp.replace(CONFIG)
    try:
        subprocess.check_call(["sing-box", "check", "-c", str(CONFIG)])
        restart()
    except Exception:
        shutil.copy2(backup, CONFIG)
        restart()
        raise SystemExit(f"Config check failed. Rolled back: {backup}")
    print(f"OK. Backup: {backup}")

def restart():
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "restart", "sing-box"])
    elif shutil.which("rc-service"):
        subprocess.call(["rc-service", "sing-box", "restart"])

def inbound(cfg):
    for item in cfg.get("inbounds", []):
        if item.get("type") == "vless" and item.get("tag") == "reality-in":
            return item
    raise SystemExit("Cannot find reality-in inbound.")

def safe_name(name):
    name = unquote(name or "").strip()
    name = re.sub(r"[^A-Za-z0-9_.-]+", "-", name).strip("-")
    return name[:32] or f"node-{int(time.time())}"

def b64decode_any(s):
    s = s.strip()
    pad = "=" * ((4 - len(s) % 4) % 4)
    return base64.urlsafe_b64decode((s + pad).encode()).decode()

def parse_ss_link(link):
    if not link.startswith("ss://"):
        raise SystemExit("Please paste a ss:// link.")
    u = urlsplit(link)
    tag = safe_name(unquote(u.fragment) or "home")
    body = link[5:].split("#", 1)[0].split("?", 1)[0]

    if "@" in body:
        left, right = body.rsplit("@", 1)
        if ":" not in left:
            left = b64decode_any(left)
        method, password = left.split(":", 1)
        host, port = right.rsplit(":", 1)
    else:
        decoded = b64decode_any(body)
        left, right = decoded.rsplit("@", 1)
        method, password = left.split(":", 1)
        host, port = right.rsplit(":", 1)

    host = host.strip("[]")
    return {
        "name": tag,
        "method": unquote(method),
        "password": unquote(password),
        "server": host,
        "server_port": int(port),
    }

def link_for_user(name, user, sid):
    meta = load_meta()
    host = meta.get("ACCESS_HOST", "YOUR_SERVER_IP")
    sni = meta.get("REALITY_SNI", "www.cloudflare.com")
    pbk = meta.get("REALITY_PUBLIC_KEY", "")
    prefix = meta.get("NODE_PREFIX", "ENTRY")
    return (
        f"vless://{user['uuid']}@{host}:443"
        f"?encryption=none&flow=xtls-rprx-vision&security=reality"
        f"&sni={sni}&fp=chrome&pbk={pbk}&sid={sid}&type=tcp&headerType=none"
        f"#{quote(prefix + '-' + name)}"
    )

def list_links():
    cfg = load_cfg()
    ib = inbound(cfg)
    sids = ib.get("tls", {}).get("reality", {}).get("short_id", [])
    users = ib.get("users", [])
    for i, user in enumerate(users):
        name = user.get("name", f"user{i+1}")
        sid = sids[i] if i < len(sids) else (sids[0] if sids else "")
        print()
        print(name)
        print(link_for_user(name, user, sid))

def add_friend(name):
    name = safe_name(name)
    if name.startswith("relay-"):
        raise SystemExit("Friend name cannot start with relay-.")
    cfg = load_cfg()
    ib = inbound(cfg)
    if any(u.get("name") == name for u in ib.get("users", [])):
        raise SystemExit(f"User already exists: {name}")
    user = {"name": name, "uuid": str(uuid.uuid4()), "flow": "xtls-rprx-vision"}
    sid = os.urandom(4).hex()
    ib.setdefault("users", []).append(user)
    ib["tls"]["reality"].setdefault("short_id", []).append(sid)
    save_cfg(cfg, "add-friend")
    print(link_for_user(name, user, sid))

def del_user(name, relay_only=False):
    cfg = load_cfg()
    ib = inbound(cfg)
    users = ib.get("users", [])
    idx = next((i for i, u in enumerate(users) if u.get("name") == name), None)
    if idx is None:
        raise SystemExit(f"User not found: {name}")
    if relay_only and not name.startswith("relay-"):
        raise SystemExit("This command only deletes relay-* users.")
    users.pop(idx)
    sids = ib["tls"]["reality"].setdefault("short_id", [])
    if idx < len(sids):
        sids.pop(idx)
    tag = name.replace("relay-", "ss-", 1)
    cfg["outbounds"] = [o for o in cfg.get("outbounds", []) if o.get("tag") != tag]
    cfg.setdefault("route", {})["rules"] = [
        r for r in cfg.get("route", {}).get("rules", [])
        if name not in r.get("auth_user", [])
    ]
    save_cfg(cfg, "delete")

def add_ss(link):
    ss = parse_ss_link(link)
    base = safe_name(ss["name"])
    user_name = "relay-" + base
    outbound_tag = "ss-" + base
    cfg = load_cfg()
    ib = inbound(cfg)
    if any(u.get("name") == user_name for u in ib.get("users", [])):
        raise SystemExit(f"Relay already exists: {user_name}")
    if any(o.get("tag") == outbound_tag for o in cfg.get("outbounds", [])):
        raise SystemExit(f"Outbound already exists: {outbound_tag}")
    user = {"name": user_name, "uuid": str(uuid.uuid4()), "flow": "xtls-rprx-vision"}
    sid = os.urandom(4).hex()
    ib.setdefault("users", []).append(user)
    ib["tls"]["reality"].setdefault("short_id", []).append(sid)
    cfg.setdefault("outbounds", []).append({
        "type": "shadowsocks",
        "tag": outbound_tag,
        "server": ss["server"],
        "server_port": ss["server_port"],
        "method": ss["method"],
        "password": ss["password"],
        "network": "tcp"
    })
    cfg.setdefault("route", {}).setdefault("rules", []).insert(0, {
        "auth_user": [user_name],
        "action": "route",
        "outbound": outbound_tag
    })
    save_cfg(cfg, "add-ss")
    print()
    print("New Reality relay link:")
    print(link_for_user(user_name, user, sid))

def list_relays():
    cfg = load_cfg()
    ib = inbound(cfg)
    found = False
    for user in ib.get("users", []):
        name = user.get("name", "")
        if name.startswith("relay-"):
            print(name)
            found = True
    if not found:
        print("No relay nodes.")

def menu():
    while True:
        print()
        print("sing-box entry manager")
        print("1. Add SS landing link / 添加 ss:// 落地")
        print("2. Delete relay / 删除落地中转")
        print("3. List relay nodes / 查看落地")
        print("4. Show all Reality links / 查看全部链接")
        print("5. Add direct friend / 添加直连朋友")
        print("6. Delete user / 删除用户")
        print("7. Restart sing-box / 重启")
        print("0. Exit")
        choice = input("Choose: ").strip()
        if choice == "1":
            add_ss(input("Paste ss:// link: ").strip())
        elif choice == "2":
            list_relays()
            del_user(input("Relay name: ").strip(), relay_only=True)
        elif choice == "3":
            list_relays()
        elif choice == "4":
            list_links()
        elif choice == "5":
            add_friend(input("Friend name: ").strip())
        elif choice == "6":
            del_user(input("User name: ").strip(), relay_only=False)
        elif choice == "7":
            restart()
            print("Restarted.")
        elif choice == "0":
            return

def main():
    args = sys.argv[1:]
    if not args:
        return menu()
    cmd = args[0]
    if cmd == "add-ss":
        add_ss(" ".join(args[1:]) if len(args) > 1 else input("Paste ss:// link: ").strip())
    elif cmd == "del-relay":
        del_user(args[1], relay_only=True)
    elif cmd == "list-relays":
        list_relays()
    elif cmd == "links":
        list_links()
    elif cmd == "add-friend":
        add_friend(args[1])
    elif cmd == "del-user":
        del_user(args[1], relay_only=False)
    elif cmd == "restart":
        restart()
    else:
        print("Usage: sb [add-ss|del-relay|list-relays|links|add-friend|del-user|restart]")
        raise SystemExit(1)

if __name__ == "__main__":
    main()
PYEOF
  chmod 700 /usr/local/bin/sb
}

install_entry() {
  role="$1"
  [ "$OS_FAMILY" = "debian" ] || die "DMIT/HK entry requires Debian/Ubuntu."
  install_deps
  install_singbox

  case "$role" in
    dmit)
      NODE_ROLE="dmit"
      NODE_PREFIX="${NODE_PREFIX:-DMIT}"
      REALITY_SNI="${REALITY_SNI:-reed.edu}"
      ;;
    hk)
      NODE_ROLE="hk"
      NODE_PREFIX="${NODE_PREFIX:-HK}"
      REALITY_SNI="${REALITY_SNI:-www.hkex.com.hk}"
      ;;
  esac

  ACCESS_HOST="$(ask "Public IP/domain for Reality links" "$(public_ip)")"
  REALITY_SNI="$(ask "Reality SNI" "$REALITY_SNI")"
  ME_UUID="$(random_uuid)"
  ME_SID="$(random_hex8)"
  reality_keypair

  entry_config
  write_entry_meta
  check_config
  write_systemd_service
  write_entry_manager
  enable_only_443_firewall

  /usr/local/bin/sb links > "$INFO_ENTRY"
  chmod 600 "$INFO_ENTRY"

  log ""
  log "Installed $NODE_PREFIX entry."
  log "Info: $INFO_ENTRY"
  log "Manager: sb"
  log "Add SS landing: sb add-ss 'ss://...'"
  log "Firewall: inbound TCP 443 only."
}

ss_uri() {
  python3 - <<PY
import base64
from urllib.parse import quote
method = "${SS_METHOD}"
password = "${SS_PASSWORD}"
host = "${ACCESS_HOST}"
port = "${SS_PORT}"
name = "${HOME_NAME}-SS"
raw = f"{method}:{password}@{host}:{port}"
enc = base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")
print(f"ss://{enc}#{quote(name)}")
PY
}

ss_uri_editable() {
  python3 - <<PY
from urllib.parse import quote
method = "${SS_METHOD}"
password = "${SS_PASSWORD}"
host = "${ACCESS_HOST}"
port = "${SS_PORT}"
name = "${HOME_NAME}-SS"
print(f"ss://{method}:{quote(password, safe='')}@{host}:{port}#{quote(name)}")
PY
}

write_home_config() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  cat > "$CONFIG_PATH" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [{ "type": "local", "tag": "dns_local" }],
    "final": "dns_local",
    "strategy": "prefer_ipv4"
  },
  "inbounds": [{
    "type": "shadowsocks",
    "tag": "ss-in",
    "listen": "::",
    "listen_port": ${SS_PORT},
    "method": "${SS_METHOD}",
    "password": "${SS_PASSWORD}",
    "network": "tcp"
  }],
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "default_domain_resolver": "dns_local",
    "auto_detect_interface": true,
    "final": "direct"
  }
}
EOF
  chmod 600 "$CONFIG_PATH"
}

write_home_manager() {
  cat > /usr/local/bin/sb <<'EOF'
#!/usr/bin/env sh
set -eu
case "${1:-menu}" in
  info)
    cat /root/singbox-home-info.txt
    ;;
  restart)
    if command -v systemctl >/dev/null 2>&1; then systemctl restart sing-box; else rc-service sing-box restart; fi
    ;;
  status)
    if command -v systemctl >/dev/null 2>&1; then systemctl status sing-box --no-pager; else rc-service sing-box status; fi
    ;;
  menu|*)
    echo "Home sing-box manager"
    echo "1. Show SS link / 查看 SS 链接"
    echo "2. Restart / 重启"
    echo "3. Status / 状态"
    echo "0. Exit"
    printf "Choose: "
    read -r c
    case "$c" in
      1) cat /root/singbox-home-info.txt ;;
      2) "$0" restart ;;
      3) "$0" status ;;
      0) exit 0 ;;
    esac
    ;;
esac
EOF
  chmod 700 /usr/local/bin/sb
}

install_home() {
  install_deps
  install_singbox

  HOME_NAME="$(ask "Home node name" "home")"
  ACCESS_HOST="$(ask "Public IP/domain for ss link" "$(public_ip)")"
  SS_PORT="$(ask "SS listen/public port" "443")"
  SS_METHOD="${SS_METHOD:-2022-blake3-aes-256-gcm}"
  SS_PASSWORD="${SS_PASSWORD:-$(random_ss2022_password)}"

  write_home_config
  check_config
  if [ "$OS_FAMILY" = "debian" ]; then
    write_systemd_service
  else
    write_openrc_service
  fi
  write_home_manager

  {
    echo "Home SS landing installed"
    echo "========================="
    echo "name: $HOME_NAME"
    echo "server: $ACCESS_HOST"
    echo "port: $SS_PORT"
    echo "method: $SS_METHOD"
    echo "password: $SS_PASSWORD"
    echo
    echo "ss_link:"
    ss_uri
    echo
    echo "ss_link_editable:"
    ss_uri_editable
    echo
    echo "Paste ss_link into DMIT/HK:"
    echo "  sb add-ss 'ss://...'"
  } > "$INFO_HOME"
  chmod 600 "$INFO_HOME"

  log ""
  log "Installed home SS landing."
  log "Info: $INFO_HOME"
  log "Manager: sb"
}

print_menu() {
  log ""
  log "Smart sing-box simplified installer"
  log "1. DMIT Debian entry / DMIT 主力入口"
  log "2. HK Debian entry / HK 国际互连入口"
  log "3. Home landing / 家宽 SS 落地"
  log "4. Add ss:// to this entry / 给当前入口添加落地"
  log "0. Exit"
  log ""
}

main() {
  need_root
  need_tty
  detect_os
  print_menu > /dev/tty
  choice="$(ask "Choose" "")"
  case "$choice" in
    1) install_entry dmit ;;
    2) install_entry hk ;;
    3) install_home ;;
    4)
      [ -x /usr/local/bin/sb ] || die "sb manager not found. Install DMIT/HK entry first."
      link="$(ask "Paste ss:// link" "")"
      /usr/local/bin/sb add-ss "$link"
      ;;
    0) exit 0 ;;
    *) die "Invalid choice: $choice" ;;
  esac
}

main "$@"
