#!/usr/bin/env sh
set -eu

CONFIG_DIR="/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"
META_PATH="${CONFIG_DIR}/entry.env"
HOME_META_PATH="${CONFIG_DIR}/home.env"
INFO_ENTRY="/root/singbox-entry-info.txt"
INFO_HOME="/root/singbox-home-info.txt"
BACKUP_DIR="/etc/sing-box/backups"
SB_BIN="/usr/local/bin/sing-box"
SB_MANAGER="/usr/local/bin/sb"
SYSTEMD_SERVICE="/etc/systemd/system/sing-box.service"
OPENRC_SERVICE="/etc/init.d/sing-box"
NFT_CONF="/etc/nftables.conf"
TC_SERVICE="/etc/systemd/system/tc-htb-fq.service"
STABLE_SYSCTL_CONF="/etc/sysctl.d/99-dmit-stable.conf"

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

ask_yes_no() {
  prompt="$1"
  default="${2:-n}"
  answer="$(ask "$prompt (y/n)" "$default")"
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
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

public_ipv4() {
  for u in https://api.ipify.org https://ipv4.icanhazip.com https://ifconfig.me/ip; do
    ip="$(curl -4 -fsSL --max-time 5 "$u" 2>/dev/null | tr -d '[:space:]' || true)"
    [ -n "$ip" ] && { printf '%s' "$ip"; return; }
  done
  printf 'YOUR_SERVER_IPV4'
}

public_ipv6() {
  for u in https://api64.ipify.org https://ipv6.icanhazip.com; do
    ip="$(curl -6 -fsSL --max-time 5 "$u" 2>/dev/null | tr -d '[:space:]' || true)"
    [ -n "$ip" ] && { printf '%s' "$ip"; return; }
  done
  printf 'YOUR_SERVER_IPV6'
}

ensure_clean_install() {
  if [ -e "$CONFIG_PATH" ] || [ -e "$SB_MANAGER" ]; then
    die "Existing sing-box install detected. Use 'sb uninstall' first, or 'sb update' to update only the manager."
  fi
}

detect_public_ipv6() {
  DETECTED_IPV6="$(public_ipv6)"
  case "$DETECTED_IPV6" in
    ''|YOUR_SERVER_IPV6) return 1 ;;
    *) return 0 ;;
  esac
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

check_config() {
  sing-box check -c "$CONFIG_PATH"
}

default_netdev() {
  ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

install_stable_net_profile() {
  [ "$OS_FAMILY" = "debian" ] || die "Stable network profile currently supports Debian/Ubuntu with systemd."
  command -v systemctl >/dev/null 2>&1 || die "Stable network profile requires systemd."

  profile="${1:-}"
  if [ -z "$profile" ]; then
    log "Network profile:"
    log "1. basic             BBR + fq + MTU probing, no HTB limit"
    log "2. dmit-safe         800mbit HTB + conservative TCP output limit"
    log "3. dmit-balanced     900mbit HTB + larger TCP output/buffer, recommended for DMIT"
    log "4. dmit-performance  1000mbit HTB + larger TCP output/buffer"
    log "5. dmit-ultra        1200mbit HTB + larger TCP output/buffer"
    log "6. custom            custom HTB rate + larger TCP output/buffer"
    profile="$(ask "Choose profile" "dmit-performance")"
    case "$profile" in
      1) profile="basic" ;;
      2) profile="dmit-safe" ;;
      3) profile="dmit-balanced" ;;
      4) profile="dmit-performance" ;;
      5) profile="dmit-ultra" ;;
      6) profile="custom" ;;
    esac
  fi

  case "$profile" in
    basic)
      rate=""
      limit="524288"
      buffer32="0"
      ;;
    dmit-safe|safe)
      profile="dmit-safe"
      rate="800mbit"
      limit="524288"
      buffer32="0"
      ;;
    dmit-balanced|balanced)
      profile="dmit-balanced"
      rate="900mbit"
      limit="1048576"
      buffer32="1"
      ;;
    dmit-performance|performance)
      profile="dmit-performance"
      rate="1000mbit"
      limit="1048576"
      buffer32="1"
      ;;
    dmit-ultra|ultra)
      profile="dmit-ultra"
      rate="1200mbit"
      limit="1048576"
      buffer32="1"
      ;;
    custom)
      rate="${2:-}"
      [ -n "$rate" ] || rate="$(ask "Custom HTB rate, for example 750mbit or 1gbit" "800mbit")"
      limit="1048576"
      buffer32="1"
      ;;
    *)
      die "Unknown network profile: $profile"
      ;;
  esac

  dev="${3:-}"
  if [ "$profile" != "custom" ] && [ -z "$dev" ]; then
    dev="${2:-}"
  fi
  [ -n "$dev" ] || dev="$(default_netdev)"
  [ -n "$dev" ] || die "Cannot detect default network interface. Pass interface name manually."

  cat > /etc/sysctl.d/99-dmit-stable.conf <<EOF
# smart-singbox network profile: ${profile}
# BBR + fq is the common low-latency TCP baseline.
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
# tcp_mtu_probing=1 helps avoid some MTU blackhole problems.
net.ipv4.tcp_mtu_probing=1
# Lower values are safer; higher values may improve throughput on stable lines.
net.ipv4.tcp_limit_output_bytes=${limit}
EOF
  if [ "$buffer32" = "1" ]; then
    cat >> /etc/sysctl.d/99-dmit-stable.conf <<'EOF'
