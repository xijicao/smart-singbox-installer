#!/usr/bin/env sh
set -eu

CONFIG_DIR="/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
META_PATH="${CONFIG_DIR}/entry.env"
HOME_META_PATH="${CONFIG_DIR}/home.env"
INFO_ENTRY="/root/singbox-entry-info.txt"
INFO_HOME="/root/singbox-home-info.txt"
BACKUP_DIR="/etc/sing-box/backups"

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
      apk add --no-cache bash curl ca-certificates openssl python3 openrc iproute2 netcat-openbsd
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

safe_label() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9_.-' '-' | sed 's/^-*//;s/-*$//' | cut -c1-32
}

validate_port() {
  name="$1"
  port="$2"
  case "$port" in
    ''|*[!0-9]*) die "$name must be a TCP port number." ;;
  esac
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "$name must be between 1 and 65535."
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
User=root
WorkingDirectory=${CONFIG_DIR}
ExecStartPre=${SINGBOX_BIN} check -c ${CONFIG_PATH}
ExecStart=${SINGBOX_BIN} run -c ${CONFIG_PATH}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

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

enable_entry_firewall() {
  [ "$OS_FAMILY" = "debian" ] || return 0

  current_ssh_port="$(printf '%s' "${SSH_CONNECTION:-}" | awk '{print $4}')"
  if [ "${FORCE_ENTRY_FIREWALL:-0}" != "1" ] && [ "$current_ssh_port" != "$SSH_PORT" ]; then
    log ""
    log "WARNING: DMIT/HK firewall will allow inbound TCP 443 and TCP ${SSH_PORT} only."
    log "Current SSH server port looks like: ${current_ssh_port:-unknown}."
    log "Please move SSH to TCP ${SSH_PORT} before enabling this firewall."
    printf "Type ENTRYFW to continue anyway: " > /dev/tty
    read -r confirm < /dev/tty
    [ "$confirm" = "ENTRYFW" ] || die "Cancelled firewall setup."
  elif [ "${FORCE_ENTRY_FIREWALL:-0}" != "1" ]; then
    log ""
    log "WARNING: This will enable the entry firewall."
    log "Inbound TCP 443 is for sing-box Reality."
    log "Inbound TCP ${SSH_PORT} is for SSH."
    log "Make sure you have provider console/rescue access before continuing."
    printf "Type ENTRYFW to continue: " > /dev/tty
    read -r confirm < /dev/tty
    [ "$confirm" = "ENTRYFW" ] || die "Cancelled firewall setup."
  fi

  cat > /etc/nftables.conf <<EOF
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;

    ct state established,related accept
    iif lo accept
    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept
    tcp dport ${SSH_PORT} accept
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
        "short_id": ["$ME_SID"]
      }
    }
  }],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_resolver": {
        "server": "dns_local",
        "strategy": "prefer_ipv4"
      }
    },
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
    backup_dir = Path("/etc/sing-box/backups")
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / f"config.{reason}.{ts}.json"
    shutil.copy2(CONFIG, backup)
    if META.exists():
        shutil.copy2(META, backup_dir / f"entry.{reason}.{ts}.env")
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

def manual_backup(reason="manual"):
    ts = time.strftime("%Y%m%d%H%M%S")
    backup_dir = Path("/etc/sing-box/backups")
    backup_dir.mkdir(parents=True, exist_ok=True)
    cfg_backup = backup_dir / f"config.{reason}.{ts}.json"
    shutil.copy2(CONFIG, cfg_backup)
    if META.exists():
        shutil.copy2(META, backup_dir / f"entry.{reason}.{ts}.env")
    print(f"Backup: {cfg_backup}")
    return cfg_backup