# 32MB is the TCP autotuning ceiling, not fixed memory per connection.
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 16384 33554432
EOF
  fi
  sysctl --system

  if [ -z "$rate" ]; then
    systemctl disable --now tc-htb-fq.service 2>/dev/null || true
    rm -f /etc/systemd/system/tc-htb-fq.service
    systemctl daemon-reload 2>/dev/null || true
    log "Network profile ${profile} installed on ${dev}: BBR + fq, no HTB limit."
    stable_net_status "$dev"
    return
  fi

  if ! command -v tc >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y iproute2
  fi
  tc_bin="$(command -v tc)"
  [ -n "$tc_bin" ] || die "tc command not found after installing iproute2."

  cat > /etc/systemd/system/tc-htb-fq.service <<EOF
[Unit]
Description=${profile} HTB ${rate} limit with fq for ${dev}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${tc_bin} qdisc replace dev ${dev} root handle 1: htb default 10
ExecStart=${tc_bin} class replace dev ${dev} parent 1: classid 1:10 htb rate ${rate} ceil ${rate}
ExecStart=${tc_bin} qdisc replace dev ${dev} parent 1:10 handle 10: fq
ExecStop=${tc_bin} qdisc del dev ${dev} root

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now tc-htb-fq.service
  log "Network profile ${profile} installed on ${dev} with ${rate} HTB + fq."
  stable_net_status "$dev"
}

remove_stable_net_profile() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now tc-htb-fq.service 2>/dev/null || true
  fi
  rm -f /etc/systemd/system/tc-htb-fq.service
  rm -f /etc/sysctl.d/99-dmit-stable.conf
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
  fi
  sysctl --system || true
  log "Stable network profile removed."
  log "If temporary tuning was applied manually before, reboot to return every runtime value to OS defaults."
}

stable_net_status() {
  dev="${1:-}"
  [ -n "$dev" ] || dev="$(default_netdev)"
  [ -n "$dev" ] || dev="eth0"

  log "== sysctl =="
  sysctl net.core.default_qdisc || true
  sysctl net.ipv4.tcp_congestion_control || true
  sysctl net.ipv4.tcp_mtu_probing || true
  sysctl net.ipv4.tcp_limit_output_bytes || true
  sysctl net.core.rmem_max || true
  sysctl net.core.wmem_max || true
  sysctl net.ipv4.tcp_rmem || true
  sysctl net.ipv4.tcp_wmem || true
  log ""
  log "== tc qdisc (${dev}) =="
  tc -s qdisc show dev "$dev" || true
  log ""
  log "== tc class (${dev}) =="
  tc -s class show dev "$dev" || true
  log ""
  log "== service =="
  systemctl --no-pager --full status tc-htb-fq.service || true
}

enable_entry_firewall() {
  [ "$OS_FAMILY" = "debian" ] || return 0

  current_ssh_port="$(printf '%s' "${SSH_CONNECTION:-}" | awk '{print $4}')"
  if [ "${FORCE_ENTRY_FIREWALL:-0}" != "1" ] && [ "$current_ssh_port" != "$SSH_PORT" ]; then
    log ""
    log "WARNING: firewall will allow SSH TCP ${SSH_PORT}, enabled Reality TCP 443, and enabled SS2022 ports only."
    log "Current SSH server port looks like: ${current_ssh_port:-unknown}."
    log "Please move SSH to TCP ${SSH_PORT} before enabling this firewall."
    printf "Type OK to continue anyway: " > /dev/tty
    read -r confirm < /dev/tty
    [ "$confirm" = "OK" ] || die "Cancelled firewall setup."
  elif [ "${FORCE_ENTRY_FIREWALL:-0}" != "1" ]; then
    log ""
    log "WARNING: This will enable the entry firewall."
    [ "${ENABLE_REALITY:-1}" = "1" ] && log "Inbound TCP 443 is for sing-box Reality."
    [ "${ENABLE_SS:-0}" = "1" ] && log "Inbound TCP/UDP 8443 is for SS2022."
    log "Inbound TCP ${SSH_PORT} is for SSH."
    log "Make sure you have provider console/rescue access before continuing."
    printf "Type OK to continue: " > /dev/tty
    read -r confirm < /dev/tty
    [ "$confirm" = "OK" ] || die "Cancelled firewall setup."
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
EOF
  if [ "${ENABLE_REALITY:-1}" = "1" ]; then
    cat >> /etc/nftables.conf <<'EOF'
    tcp dport 443 accept
EOF
  fi
  if [ "${ENABLE_SS:-0}" = "1" ]; then
    cat >> /etc/nftables.conf <<'EOF'
    tcp dport 8443 accept
    udp dport 8443 accept
EOF
  fi
  cat >> /etc/nftables.conf <<'EOF'
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
  nft -c -f /etc/nftables.conf
  nft -f /etc/nftables.conf
  systemctl enable nftables
}

entry_config() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  export CONFIG_PATH REALITY_SNI REALITY_PRIVATE_KEY ENTRY_USERS ENTRY_UUIDS ENTRY_SIDS ENABLE_SS SS_METHOD SS_SERVER_PASSWORD SS_USER_PASSWORDS
  python3 - <<'PY'
import json, os

def split(name):
    return [x for x in os.environ.get(name, "").split(",") if x]

users = split("ENTRY_USERS")
uuids = split("ENTRY_UUIDS")
sids = split("ENTRY_SIDS")
ss_passwords = split("SS_USER_PASSWORDS")