def restore_latest():
    backup_dir = Path("/etc/sing-box/backups")
    backups = sorted(backup_dir.glob("config.*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not backups:
        raise SystemExit("No config backup found.")
    latest = backups[0]
    current = manual_backup("before-restore")
    shutil.copy2(latest, CONFIG)
    os.chmod(CONFIG, 0o600)
    try:
        subprocess.check_call(["sing-box", "check", "-c", str(CONFIG)])
        restart()
    except Exception:
        shutil.copy2(current, CONFIG)
        restart()
        raise SystemExit(f"Restore failed. Rolled back: {current}")
    print(f"Restored: {latest}")

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
        "network": "tcp",
        "domain_resolver": {
            "server": "dns_local",
            "strategy": "prefer_ipv4"
        }
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
    relays = []
    for user in ib.get("users", []):
        name = user.get("name", "")
        if name.startswith("relay-"):
            relays.append(name)
    if not relays:
        print("No relay nodes.")
        return []
    for i, name in enumerate(relays, 1):
        print(f"{i}. {name}")
    return relays

def choose_relay():
    relays = list_relays()
    if not relays:
        return None
    choice = input("Relay name or number: ").strip()
    if choice.isdigit() and 1 <= int(choice) <= len(relays):
        return relays[int(choice) - 1]
    return choice

def status_test():
    print("== sing-box version ==")
    subprocess.call(["sing-box", "version"])
    print("\n== config check ==")
    subprocess.call(["sing-box", "check", "-c", str(CONFIG)])
    print("\n== service status ==")
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "is-active", "sing-box"])
        subprocess.call(["systemctl", "status", "sing-box", "--no-pager", "-l"])
    elif shutil.which("rc-service"):
        subprocess.call(["rc-service", "sing-box", "status"])
    print("\n== listen ports ==")
    if shutil.which("ss"):
        subprocess.call(["ss", "-lntp"])
    elif shutil.which("netstat"):
        subprocess.call(["netstat", "-lntp"])

def uninstall_entry():
    confirm = input("Type UNINSTALL_ENTRY to remove entry install: ").strip()
    if confirm != "UNINSTALL_ENTRY":
        print("Cancelled.")
        return
    ts = time.strftime("%Y%m%d%H%M%S")
    archive = f"/root/singbox-entry-uninstall-backup-{ts}.tar.gz"
    subprocess.call([
        "tar", "-czf", archive,
        "/etc/sing-box",
        "/root/singbox-entry-info.txt",
        "/usr/local/bin/sb",
        "/etc/systemd/system/sing-box.service",
        "/etc/nftables.conf",
    ], stderr=subprocess.DEVNULL)
    try:
        os.chmod(archive, 0o600)
    except OSError:
        pass
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "stop", "sing-box"])
        subprocess.call(["systemctl", "disable", "sing-box"])
        Path("/etc/systemd/system/sing-box.service").unlink(missing_ok=True)
        subprocess.call(["systemctl", "daemon-reload"])
    shutil.rmtree("/etc/sing-box", ignore_errors=True)
    subprocess.call(["rm", "-f", "/usr/local/bin/sb"])
    subprocess.call(["rm", "-f", "/root/singbox-entry-info.txt"])
    print(f"Entry install removed. Backup: {archive}")
    print("nftables config is backed up but not disabled, so your SSH allow rule remains protected.")

def purge_entry():
    confirm = input("Type PURGE_ENTRY to remove entry install WITHOUT backup: ").strip()
    if confirm != "PURGE_ENTRY":
        print("Cancelled.")
        return
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "stop", "sing-box"])
        subprocess.call(["systemctl", "disable", "sing-box"])
        Path("/etc/systemd/system/sing-box.service").unlink(missing_ok=True)
        subprocess.call(["systemctl", "daemon-reload"])
    shutil.rmtree("/etc/sing-box", ignore_errors=True)
    subprocess.call(["rm", "-f", "/usr/local/bin/sb"])
    subprocess.call(["rm", "-f", "/root/singbox-entry-info.txt"])
    print("Entry install purged without backup.")
    print("nftables was not disabled. If needed, edit /etc/nftables.conf manually or run: systemctl disable --now nftables")