cfg = {
    "log": {"level": "warn", "timestamp": True},
    "dns": {
        "servers": [{"type": "local", "tag": "dns_local"}],
        "final": "dns_local",
        "strategy": "prefer_ipv4",
    },
    "inbounds": [{
        "type": "vless",
        "tag": "reality-in",
        "listen": "::",
        "listen_port": 443,
        "users": [
            {"name": name, "uuid": uuids[i], "flow": "xtls-rprx-vision"}
            for i, name in enumerate(users)
        ],
        "tls": {
            "enabled": True,
            "server_name": os.environ["REALITY_SNI"],
            "reality": {
                "enabled": True,
                "handshake": {"server": os.environ["REALITY_SNI"], "server_port": 443},
                "private_key": os.environ["REALITY_PRIVATE_KEY"],
                "short_id": sids,
            },
        },
    }],
    "outbounds": [
        {"type": "direct", "tag": "direct", "domain_resolver": {"server": "dns_local"}},
        {"type": "block", "tag": "block"},
    ],
    "route": {
        "default_domain_resolver": "dns_local",
        "auto_detect_interface": True,
        "rules": [],
        "final": "direct",
    },
}

if os.environ.get("ENABLE_SS") == "1":
    cfg["inbounds"].append({
        "type": "shadowsocks",
        "tag": "ss-in",
        "listen": "::",
        "listen_port": 8443,
        "method": os.environ.get("SS_METHOD", "2022-blake3-aes-128-gcm"),
        "password": os.environ["SS_SERVER_PASSWORD"],
        "users": [
            {"name": name, "password": ss_passwords[i]}
            for i, name in enumerate(users)
        ],
    })

with open(os.environ["CONFIG_PATH"], "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
  chmod 600 "$CONFIG_PATH"
}

write_entry_meta() {
  cat > "$META_PATH" <<EOF
NODE_ROLE="$NODE_ROLE"
NODE_PREFIX="$NODE_PREFIX"
ACCESS_HOST="$ACCESS_HOST"
SS_ACCESS_HOST="${SS_ACCESS_HOST:-}"
ENABLE_SS="${ENABLE_SS:-0}"
SS_METHOD="${SS_METHOD:-}"
SS_SERVER_PASSWORD="${SS_SERVER_PASSWORD:-}"
REALITY_SNI="$REALITY_SNI"
REALITY_PUBLIC_KEY="$REALITY_PUBLIC_KEY"
REALITY_PRIVATE_KEY="$REALITY_PRIVATE_KEY"
EOF
  chmod 600 "$META_PATH"
}

write_entry_manager() {
  cat > /usr/local/bin/sb <<'PYEOF'
#!/usr/bin/env python3
import base64, json, os, re, shutil, subprocess, sys, tempfile, time, uuid
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
        if right.startswith("["):
            host, port = right.rsplit("]:", 1)
            host = host[1:]
        else:
            host, port = right.rsplit(":", 1)
    else:
        decoded = b64decode_any(body)
        left, right = decoded.rsplit("@", 1)
        method, password = left.split(":", 1)
        if right.startswith("["):
            host, port = right.rsplit("]:", 1)
            host = host[1:]
        else:
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

def display_host(host):
    if ":" in host and not host.startswith("["):
        return f"[{host}]"
    return host

def ss_link_for_user(name, user):
    meta = load_meta()
    host = display_host(meta.get("SS_ACCESS_HOST") or meta.get("ACCESS_HOST", "YOUR_SERVER_IP"))
    method = meta.get("SS_METHOD", "2022-blake3-aes-128-gcm")
    server_password = meta.get("SS_SERVER_PASSWORD", "")
    prefix = meta.get("NODE_PREFIX", "ENTRY")
    user_password = user.get("password", "")
    raw = f"{method}:{server_password}:{user_password}"
    encoded = base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")
    return f"ss://{encoded}@{host}:8443#{quote(prefix + '-SS-' + name)}"

def list_links():
    cfg = load_cfg()
    ib = inbound(cfg)
    sids = ib.get("tls", {}).get("reality", {}).get("short_id", [])
    users = ib.get("users", [])
    print("===== Reality =====")
    for i, user in enumerate(users):
        name = user.get("name", f"user{i+1}")
        sid = sids[i] if i < len(sids) else (sids[0] if sids else "")
        print()
        print(name)
        print(link_for_user(name, user, sid))
    for item in cfg.get("inbounds", []):
        if item.get("type") == "shadowsocks" and item.get("tag") == "ss-in":
            print()
            print("===== SS2022 =====")
            for user in item.get("users", []):
                name = user.get("name", "user")
                print()
                print(name)
                print(ss_link_for_user(name, user))
            break

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

    ss_user = None
    for item in cfg.get("inbounds", []):
        if item.get("type") == "shadowsocks" and item.get("tag") == "ss-in":
            ss_user = {
                "name": name,
                "password": base64.urlsafe_b64encode(os.urandom(16)).decode().rstrip("="),
            }
            item.setdefault("users", []).append(ss_user)
            break

    save_cfg(cfg, "add-friend")
    print("Reality:")
    print(link_for_user(name, user, sid))
    if ss_user:
        print("\nSS2022:")
        print(ss_link_for_user(name, ss_user))

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
    for item in cfg.get("inbounds", []):
        if item.get("type") == "shadowsocks" and item.get("tag") == "ss-in":
            item["users"] = [u for u in item.get("users", []) if u.get("name") != name]
            break
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
            "server": "dns_local"
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
        subprocess.call(["ss", "-lntup"])
    elif shutil.which("netstat"):
        subprocess.call(["netstat", "-lntup"])

def update_manager():
    url = "https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh"
    with tempfile.NamedTemporaryFile(prefix="smart-singbox-", suffix=".sh", delete=False) as f:
        script = f.name
    try:
        subprocess.check_call(["curl", "-fsSL", url, "-o", script])
        subprocess.check_call(["bash", script, "update-manager"])
    finally:
        Path(script).unlink(missing_ok=True)

def default_netdev():
    try:
        out = subprocess.check_output(["ip", "route", "get", "1.1.1.1"], text=True, stderr=subprocess.DEVNULL)
        parts = out.split()
        if "dev" in parts:
            return parts[parts.index("dev") + 1]
    except Exception:
        pass
    return "eth0"

def install_stable_net_profile(profile=None, rate=None, dev=None):
    if not shutil.which("systemctl"):
        raise SystemExit("Stable network profile requires systemd.")

    valid_profiles = {
        "basic": ("", "524288", False),
        "dmit-safe": ("800mbit", "524288", False),
        "safe": ("800mbit", "524288", False),
        "dmit-balanced": ("900mbit", "1048576", True),
        "balanced": ("900mbit", "1048576", True),
        "dmit-performance": ("1000mbit", "1048576", True),
        "performance": ("1000mbit", "1048576", True),
        "dmit-ultra": ("1200mbit", "1048576", True),
        "ultra": ("1200mbit", "1048576", True),
    }
    if profile and profile not in valid_profiles and profile != "custom" and dev is None:
        dev = profile
        profile = None
    if not profile:
        print("Network profile:")
        print("1. basic             BBR + fq + MTU probing, no HTB limit")
        print("2. dmit-safe         800mbit HTB + conservative TCP output limit")
        print("3. dmit-balanced     900mbit HTB + larger TCP output/buffer, recommended for DMIT")
        print("4. dmit-performance  1000mbit HTB + larger TCP output/buffer")
        print("5. dmit-ultra        1200mbit HTB + larger TCP output/buffer")
        print("6. custom            custom HTB rate + larger TCP output/buffer")
        profile = input("Choose profile [dmit-performance]: ").strip() or "dmit-performance"
        profile = {
            "1": "basic",
            "2": "dmit-safe",
            "3": "dmit-balanced",
            "4": "dmit-performance",
            "5": "dmit-ultra",
            "6": "custom",
        }.get(profile, profile)

    if profile == "custom":
        rate = rate or input("Custom HTB rate, for example 750mbit or 1gbit [800mbit]: ").strip() or "800mbit"
        limit = "1048576"
        buffer32 = True
    else:
        if profile not in valid_profiles:
            raise SystemExit(f"Unknown network profile: {profile}")
        if rate and dev is None:
            dev = rate
        rate, limit, buffer32 = valid_profiles[profile]
        if profile == "safe":
            profile = "dmit-safe"
        elif profile == "balanced":
            profile = "dmit-balanced"
        elif profile == "performance":
            profile = "dmit-performance"

    dev = dev or default_netdev()

    sysctl_text = (
        f"# smart-singbox network profile: {profile}\n"
        "# BBR + fq is the common low-latency TCP baseline.\n"
        "net.core.default_qdisc=fq\n"
        "net.ipv4.tcp_congestion_control=bbr\n"
        "# tcp_mtu_probing=1 helps avoid some MTU blackhole problems.\n"
        "net.ipv4.tcp_mtu_probing=1\n"
        "# Lower values are safer; higher values may improve throughput on stable lines.\n"
        f"net.ipv4.tcp_limit_output_bytes={limit}\n"
    )
    if buffer32:
        sysctl_text += (
            "# 32MB is the TCP autotuning ceiling, not fixed memory per connection.\n"
            "net.core.rmem_max=33554432\n"
            "net.core.wmem_max=33554432\n"
            "net.ipv4.tcp_rmem=4096 87380 33554432\n"
            "net.ipv4.tcp_wmem=4096 16384 33554432\n"
        )
    Path("/etc/sysctl.d/99-dmit-stable.conf").write_text(sysctl_text, encoding="utf-8")
    subprocess.call(["sysctl", "--system"])

    if not rate:
        if shutil.which("systemctl"):
            subprocess.call(["systemctl", "disable", "--now", "tc-htb-fq.service"], stderr=subprocess.DEVNULL)
        Path("/etc/systemd/system/tc-htb-fq.service").unlink(missing_ok=True)
        subprocess.call(["systemctl", "daemon-reload"])
        print(f"Network profile {profile} installed on {dev}: BBR + fq, no HTB limit.")
        stable_net_status(dev)
        return

    tc_bin = shutil.which("tc")
    if not tc_bin:
        subprocess.check_call(["apt-get", "update"])
        subprocess.check_call(["apt-get", "install", "-y", "iproute2"])
        tc_bin = shutil.which("tc")
    if not tc_bin:
        raise SystemExit("tc command not found after installing iproute2.")

    Path("/etc/systemd/system/tc-htb-fq.service").write_text(f"""[Unit]
Description={profile} HTB {rate} limit with fq for {dev}
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart={tc_bin} qdisc replace dev {dev} root handle 1: htb default 10
ExecStart={tc_bin} class replace dev {dev} parent 1: classid 1:10 htb rate {rate} ceil {rate}
ExecStart={tc_bin} qdisc replace dev {dev} parent 1:10 handle 10: fq
ExecStop={tc_bin} qdisc del dev {dev} root

[Install]
WantedBy=multi-user.target
""", encoding="utf-8")

    subprocess.call(["systemctl", "daemon-reload"])
    subprocess.call(["systemctl", "enable", "--now", "tc-htb-fq.service"])
    print(f"Network profile {profile} installed on {dev} with {rate} HTB + fq.")
    stable_net_status(dev)

def remove_stable_net_profile():
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "disable", "--now", "tc-htb-fq.service"], stderr=subprocess.DEVNULL)
    Path("/etc/systemd/system/tc-htb-fq.service").unlink(missing_ok=True)
    Path("/etc/sysctl.d/99-dmit-stable.conf").unlink(missing_ok=True)
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "daemon-reload"])
    subprocess.call(["sysctl", "--system"])
    print("Stable network profile removed.")
    print("If temporary tuning was applied manually before, reboot to return every runtime value to OS defaults.")