def menu():
    while True:
        print()
        print("sing-box entry manager")
        print("1. Add SS landing link")
        print("2. Delete relay")
        print("3. List relay nodes")
        print("4. Show all Reality links")
        print("5. Add direct friend")
        print("6. Delete user")
        print("7. Restart sing-box")
        print("8. Test status")
        print("9. Backup config")
        print("10. Restore latest backup")
        print("11. Uninstall entry")
        print("12. Purge entry without backup")
        print("0. Exit")
        choice = input("Choose: ").strip()
        if choice == "1":
            add_ss(input("Paste ss:// link: ").strip())
        elif choice == "2":
            relay = choose_relay()
            if relay:
                del_user(relay, relay_only=True)
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
        elif choice == "8":
            status_test()
        elif choice == "9":
            manual_backup()
        elif choice == "10":
            restore_latest()
        elif choice == "11":
            uninstall_entry()
        elif choice == "12":
            purge_entry()
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
    elif cmd == "test":
        status_test()
    elif cmd == "backup":
        manual_backup()
    elif cmd == "restore-latest":
        restore_latest()
    elif cmd == "uninstall":
        uninstall_entry()
    elif cmd == "purge":
        purge_entry()
    else:
        print("Usage: sb [add-ss|del-relay|list-relays|links|add-friend|del-user|restart|test|backup|restore-latest|uninstall|purge]")
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
  SSH_PORT="$(ask "SSH port to allow in firewall" "${SSH_PORT:-51398}")"
  validate_port "SSH port" "$SSH_PORT"
  ME_UUID="$(random_uuid)"
  ME_SID="$(random_hex8)"
  reality_keypair

  entry_config
  write_entry_meta
  check_config
  write_systemd_service
  write_entry_manager
  enable_entry_firewall

  /usr/local/bin/sb links > "$INFO_ENTRY"
  chmod 600 "$INFO_ENTRY"

  log ""
  log "Installed $NODE_PREFIX entry."
  log "Info: $INFO_ENTRY"
  log "Manager: sb"
  log "Add SS landing: sb add-ss 'ss://...'"
  log "Firewall: inbound TCP 443 and TCP ${SSH_PORT} only."
}

ss_uri() {
  python3 - <<PY
import base64
from urllib.parse import quote
method = "${SS_METHOD}"
password = "${SS_PASSWORD}"
host = "${ACCESS_HOST}"
port = "${SS_PUBLIC_PORT}"
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
port = "${SS_PUBLIC_PORT}"
name = "${HOME_NAME}-SS"
print(f"ss://{method}:{quote(password, safe='')}@{host}:{port}#{quote(name)}")
PY
}

reality_uri() {
  python3 - <<PY
from urllib.parse import quote
host = "${ACCESS_HOST}"
port = "${REALITY_PUBLIC_PORT}"
name = "${HOME_NAME}-Reality"
uuid = "${REALITY_UUID}"
sni = "${REALITY_SNI}"
pbk = "${REALITY_PUBLIC_KEY}"
sid = "${REALITY_SID}"
print(f"vless://{uuid}@{host}:{port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={sni}&fp=chrome&pbk={pbk}&sid={sid}&type=tcp&headerType=none#{quote(name)}")
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
  "inbounds": [
EOF

  sep=""
  if [ "$HOME_MODE" = "ss2022" ] || [ "$HOME_MODE" = "both" ]; then
    cat >> "$CONFIG_PATH" <<EOF
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "::",
      "listen_port": ${SS_PORT},
      "method": "${SS_METHOD}",
      "password": "${SS_PASSWORD}",
      "network": "tcp"
    }
EOF
    sep=","
  fi

  if [ "$HOME_MODE" = "reality" ] || [ "$HOME_MODE" = "both" ]; then
    [ -n "$sep" ] && printf ',\n' >> "$CONFIG_PATH"
    cat >> "$CONFIG_PATH" <<EOF
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "users": [{
        "uuid": "${REALITY_UUID}",
        "flow": "xtls-rprx-vision"
      }],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SNI}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${REALITY_SNI}", "server_port": 443 },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": ["${REALITY_SID}"]
        }
      }
    }
EOF
  fi

  cat >> "$CONFIG_PATH" <<EOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "domain_resolver": {
        "server": "dns_local",
        "strategy": "prefer_ipv4"
      }
    },
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
CONFIG_PATH="/etc/sing-box/config.json"
HOME_META_PATH="/etc/sing-box/home.env"
INFO_HOME="/root/singbox-home-info.txt"

load_meta() {
  [ -r "$HOME_META_PATH" ] || { echo "Missing $HOME_META_PATH" >&2; exit 1; }
  . "$HOME_META_PATH"
}