def stable_net_status(dev=None):
    dev = dev or default_netdev()
    print("== sysctl ==")
    subprocess.call(["sysctl", "net.core.default_qdisc"])
    subprocess.call(["sysctl", "net.ipv4.tcp_congestion_control"])
    subprocess.call(["sysctl", "net.ipv4.tcp_mtu_probing"])
    subprocess.call(["sysctl", "net.ipv4.tcp_limit_output_bytes"])
    subprocess.call(["sysctl", "net.core.rmem_max"])
    subprocess.call(["sysctl", "net.core.wmem_max"])
    subprocess.call(["sysctl", "net.ipv4.tcp_rmem"])
    subprocess.call(["sysctl", "net.ipv4.tcp_wmem"])
    print(f"\n== tc qdisc ({dev}) ==")
    if shutil.which("tc"):
        subprocess.call(["tc", "-s", "qdisc", "show", "dev", dev])
        print(f"\n== tc class ({dev}) ==")
        subprocess.call(["tc", "-s", "class", "show", "dev", dev])
    else:
        print("tc command not found.")
    print("\n== service ==")
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "--no-pager", "--full", "status", "tc-htb-fq.service"])
    else:
        print("systemctl not found.")

def backup_uninstall(name):
    ts = time.strftime("%Y%m%d%H%M%S")
    archive = f"/root/singbox-{name}-uninstall-backup-{ts}.tar.gz"
    subprocess.call([
        "tar", "-czf", archive,
        "/etc/sing-box",
        "/root/singbox-entry-info.txt",
        "/root/singbox-home-info.txt",
        "/usr/local/bin/sb",
        "/usr/local/bin/sing-box",
        "/etc/systemd/system/sing-box.service",
        "/etc/init.d/sing-box",
        "/etc/nftables.conf",
        "/etc/systemd/system/tc-htb-fq.service",
        "/etc/sysctl.d/99-dmit-stable.conf",
    ], stderr=subprocess.DEVNULL)
    try:
        os.chmod(archive, 0o600)
    except OSError:
        pass
    return archive

def stop_and_remove_service():
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "stop", "sing-box"], stderr=subprocess.DEVNULL)
        subprocess.call(["systemctl", "disable", "sing-box"], stderr=subprocess.DEVNULL)
        Path("/etc/systemd/system/sing-box.service").unlink(missing_ok=True)
        subprocess.call(["systemctl", "daemon-reload"], stderr=subprocess.DEVNULL)
    if shutil.which("rc-service"):
        subprocess.call(["rc-service", "sing-box", "stop"], stderr=subprocess.DEVNULL)
        subprocess.call(["rc-update", "del", "sing-box", "default"], stderr=subprocess.DEVNULL)
        Path("/etc/init.d/sing-box").unlink(missing_ok=True)