restart_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sing-box
  else
    rc-service sing-box restart
  fi
}

status_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl status sing-box --no-pager
  else
    rc-service sing-box status
  fi
}

write_info() {
  load_meta
  python3 - <<PY > "$INFO_HOME"
import base64
from urllib.parse import quote
name = "${HOME_NAME}"
mode = "${HOME_MODE}"
host = "${ACCESS_HOST}"
print("Home SS landing installed")
print("=========================")
print(f"name: {name}")
print(f"mode: {mode}")
print(f"server: {host}")
if mode in ("ss2022", "both"):
    inside_port = "${SS_PORT}"
    public_port = "${SS_PUBLIC_PORT}"
    method = "${SS_METHOD}"
    password = "${SS_PASSWORD}"
    raw = f"{method}:{password}@{host}:{public_port}"
    enc = base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")
    print()
    print("SS2022 landing")
    print("--------------")
    print(f"listen_port_inside_server: {inside_port}")
    print(f"public_port_for_dmit_hk: {public_port}")
    print(f"method: {method}")
    print(f"password: {password}")
    print()
    print("ss_link:")
    print(f"ss://{enc}#{quote(name + '-SS')}")
    print()
    print("ss_link_editable:")
    print(f"ss://{method}:{quote(password, safe='')}@{host}:{public_port}#{quote(name + '-SS')}")
    print()
    print("Paste ss_link into DMIT/HK:")
    print("  sb add-ss 'ss://...'")
if mode in ("reality", "both"):
    uuid = "${REALITY_UUID}"
    inside_port = "${REALITY_PORT}"
    public_port = "${REALITY_PUBLIC_PORT}"
    sni = "${REALITY_SNI}"
    pbk = "${REALITY_PUBLIC_KEY}"
    sid = "${REALITY_SID}"
    print()
    print("Reality direct")
    print("--------------")
    print(f"listen_port_inside_server: {inside_port}")
    print(f"public_port_for_client: {public_port}")
    print(f"sni: {sni}")
    print(f"public_key: {pbk}")
    print(f"uuid: {uuid}")
    print(f"short_id: {sid}")
    print()
    print("reality_link:")
    print(f"vless://{uuid}@{host}:{public_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={sni}&fp=chrome&pbk={pbk}&sid={sid}&type=tcp&headerType=none#{quote(name + '-Reality')}")
PY
  chmod 600 "$INFO_HOME"
}

reset_ss() {
  load_meta
  if [ "${HOME_MODE:-ss2022}" = "reality" ]; then
    echo "This home install has no SS2022 inbound." >&2
    exit 1
  fi
  new_password="$(openssl rand -base64 32 | tr -d '\n\r')"
  backup="/etc/sing-box/config.json.bak.reset-ss.$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG_PATH" "$backup"
  SS_PASSWORD="$new_password" python3 - <<'PY'
import json, os
path = "/etc/sing-box/config.json"
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)
for inbound in cfg.get("inbounds", []):
    if inbound.get("type") == "shadowsocks" and inbound.get("tag") == "ss-in":
        inbound["password"] = os.environ["SS_PASSWORD"]
with open(path + ".tmp", "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.chmod(path + ".tmp", 0o600)
os.replace(path + ".tmp", path)
PY
  if ! sing-box check -c "$CONFIG_PATH"; then
    cp "$backup" "$CONFIG_PATH"
    echo "Config check failed. Rolled back: $backup" >&2
    exit 1
  fi
  cat > "$HOME_META_PATH" <<META
HOME_NAME="${HOME_NAME}"
HOME_MODE="${HOME_MODE}"
ACCESS_HOST="${ACCESS_HOST}"
SS_PORT="${SS_PORT}"
SS_PUBLIC_PORT="${SS_PUBLIC_PORT}"
SS_METHOD="${SS_METHOD}"
SS_PASSWORD="${new_password}"
REALITY_PORT="${REALITY_PORT:-}"
REALITY_PUBLIC_PORT="${REALITY_PUBLIC_PORT:-}"
REALITY_SNI="${REALITY_SNI:-}"
REALITY_UUID="${REALITY_UUID:-}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
REALITY_SID="${REALITY_SID:-}"
META
  chmod 600 "$HOME_META_PATH"
  restart_service
  write_info
  echo "SS password reset."
  echo "New info: $INFO_HOME"
}

test_status() {
  echo "== sing-box version =="
  sing-box version || true
  echo
  echo "== config check =="
  sing-box check -c "$CONFIG_PATH" || true
  echo
  echo "== service status =="
  status_service || true
  echo
  echo "== listen ports =="
  if command -v ss >/dev/null 2>&1; then
    ss -lntp || true
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntp || true
  fi
}

uninstall_home() {
  printf "Type UNINSTALL_HOME to remove home install: "
  read -r confirm
  [ "$confirm" = "UNINSTALL_HOME" ] || { echo "Cancelled."; exit 0; }
  backup="/root/singbox-home-uninstall-backup-$(date +%Y%m%d%H%M%S).tar.gz"
  tar -czf "$backup" /etc/sing-box /root/singbox-home-info.txt /usr/local/bin/sb 2>/dev/null || true
  chmod 600 "$backup" 2>/dev/null || true
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload 2>/dev/null || true
  else
    rc-service sing-box stop 2>/dev/null || true
    rc-update del sing-box default 2>/dev/null || true
    rm -f /etc/init.d/sing-box
  fi
  rm -rf /etc/sing-box
  rm -f /root/singbox-home-info.txt
  rm -f /usr/local/bin/sb
  echo "Home install removed. Backup: $backup"
}

purge_home() {
  printf "Type PURGE_HOME to remove home install WITHOUT backup: "
  read -r confirm
  [ "$confirm" = "PURGE_HOME" ] || { echo "Cancelled."; exit 0; }
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload 2>/dev/null || true
  else
    rc-service sing-box stop 2>/dev/null || true
    rc-update del sing-box default 2>/dev/null || true
    rm -f /etc/init.d/sing-box
  fi
  rm -rf /etc/sing-box
  rm -f /root/singbox-home-info.txt
  rm -f /usr/local/bin/sb
  echo "Home install purged without backup."
}

case "${1:-menu}" in
  info)
    write_info
    cat "$INFO_HOME"
    ;;
  refresh-info)
    write_info
    ;;
  restart)
    restart_service
    ;;
  status)
    status_service
    ;;
  test)
    test_status
    ;;
  reset-ss)
    reset_ss
    ;;
  uninstall)
    uninstall_home
    ;;
  purge)
    purge_home
    ;;
  menu|*)
    echo "Home sing-box manager"
    echo "1. Show SS link"
    echo "2. Restart"
    echo "3. Status"
    echo "4. Test"
    echo "5. Reset SS password"
    echo "6. Uninstall home install"
    echo "7. Purge home install without backup"
    echo "0. Exit"
    printf "Choose: "
    read -r c
    case "$c" in
      1) cat "$INFO_HOME" ;;
      2) "$0" restart ;;
      3) "$0" status ;;
      4) "$0" test ;;
      5) "$0" reset-ss ;;
      6) "$0" uninstall ;;
      7) "$0" purge ;;
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

  raw_home_name="$(ask "Home node name" "home")"
  HOME_NAME="$(safe_label "$raw_home_name")"
  [ -n "$HOME_NAME" ] || HOME_NAME="home"
  log "Home install mode:"
  log "1. SS2022 landing only"
  log "2. Reality direct only"
  log "3. SS2022 landing + Reality direct"
  mode_choice="$(ask "Choose mode" "1")"
  case "$mode_choice" in
    1) HOME_MODE="ss2022" ;;
    2) HOME_MODE="reality" ;;
    3) HOME_MODE="both" ;;
    ss2022|reality|both) HOME_MODE="$mode_choice" ;;
    *) die "Invalid home mode: $mode_choice" ;;
  esac

  ACCESS_HOST="$(ask "Public IP/domain for exported links" "$(public_ip)")"

  if [ "$HOME_MODE" = "ss2022" ] || [ "$HOME_MODE" = "both" ]; then
    SS_DEFAULT_PORT="443"
    SS_PORT="$(ask "SS internal listen port" "$SS_DEFAULT_PORT")"
    SS_PUBLIC_PORT="$(ask "SS public mapped port" "$SS_PORT")"
    validate_port "SS internal listen port" "$SS_PORT"
    validate_port "SS public mapped port" "$SS_PUBLIC_PORT"
    SS_METHOD="${SS_METHOD:-2022-blake3-aes-256-gcm}"
    SS_PASSWORD="${SS_PASSWORD:-$(random_ss2022_password)}"
  else
    SS_PORT=""
    SS_PUBLIC_PORT=""
    SS_METHOD=""
    SS_PASSWORD=""
  fi

  if [ "$HOME_MODE" = "reality" ] || [ "$HOME_MODE" = "both" ]; then
    if [ "$HOME_MODE" = "both" ]; then
      REALITY_DEFAULT_PORT="8443"
    else
      REALITY_DEFAULT_PORT="443"
    fi
    REALITY_PORT="$(ask "Reality internal listen port" "$REALITY_DEFAULT_PORT")"
    REALITY_PUBLIC_PORT="$(ask "Reality public mapped port" "$REALITY_PORT")"
    validate_port "Reality internal listen port" "$REALITY_PORT"
    validate_port "Reality public mapped port" "$REALITY_PUBLIC_PORT"
    REALITY_SNI="$(ask "Reality SNI" "${REALITY_SNI:-www.sony.jp}")"
    REALITY_UUID="$(random_uuid)"
    REALITY_SID="$(random_hex8)"
    reality_keypair
  else
    REALITY_PORT=""
    REALITY_PUBLIC_PORT=""
    REALITY_SNI=""
    REALITY_UUID=""
    REALITY_PUBLIC_KEY=""
    REALITY_PRIVATE_KEY=""
    REALITY_SID=""
  fi

  write_home_config
  cat > "$HOME_META_PATH" <<EOF