def remove_stable_profile():
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "disable", "--now", "tc-htb-fq.service"], stderr=subprocess.DEVNULL)
    Path("/etc/systemd/system/tc-htb-fq.service").unlink(missing_ok=True)
    Path("/etc/sysctl.d/99-dmit-stable.conf").unlink(missing_ok=True)
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "daemon-reload"], stderr=subprocess.DEVNULL)
    subprocess.call(["sysctl", "--system"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def remove_nftables():
    if shutil.which("systemctl"):
        subprocess.call(["systemctl", "disable", "--now", "nftables"], stderr=subprocess.DEVNULL)
    if shutil.which("nft"):
        subprocess.call(["nft", "flush", "ruleset"], stderr=subprocess.DEVNULL)
    Path("/etc/nftables.conf").unlink(missing_ok=True)

def remove_files():
    shutil.rmtree("/etc/sing-box", ignore_errors=True)
    Path("/usr/local/bin/sb").unlink(missing_ok=True)
    bin_path = shutil.which("sing-box")
    if bin_path:
        Path(bin_path).unlink(missing_ok=True)
    Path("/usr/local/bin/sing-box").unlink(missing_ok=True)
    Path("/root/singbox-entry-info.txt").unlink(missing_ok=True)
    Path("/root/singbox-home-info.txt").unlink(missing_ok=True)

def uninstall_entry():
    confirm = input("Type UNINSTALL_ENTRY to remove entry install: ").strip()
    if confirm != "UNINSTALL_ENTRY":
        print("Cancelled.")
        return
    archive = backup_uninstall("entry")
    stop_and_remove_service()
    remove_stable_profile()
    remove_files()
    print(f"Entry install removed. Backup: {archive}")
    print("nftables was kept enabled. Use purge-all only if you also want to remove firewall rules.")

def purge_entry():
    confirm = input("Type PURGE_ENTRY to remove entry install WITHOUT backup: ").strip()
    if confirm != "PURGE_ENTRY":
        print("Cancelled.")
        return
    stop_and_remove_service()
    remove_stable_profile()
    remove_files()
    print("Entry install purged without backup.")
    print("nftables was kept enabled. Use purge-all only if you also want to remove firewall rules.")

def purge_all():
    confirm = input("Type PURGE_ALL to remove sing-box AND nftables firewall WITHOUT backup: ").strip()
    if confirm != "PURGE_ALL":
        print("Cancelled.")
        return
    stop_and_remove_service()
    remove_stable_profile()
    remove_nftables()
    remove_files()
    print("Everything installed by this script was purged without backup.")

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
        print("13. Purge all, including nftables firewall")
        print("14. Install stable network profile")
        print("15. Remove stable network profile")
        print("16. Show stable network profile status")
        print("17. Update sb manager")
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
        elif choice == "13":
            purge_all()
        elif choice == "14":
            install_stable_net_profile()
        elif choice == "15":
            remove_stable_net_profile()
        elif choice == "16":
            stable_net_status()
        elif choice == "17":
            update_manager()
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
        del_user(args[1] if len(args) > 1 else input("Relay name: ").strip(), relay_only=True)
    elif cmd == "list-relays":
        list_relays()
    elif cmd == "links":
        list_links()
    elif cmd == "add-friend":
        add_friend(args[1] if len(args) > 1 else input("Friend name: ").strip())
    elif cmd == "del-user":
        del_user(args[1] if len(args) > 1 else input("User name: ").strip(), relay_only=False)
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
    elif cmd == "purge-all":
        purge_all()
    elif cmd == "stable-install":
        install_stable_net_profile(
            args[1] if len(args) > 1 else None,
            args[2] if len(args) > 2 else None,
            args[3] if len(args) > 3 else None,
        )
    elif cmd == "stable-remove":
        remove_stable_net_profile()
    elif cmd == "stable-status":
        stable_net_status(args[1] if len(args) > 1 else None)
    elif cmd == "update":
        update_manager()
    else:
        print("Usage: sb [add-ss|del-relay|list-relays|links|add-friend|del-user|restart|test|backup|restore-latest|uninstall|purge|purge-all|stable-install|stable-remove|stable-status|update]")
        raise SystemExit(1)

if __name__ == "__main__":
    main()
PYEOF
  chmod 700 /usr/local/bin/sb
}

install_entry() {
  role="$1"
  [ "$OS_FAMILY" = "debian" ] || die "Entry requires Debian/Ubuntu."
  ensure_clean_install
  install_deps
  install_singbox

  case "$role" in
    dmit)
      NODE_ROLE="dmit"
      NODE_PREFIX="${NODE_PREFIX:-DMIT}"
      REALITY_SNI="${REALITY_SNI:-reed.edu}"
      ;;
    other|*)
      NODE_ROLE="other"
      NODE_PREFIX="${NODE_PREFIX:-ENTRY}"
      REALITY_SNI="${REALITY_SNI:-www.microsoft.com}"
      ;;
  esac

  NODE_PREFIX="$(safe_label "$(ask "Node name shown in links" "$NODE_PREFIX")")"
  [ -n "$NODE_PREFIX" ] || NODE_PREFIX="ENTRY"
  if detect_public_ipv6; then
    log "Detected usable IPv6: $DETECTED_IPV6"
    if ask_yes_no "Enable SS2022 on 8443 with this IPv6" "y"; then
      ENABLE_SS="1"
      SS_ACCESS_HOST="$DETECTED_IPV6"
    else
      ENABLE_SS="0"
      SS_ACCESS_HOST=""
    fi
  else
    log "No usable IPv6 detected. This entry will install Reality only."
    ENABLE_SS="0"
    SS_ACCESS_HOST=""
  fi
  REALITY_SNI="$(ask "Reality SNI / camouflage site" "$REALITY_SNI")"
  SSH_PORT="$(ask "SSH port to allow in firewall" "${SSH_PORT:-51398}")"
  validate_port "SSH port" "$SSH_PORT"

  ACCESS_HOST="$(public_ipv4)"
  ENTRY_USERS="CAO,WEI,TAO,XU"
  ENTRY_UUIDS="$(random_uuid),$(random_uuid),$(random_uuid),$(random_uuid)"
  ENTRY_SIDS="$(random_hex8),$(random_hex8),$(random_hex8),$(random_hex8)"
  reality_keypair
  SS_METHOD="2022-blake3-aes-128-gcm"
  if [ "$ENABLE_SS" = "1" ]; then
    SS_SERVER_PASSWORD="$(openssl rand -base64 16 | tr -d '\n\r')"
    SS_USER_PASSWORDS="$(openssl rand -base64 16 | tr -d '\n\r'),$(openssl rand -base64 16 | tr -d '\n\r'),$(openssl rand -base64 16 | tr -d '\n\r'),$(openssl rand -base64 16 | tr -d '\n\r')"
  else
    SS_SERVER_PASSWORD=""
    SS_USER_PASSWORDS=""
  fi

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
  if [ "$ENABLE_SS" = "1" ]; then
    log "Firewall: inbound TCP ${SSH_PORT}, TCP 443, TCP/UDP 8443."
  else
    log "Firewall: inbound TCP ${SSH_PORT} and TCP 443."
  fi
  if [ "$NODE_ROLE" = "dmit" ]; then
    dmit_profile="$(ask "DMIT profile: skip/safe/balanced/performance/ultra/custom" "performance")"
    case "$dmit_profile" in
      skip|0|n|N) log "DMIT network profile skipped." ;;
      safe|1) install_stable_net_profile dmit-safe ;;
      balanced|2) install_stable_net_profile dmit-balanced ;;
      performance|3) install_stable_net_profile dmit-performance ;;
      ultra|4) install_stable_net_profile dmit-ultra ;;
      custom|5) install_stable_net_profile custom ;;
      *) die "Invalid DMIT profile: $dmit_profile" ;;
    esac
  fi
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
      "password": "${SS_PASSWORD}"
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
        "server": "dns_local"
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
ss_host = "${SS_LINK_HOST:-$ACCESS_HOST}"
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
    link_host = f"[{ss_host}]" if ":" in ss_host and not ss_host.startswith("[") else ss_host
    raw = f"{method}:{password}@{link_host}:{public_port}"
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
    print(f"ss://{method}:{quote(password, safe='')}@{link_host}:{public_port}#{quote(name + '-SS')}")
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
    ss -lntup || true
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntup || true
  fi
}

update_manager() {
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT INT TERM
  curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh -o "$tmp"
  bash "$tmp" update-manager
  rm -f "$tmp"
  trap - EXIT INT TERM
}

uninstall_home() {
  printf "Type UNINSTALL_HOME to remove home install: "
  read -r confirm
  [ "$confirm" = "UNINSTALL_HOME" ] || { echo "Cancelled."; exit 0; }
  backup="/root/singbox-home-uninstall-backup-$(date +%Y%m%d%H%M%S).tar.gz"
  tar -czf "$backup" /etc/sing-box /root/singbox-home-info.txt /root/singbox-entry-info.txt /usr/local/bin/sb /usr/local/bin/sing-box /etc/systemd/system/sing-box.service /etc/init.d/sing-box /etc/nftables.conf /etc/systemd/system/tc-htb-fq.service /etc/sysctl.d/99-dmit-stable.conf 2>/dev/null || true
  chmod 600 "$backup" 2>/dev/null || true
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    systemctl disable --now tc-htb-fq.service 2>/dev/null || true
    rm -f /etc/systemd/system/sing-box.service
    rm -f /etc/systemd/system/tc-htb-fq.service
    systemctl daemon-reload 2>/dev/null || true
  else
    rc-service sing-box stop 2>/dev/null || true
    rc-update del sing-box default 2>/dev/null || true
    rm -f /etc/init.d/sing-box
  fi
  rm -rf /etc/sing-box
  rm -f /root/singbox-home-info.txt /root/singbox-entry-info.txt
  rm -f /usr/local/bin/sb /usr/local/bin/sing-box
  rm -f /etc/sysctl.d/99-dmit-stable.conf
  sysctl --system >/dev/null 2>&1 || true
  echo "Home install removed. Backup: $backup"
  echo "nftables was kept enabled. Use purge-all only if you also want to remove firewall rules."
}

purge_home() {
  printf "Type PURGE_HOME to remove home install WITHOUT backup: "
  read -r confirm
  [ "$confirm" = "PURGE_HOME" ] || { echo "Cancelled."; exit 0; }
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    systemctl disable --now tc-htb-fq.service 2>/dev/null || true
    rm -f /etc/systemd/system/sing-box.service
    rm -f /etc/systemd/system/tc-htb-fq.service
    systemctl daemon-reload 2>/dev/null || true
  else
    rc-service sing-box stop 2>/dev/null || true
    rc-update del sing-box default 2>/dev/null || true
    rm -f /etc/init.d/sing-box
  fi
  rm -rf /etc/sing-box
  rm -f /root/singbox-home-info.txt /root/singbox-entry-info.txt
  rm -f /usr/local/bin/sb /usr/local/bin/sing-box
  rm -f /etc/sysctl.d/99-dmit-stable.conf
  sysctl --system >/dev/null 2>&1 || true
  echo "Home install purged without backup."
  echo "nftables was kept enabled. Use purge-all only if you also want to remove firewall rules."
}

purge_all_home() {
  printf "Type PURGE_ALL to remove sing-box AND nftables firewall WITHOUT backup: "
  read -r confirm
  [ "$confirm" = "PURGE_ALL" ] || { echo "Cancelled."; exit 0; }
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    systemctl disable --now tc-htb-fq.service 2>/dev/null || true
    systemctl disable --now nftables 2>/dev/null || true
    rm -f /etc/systemd/system/sing-box.service
    rm -f /etc/systemd/system/tc-htb-fq.service
    systemctl daemon-reload 2>/dev/null || true
  else
    rc-service sing-box stop 2>/dev/null || true
    rc-update del sing-box default 2>/dev/null || true
    rm -f /etc/init.d/sing-box
  fi
  if command -v nft >/dev/null 2>&1; then
    nft flush ruleset 2>/dev/null || true
  fi
  rm -rf /etc/sing-box
  rm -f /root/singbox-home-info.txt /root/singbox-entry-info.txt
  rm -f /usr/local/bin/sb /usr/local/bin/sing-box
  rm -f /etc/sysctl.d/99-dmit-stable.conf /etc/nftables.conf
  sysctl --system >/dev/null 2>&1 || true
  echo "Everything installed by this script was purged without backup."
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
  update)
    update_manager
    ;;
  uninstall)
    uninstall_home
    ;;
  purge)
    purge_home
    ;;
  purge-all)
    purge_all_home
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
    echo "8. Purge all, including nftables firewall"
    echo "9. Update sb manager"
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
      8) "$0" purge-all ;;
      9) "$0" update ;;
      0) exit 0 ;;
    esac
    ;;