HOME_NAME="${HOME_NAME}"
HOME_MODE="${HOME_MODE}"
ACCESS_HOST="${ACCESS_HOST}"
SS_PORT="${SS_PORT}"
SS_PUBLIC_PORT="${SS_PUBLIC_PORT}"
SS_METHOD="${SS_METHOD}"
SS_PASSWORD="${SS_PASSWORD}"
REALITY_PORT="${REALITY_PORT}"
REALITY_PUBLIC_PORT="${REALITY_PUBLIC_PORT}"
REALITY_SNI="${REALITY_SNI}"
REALITY_UUID="${REALITY_UUID}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY}"
REALITY_SID="${REALITY_SID}"
EOF
  chmod 600 "$HOME_META_PATH"
  check_config
  if [ "$OS_FAMILY" = "debian" ]; then
    write_systemd_service
  else
    write_openrc_service
  fi
  write_home_manager

  /usr/local/bin/sb refresh-info

  log ""
  log "Installed home mode: $HOME_MODE"
  log "Info: $INFO_HOME"
  log "Manager: sb"
}

purge_current_install() {
  log ""
  log "This will remove current sing-box install WITHOUT backup."
  log "It removes service files, /etc/sing-box, /usr/local/bin/sb and info files."
  log "For DMIT/HK, nftables is NOT disabled automatically to avoid exposing SSH unexpectedly."
  printf "Type PURGE to continue: " > /dev/tty
  read -r confirm < /dev/tty
  [ "$confirm" = "PURGE" ] || die "Cancelled."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    rm -f /etc/systemd/system/sing-box.service
    systemctl daemon-reload 2>/dev/null || true
  fi

  if command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box stop 2>/dev/null || true
    rc-update del sing-box default 2>/dev/null || true
    rm -f /etc/init.d/sing-box
  fi

  rm -rf /etc/sing-box
  rm -f /usr/local/bin/sb
  rm -f /root/singbox-entry-info.txt /root/singbox-home-info.txt
  log "Purged current sing-box install without backup."
}

print_menu() {
  log ""
  log "Smart sing-box simplified installer"
  log "1. DMIT Debian entry"
  log "2. HK Debian entry"
  log "3. Home landing/direct"
  log "4. Add ss:// to this entry"
  log "5. Purge current install without backup"
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
    5) purge_current_install ;;
    0) exit 0 ;;
    *) die "Invalid choice: $choice" ;;
  esac
}

main "$@"