esac
EOF
  chmod 700 /usr/local/bin/sb
}

install_home() {
  ensure_clean_install
  install_deps
  install_singbox

  raw_home_name="$(ask "Landing node name" "landing")"
  HOME_NAME="$(safe_label "$raw_home_name")"
  [ -n "$HOME_NAME" ] || HOME_NAME="landing"
  log "Landing install mode:"
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

  HAS_IPV6="0"
  IPV6_HOST=""
  if [ "$HOME_MODE" = "ss2022" ] || [ "$HOME_MODE" = "both" ]; then
    if detect_public_ipv6; then
      log "Detected usable IPv6: $DETECTED_IPV6"
      if ask_yes_no "Use this IPv6 in SS2022 links" "y"; then
        HAS_IPV6="1"
        IPV6_HOST="$DETECTED_IPV6"
      fi
    else
      log "No usable IPv6 detected. SS2022 links will use IPv4."
    fi
  fi
  SSH_PORT="$(ask "SSH port to allow in firewall" "${SSH_PORT:-51398}")"
  validate_port "SSH port" "$SSH_PORT"

  IPV4_HOST="$(public_ipv4)"
  ACCESS_HOST="$IPV4_HOST"

  if [ "$HOME_MODE" = "ss2022" ] || [ "$HOME_MODE" = "both" ]; then
    SS_PORT="8443"
    SS_PUBLIC_PORT="8443"
    SS_METHOD="${SS_METHOD:-2022-blake3-aes-256-gcm}"
    SS_PASSWORD="${SS_PASSWORD:-$(random_ss2022_password)}"
    [ "$HAS_IPV6" = "1" ] && ACCESS_HOST="$IPV6_HOST"
  else
    SS_PORT=""
    SS_PUBLIC_PORT=""
    SS_METHOD=""
    SS_PASSWORD=""
  fi

  if [ "$HOME_MODE" = "reality" ] || [ "$HOME_MODE" = "both" ]; then
    REALITY_PORT="443"
    REALITY_PUBLIC_PORT="443"
    REALITY_SNI="$(ask "Reality SNI / camouflage site" "${REALITY_SNI:-www.sony.jp}")"
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
  if [ "$HOME_MODE" = "both" ]; then
    ACCESS_HOST="$IPV4_HOST"
    SS_LINK_HOST="$([ "$HAS_IPV6" = "1" ] && printf '%s' "$IPV6_HOST" || printf '%s' "$IPV4_HOST")"
  else
    SS_LINK_HOST="$ACCESS_HOST"
  fi
  cat > "$HOME_META_PATH" <<EOF
HOME_NAME="${HOME_NAME}"
HOME_MODE="${HOME_MODE}"
ACCESS_HOST="${ACCESS_HOST}"
SS_LINK_HOST="${SS_LINK_HOST:-$ACCESS_HOST}"
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
    case "$HOME_MODE" in
      ss2022) ENABLE_REALITY="0"; ENABLE_SS="1" ;;
      reality) ENABLE_REALITY="1"; ENABLE_SS="0" ;;
      both) ENABLE_REALITY="1"; ENABLE_SS="1" ;;
    esac
    enable_entry_firewall
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

update_manager_only() {
  [ -x "$SB_MANAGER" ] || die "No sb manager found. Install a node first."
  ts="$(date +%Y%m%d%H%M%S)"
  backup="${SB_MANAGER}.bak.${ts}"
  cp -a "$SB_MANAGER" "$backup"

  if [ -r "$META_PATH" ] && [ ! -r "$HOME_META_PATH" ]; then
    write_entry_manager
    if ! python3 - "$SB_MANAGER" <<'PY'
from pathlib import Path
import sys
compile(Path(sys.argv[1]).read_text(encoding="utf-8"), sys.argv[1], "exec")
PY
    then
      cp -a "$backup" "$SB_MANAGER"
      die "Updated entry manager failed validation; restored $backup"
    fi
  elif [ -r "$HOME_META_PATH" ] && [ ! -r "$META_PATH" ]; then
    write_home_manager
    if ! sh -n "$SB_MANAGER"; then
      cp -a "$backup" "$SB_MANAGER"
      die "Updated home manager failed validation; restored $backup"
    fi
  else
    die "Cannot identify a single entry or landing installation."
  fi
  log "sb manager updated. Backup: $backup"
}

print_menu() {
  log ""
  log "Smart sing-box installer"
  log "1. Entry line machine"
  log "2. Landing machine"
  log "3. Update existing sb manager"
  log "0. Exit"
  log ""
}

main() {
  need_root
  need_tty
  if [ "${1:-}" = "update-manager" ] || [ "${1:-}" = "--update-manager" ]; then
    update_manager_only
    exit 0
  fi
  detect_os
  print_menu > /dev/tty
  choice="$(ask "Choose" "")"
  case "$choice" in
    1)
      log "Entry line type:"
      log "1. DMIT"
      log "2. Other region/provider"
      entry_type="$(ask "Choose entry type" "1")"
      case "$entry_type" in
        1|dmit|DMIT) install_entry dmit ;;
        2|other|Other) install_entry other ;;
        *) die "Invalid entry type: $entry_type" ;;
      esac
      ;;
    2) install_home ;;
    3) update_manager_only ;;
    0) exit 0 ;;
    *) die "Invalid choice: $choice" ;;
  esac
}

main "$@"
