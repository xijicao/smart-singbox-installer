#!/usr/bin/env sh

SINGBOX_BIN="/usr/local/bin/sing-box"
CONFIG_DIR="/etc/sing-box"
CONFIG_PATH="${CONFIG_DIR}/config.json"

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_root_common() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "Please run as root."
  fi
}

require_os_family() {
  required="$1"
  if [ "${OS_FAMILY:-}" != "${required}" ]; then
    fail "This profile requires ${required}, current OS family is ${OS_FAMILY:-unknown}."
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) SB_ARCH="amd64" ;;
    aarch64|arm64) SB_ARCH="arm64" ;;
    *) fail "Unsupported architecture: $(uname -m). Supported: amd64/arm64." ;;
  esac
}

latest_singbox_version() {
  if [ -n "${SINGBOX_VERSION:-}" ]; then
    printf '%s' "${SINGBOX_VERSION#v}"
    return
  fi

  version="$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null \
    | sed -n 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' \
    | head -n 1)"

  if [ -z "${version}" ]; then
    latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/SagerNet/sing-box/releases/latest 2>/dev/null || true)"
    version="$(printf '%s' "${latest_url}" | sed -n 's#.*/tag/v\{0,1\}\([^/]*\)$#\1#p')"
  fi

  if [ -z "${version}" ]; then
    fail "Cannot detect latest sing-box version. Set SINGBOX_VERSION manually."
  fi

  printf '%s' "${version}"
}

install_debian_dependencies() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl tar openssl iproute2 nftables python3
  update-ca-certificates >/dev/null 2>&1 || true
}

install_alpine_dependencies() {
  apk update
  apk add ca-certificates curl tar openssl iproute2 grep python3
  update-ca-certificates >/dev/null 2>&1 || true
}

install_singbox_tarball() {
  preferred_libc="${1:-}"
  detect_arch
  version="$(latest_singbox_version)"

  case "${preferred_libc}" in
    glibc) suffixes="glibc standard" ;;
    musl) suffixes="musl standard" ;;
    *) suffixes="standard" ;;
  esac

  tmp_dir="$(mktemp -d)"
  archive=""
  dir=""

  for suffix in ${suffixes}; do
    if [ "${suffix}" = "standard" ]; then
      candidate_archive="sing-box-${version}-linux-${SB_ARCH}.tar.gz"
      candidate_dir="sing-box-${version}-linux-${SB_ARCH}"
    else
      candidate_archive="sing-box-${version}-linux-${SB_ARCH}-${suffix}.tar.gz"
      candidate_dir="sing-box-${version}-linux-${SB_ARCH}-${suffix}"
    fi

    url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${candidate_archive}"
    log "Trying sing-box ${version}: ${candidate_archive}"

    if (cd "${tmp_dir}" && curl -fL -O "${url}"); then
      archive="${candidate_archive}"
      dir="${candidate_dir}"
      break
    fi
  done

  if [ -z "${archive}" ]; then
    rm -rf "${tmp_dir}"
    fail "Failed to download sing-box ${version} for linux-${SB_ARCH}. Tried system-specific and standard tarballs."
  fi

  (
    cd "${tmp_dir}"
    tar -xzf "${archive}"
    if [ -x "${dir}/sing-box" ]; then
      install -m 755 "${dir}/sing-box" "${SINGBOX_BIN}"
    else
      found_bin="$(find . -type f -name sing-box -perm -111 | head -n 1)"
      [ -n "${found_bin}" ] || fail "sing-box binary not found inside ${archive}."
      install -m 755 "${found_bin}" "${SINGBOX_BIN}"
    fi
  )
  rm -rf "${tmp_dir}"
}

write_home_uninstall_script() {
  uninstall_path="/usr/local/bin/sing-box-uninstall"
  cat > "${uninstall_path}" <<'EOF'
#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

if [ "${FORCE_UNINSTALL:-0}" != "1" ]; then
  if [ -r /dev/tty ]; then
    echo "This will stop sing-box and remove the home sing-box install." > /dev/tty
    echo "It removes config, service files, healthcheck, info file and /usr/local/bin/sing-box." > /dev/tty
    printf "Type UNINSTALL to continue: " > /dev/tty
    read -r confirm < /dev/tty
    [ "${confirm}" = "UNINSTALL" ] || { echo "Cancelled."; exit 0; }
  else
    echo "No TTY found. Run with FORCE_UNINSTALL=1 to uninstall non-interactively." >&2
    exit 1
  fi
fi

backup_path="/root/sing-box-uninstall-backup-$(date +%Y%m%d%H%M%S).tar.gz"
tar -czf "${backup_path}" \
  /etc/sing-box \
  /root/home-singbox-info.txt \
  /etc/systemd/system/sing-box.service \
  /etc/init.d/sing-box \
  /etc/periodic/15min/sing-box-healthcheck \
  /usr/local/bin/sing-box-healthcheck \
  /usr/local/bin/sing-box 2>/dev/null || true
chmod 600 "${backup_path}" 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl stop sing-box >/dev/null 2>&1 || true
  systemctl disable sing-box >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/sing-box.service
  systemctl daemon-reload >/dev/null 2>&1 || true
fi

if command -v rc-service >/dev/null 2>&1; then
  rc-service sing-box stop >/dev/null 2>&1 || true
  rc-update del sing-box default >/dev/null 2>&1 || true
fi

rm -f /etc/init.d/sing-box
rm -f /etc/periodic/15min/sing-box-healthcheck
rm -f /usr/local/bin/sing-box-healthcheck
rm -rf /etc/sing-box
rm -f /root/home-singbox-info.txt
rm -f /usr/local/bin/sing-box
rm -f /usr/local/bin/sing-box-uninstall

echo "sing-box home install removed."
echo "Backup, if any files existed: ${backup_path}"
EOF
  chmod 700 "${uninstall_path}"
}

write_home_restore_script() {
  restore_path="/usr/local/bin/sing-box-restore"
  cat > "${restore_path}" <<'EOF'
#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

backup_path="${1:-}"
if [ -z "${backup_path}" ]; then
  backup_path="$(ls -1t /root/sing-box-uninstall-backup-*.tar.gz 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${backup_path}" ] || [ ! -r "${backup_path}" ]; then
  echo "No readable home uninstall backup found. You can pass one explicitly:" >&2
  echo "  sing-box-restore /root/sing-box-uninstall-backup-YYYYMMDDHHMMSS.tar.gz" >&2
  exit 1
fi

pre_restore="/root/sing-box-pre-restore-backup-$(date +%Y%m%d%H%M%S).tar.gz"
tar -czf "${pre_restore}" \
  /etc/sing-box \
  /root/home-singbox-info.txt \
  /etc/systemd/system/sing-box.service \
  /etc/init.d/sing-box \
  /etc/periodic/15min/sing-box-healthcheck \
  /usr/local/bin/sing-box-healthcheck \
  /usr/local/bin/sing-box \
  /usr/local/bin/sing-box-uninstall \
  /usr/local/bin/sing-box-restore 2>/dev/null || true
chmod 600 "${pre_restore}" 2>/dev/null || true

tar -xzf "${backup_path}" -C /

chmod 755 /usr/local/bin/sing-box 2>/dev/null || true
chmod 700 /usr/local/bin/sing-box-uninstall /usr/local/bin/sing-box-restore 2>/dev/null || true
chmod 755 /usr/local/bin/sing-box-healthcheck 2>/dev/null || true
chmod 755 /etc/init.d/sing-box 2>/dev/null || true
chmod 600 /etc/sing-box/config.json /root/home-singbox-info.txt 2>/dev/null || true

if [ -x /usr/local/bin/sing-box ] && [ -r /etc/sing-box/config.json ]; then
  /usr/local/bin/sing-box check -c /etc/sing-box/config.json
fi

if command -v systemctl >/dev/null 2>&1 && [ -r /etc/systemd/system/sing-box.service ]; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable sing-box >/dev/null 2>&1 || true
  systemctl restart sing-box
elif command -v rc-service >/dev/null 2>&1 && [ -x /etc/init.d/sing-box ]; then
  rc-update add crond default >/dev/null 2>&1 || true
  rc-service crond start >/dev/null 2>&1 || true
  rc-update add sing-box default >/dev/null 2>&1 || true
  rc-service sing-box restart
fi

echo "sing-box home install restored from: ${backup_path}"
echo "Pre-restore backup saved to: ${pre_restore}"
EOF
  chmod 700 "${restore_path}"
}

write_entry_uninstall_script() {
  uninstall_path="/usr/local/bin/sing-box-entry-uninstall"
  cat > "${uninstall_path}" <<'EOF'
#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

if [ "${FORCE_UNINSTALL_ENTRY:-0}" != "1" ]; then
  if [ -r /dev/tty ]; then
    echo "This will stop sing-box and remove the DMIT/HK entry install." > /dev/tty
    echo "It removes config, service file, info files, relay importer, sb manager and /usr/local/bin/sing-box." > /dev/tty
    echo "It does not remove apt packages or restore the whole OS to factory state." > /dev/tty
    printf "Type UNINSTALL_ENTRY to continue: " > /dev/tty
    read -r confirm < /dev/tty
    [ "${confirm}" = "UNINSTALL_ENTRY" ] || { echo "Cancelled."; exit 0; }
  else
    echo "No TTY found. Run with FORCE_UNINSTALL_ENTRY=1 to uninstall non-interactively." >&2
    exit 1
  fi
fi

backup_path="/root/sing-box-entry-uninstall-backup-$(date +%Y%m%d%H%M%S).tar.gz"
tar -czf "${backup_path}" \
  /etc/sing-box \
  /root/dmit-singbox-info.txt \
  /root/hk-singbox-info.txt \
  /etc/systemd/system/sing-box.service \
  /usr/local/bin/sing-box \
  /usr/local/bin/sing-box-add-ss2022-relay \
  /usr/local/bin/sb \
  /usr/local/bin/-sb 2>/dev/null || true
chmod 600 "${backup_path}" 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
  systemctl stop sing-box >/dev/null 2>&1 || true
  systemctl disable sing-box >/dev/null 2>&1 || true
  rm -f /etc/systemd/system/sing-box.service
  systemctl daemon-reload >/dev/null 2>&1 || true
fi

rm -rf /etc/sing-box
rm -f /root/dmit-singbox-info.txt
rm -f /root/hk-singbox-info.txt
rm -f /usr/local/bin/sing-box
rm -f /usr/local/bin/sing-box-add-ss2022-relay
rm -f /usr/local/bin/sb
rm -f /usr/local/bin/-sb
rm -f /usr/local/bin/sing-box-entry-uninstall

echo "sing-box entry install removed."
echo "Backup, if any files existed: ${backup_path}"
EOF
  chmod 700 "${uninstall_path}"
}

write_entry_restore_script() {
  restore_path="/usr/local/bin/sing-box-entry-restore"
  cat > "${restore_path}" <<'EOF'
#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

backup_path="${1:-}"
if [ -z "${backup_path}" ]; then
  backup_path="$(ls -1t /root/sing-box-entry-uninstall-backup-*.tar.gz 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${backup_path}" ] || [ ! -r "${backup_path}" ]; then
  echo "No readable entry uninstall backup found. You can pass one explicitly:" >&2
  echo "  sing-box-entry-restore /root/sing-box-entry-uninstall-backup-YYYYMMDDHHMMSS.tar.gz" >&2
  exit 1
fi

pre_restore="/root/sing-box-entry-pre-restore-backup-$(date +%Y%m%d%H%M%S).tar.gz"
tar -czf "${pre_restore}" \
  /etc/sing-box \
  /root/dmit-singbox-info.txt \
  /root/hk-singbox-info.txt \
  /etc/systemd/system/sing-box.service \
  /usr/local/bin/sing-box \
  /usr/local/bin/sing-box-add-ss2022-relay \
  /usr/local/bin/sb \
  /usr/local/bin/-sb \
  /usr/local/bin/sing-box-entry-uninstall \
  /usr/local/bin/sing-box-entry-restore 2>/dev/null || true
chmod 600 "${pre_restore}" 2>/dev/null || true

tar -xzf "${backup_path}" -C /

chmod 755 /usr/local/bin/sing-box 2>/dev/null || true
chmod 700 /usr/local/bin/sing-box-add-ss2022-relay /usr/local/bin/sb /usr/local/bin/-sb /usr/local/bin/sing-box-entry-uninstall /usr/local/bin/sing-box-entry-restore 2>/dev/null || true
chmod 600 /etc/sing-box/config.json /etc/sing-box/reality-meta.env /root/dmit-singbox-info.txt /root/hk-singbox-info.txt 2>/dev/null || true

if [ -x /usr/local/bin/sing-box ] && [ -r /etc/sing-box/config.json ]; then
  /usr/local/bin/sing-box check -c /etc/sing-box/config.json
fi

if command -v systemctl >/dev/null 2>&1 && [ -r /etc/systemd/system/sing-box.service ]; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable sing-box >/dev/null 2>&1 || true
  systemctl restart sing-box
fi

echo "sing-box entry install restored from: ${backup_path}"
echo "Pre-restore backup saved to: ${pre_restore}"
EOF
  chmod 700 "${restore_path}"
}

random_uuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    "${SINGBOX_BIN}" generate uuid
  fi
}

random_hex() {
  bytes="$1"
  openssl rand -hex "${bytes}"
}

singbox_rand_base64_32() {
  "${SINGBOX_BIN}" generate rand --base64 32
}

generate_reality_keypair() {
  keypair="$("${SINGBOX_BIN}" generate reality-keypair)"
  REALITY_PRIVATE_KEY="$(printf '%s\n' "${keypair}" | awk -F': ' '/PrivateKey/ {print $2}')"
  REALITY_PUBLIC_KEY="$(printf '%s\n' "${keypair}" | awk -F': ' '/PublicKey/ {print $2}')"

  if [ -z "${REALITY_PRIVATE_KEY}" ] || [ -z "${REALITY_PUBLIC_KEY}" ]; then
    fail "Failed to generate Reality keypair."
  fi
}

detect_access_host() {
  if [ -n "${ACCESS_HOST:-}" ]; then
    return
  fi

  ACCESS_HOST="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}')"
  if [ -z "${ACCESS_HOST}" ]; then
    ACCESS_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if [ -z "${ACCESS_HOST}" ]; then
    ACCESS_HOST="${ACCESS_HOST_FALLBACK:-YOUR_SERVER_IP_OR_DOMAIN}"
  fi
}

write_systemd_service() {
  service_path="/etc/systemd/system/sing-box.service"
  cat > "${service_path}" <<EOF
[Unit]
Description=sing-box
After=network-online.target
Wants=network-online.target

[Service]
ExecStartPre=${SINGBOX_BIN} check -c ${CONFIG_PATH}
ExecStart=${SINGBOX_BIN} run -c ${CONFIG_PATH}
Restart=always
RestartSec=3
LimitNOFILE=1048576
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF
}

enable_systemd_singbox() {
  chmod 600 "${CONFIG_PATH}"
  "${SINGBOX_BIN}" check -c "${CONFIG_PATH}"
  systemctl daemon-reload
  systemctl enable sing-box
  systemctl restart sing-box
}

write_openrc_service() {
  openrc_service="/etc/init.d/sing-box"
  cat > "${openrc_service}" <<'EOF'
#!/sbin/openrc-run

name="sing-box"
description="sing-box service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
supervisor="supervise-daemon"
pidfile="/run/sing-box.pid"
respawn_delay=3
respawn_max=5
respawn_period=60

depend() {
  need net
}

start_pre() {
  /usr/local/bin/sing-box check -c /etc/sing-box/config.json
}
EOF
  chmod +x "${openrc_service}"
}

write_alpine_healthcheck() {
  ports="$1"
  healthcheck_script="/usr/local/bin/sing-box-healthcheck"
  cat > "${healthcheck_script}" <<EOF
#!/usr/bin/env sh
set -eu

CONFIG_PATH="/etc/sing-box/config.json"
CHECK_PORTS="${ports}"
NEED_RESTART=0

/usr/local/bin/sing-box check -c "\${CONFIG_PATH}" >/dev/null 2>&1 || NEED_RESTART=1
pidof sing-box >/dev/null 2>&1 || NEED_RESTART=1

for port in \${CHECK_PORTS}; do
  ss -lnptu 2>/dev/null | grep -q ":\${port}" || NEED_RESTART=1
done

if [ "\${NEED_RESTART}" -ne 0 ]; then
  rc-service sing-box restart >/dev/null 2>&1 || true
fi
EOF
  chmod +x "${healthcheck_script}"
  mkdir -p /etc/periodic/15min
  ln -sf "${healthcheck_script}" /etc/periodic/15min/sing-box-healthcheck
}

enable_openrc_singbox() {
  chmod 600 "${CONFIG_PATH}"
  "${SINGBOX_BIN}" check -c "${CONFIG_PATH}"
  rc-update add crond default
  rc-service crond start || true
  rc-update add sing-box default
  rc-service sing-box restart
}

maybe_enable_nftables_443() {
  ssh_port="${SSH_PORT:-22}"
  enable_nftables="${ENABLE_NFTABLES:-0}"

  if [ "${enable_nftables}" != "1" ]; then
    log "nftables firewall skipped. Set ENABLE_NFTABLES=1 SSH_PORT=your_port if you want to enable it."
    return
  fi

  cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;

    iif lo accept
    ct state established,related accept

    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept

    tcp dport ${ssh_port} ct state new limit rate 30/minute accept
    tcp dport 443 accept
  }

  chain forward {
    type filter hook forward priority 0;
    policy accept;
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
EOF

  systemctl enable nftables
  systemctl restart nftables
}

write_info_file() {
  info_path="$1"
  chmod 600 "${info_path}"
  log "Info saved to: ${info_path}"
}

write_reality_meta() {
  meta_path="${1:-/etc/sing-box/reality-meta.env}"
  mkdir -p "$(dirname "${meta_path}")"
  umask 077
  cat > "${meta_path}" <<EOF
NODE_PREFIX="${NODE_PREFIX}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY}"
ACCESS_HOST="${ACCESS_HOST}"
INFO_PATH="${INFO_PATH}"
CONFIG_PATH="${CONFIG_PATH}"
EOF
  chmod 600 "${meta_path}"
}

write_ss2022_relay_importer() {
  importer_path="/usr/local/bin/sing-box-add-ss2022-relay"
  cat > "${importer_path}" <<'EOF'
#!/usr/bin/env sh
set -eu

CONFIG_PATH="${CONFIG_PATH:-/etc/sing-box/config.json}"
META_PATH="${META_PATH:-/etc/sing-box/reality-meta.env}"
METHOD_DEFAULT="2022-blake3-aes-256-gcm"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

if [ ! -r "${META_PATH}" ]; then
  echo "Missing ${META_PATH}. This tool must be installed by dmit-debian or hk-debian profile." >&2
  exit 1
fi

. "${META_PATH}"

ask_value() {
  current_value="$1"
  prompt="$2"
  default_value="${3:-}"

  if [ -n "${current_value}" ]; then
    printf '%s' "${current_value}"
    return
  fi

  if [ ! -r /dev/tty ]; then
    printf '%s' "${default_value}"
    return
  fi

  if [ -n "${default_value}" ]; then
    printf "%s [%s]: " "${prompt}" "${default_value}" > /dev/tty
  else
    printf "%s: " "${prompt}" > /dev/tty
  fi

  read -r input_value < /dev/tty
  if [ -z "${input_value}" ]; then
    input_value="${default_value}"
  fi
  printf '%s' "${input_value}"
}

parse_ss_uri() {
  SS_URI_INPUT="$1"
  export SS_URI_INPUT
  eval "$(python3 - <<'PY'
import base64
import re
import shlex
import sys
from urllib.parse import unquote, urlsplit
import os

uri = os.environ.get("SS_URI_INPUT", "").strip()
if not uri.startswith("ss://"):
    raise SystemExit(1)

body = uri[5:]
name = ""
if "#" in body:
    body, frag = body.split("#", 1)
    name = unquote(frag).strip()

body = body.split("?", 1)[0]
method = password = server = port = ""

if "@" in body:
    userinfo, hostport = body.rsplit("@", 1)
    if ":" in userinfo:
        method, password = userinfo.split(":", 1)
    else:
        padded = userinfo + "=" * (-len(userinfo) % 4)
        decoded = base64.urlsafe_b64decode(padded.encode()).decode()
        method, password = decoded.split(":", 1)
else:
    padded = body + "=" * (-len(body) % 4)
    decoded = base64.urlsafe_b64decode(padded.encode()).decode()
    if "@" not in decoded:
        raise SystemExit(1)
    userinfo, hostport = decoded.rsplit("@", 1)
    method, password = userinfo.split(":", 1)

if hostport.startswith("["):
    m = re.match(r"^\[([^\]]+)\]:(\d+)$", hostport)
    if not m:
        raise SystemExit(1)
    server, port = m.group(1), m.group(2)
else:
    if ":" not in hostport:
        raise SystemExit(1)
    server, port = hostport.rsplit(":", 1)

relay_name = name or server
relay_name = re.sub(r"[^A-Za-z0-9_-]+", "-", relay_name).strip("-").lower() or "home"

print(f"SS2022_METHOD={shlex.quote(unquote(method))}")
print(f"SS2022_PASSWORD={shlex.quote(unquote(password))}")
print(f"SS2022_SERVER={shlex.quote(unquote(server))}")
print(f"SS2022_PORT={shlex.quote(port)}")
print(f"RELAY_NAME={shlex.quote(relay_name)}")
PY
)"
}

SS_URI="$(ask_value "${SS_URI:-}" "Paste ss:// link from home landing, or press Enter for manual input" "")"
if [ -n "${SS_URI}" ]; then
  if parse_ss_uri "${SS_URI}"; then
    echo "Parsed ss:// landing: ${RELAY_NAME} -> ${SS2022_SERVER}:${SS2022_PORT}"
    echo "NAT/LXC note: this port must be the public mapped port, not the internal listen port."
  else
    echo "Failed to parse ss:// link, fallback to manual input." >&2
  fi
fi

RELAY_NAME="$(ask_value "${RELAY_NAME:-}" "Relay name, for example jp-home / tw-home / us-home" "")"
SS2022_SERVER="$(ask_value "${SS2022_SERVER:-}" "SS2022 server IP or domain" "")"
SS2022_PORT="$(ask_value "${SS2022_PORT:-}" "SS2022 public port, for NAT use the mapped outside port" "8443")"
SS2022_PASSWORD="$(ask_value "${SS2022_PASSWORD:-}" "SS2022 password" "")"
SS2022_METHOD="$(ask_value "${SS2022_METHOD:-}" "SS2022 method" "${METHOD_DEFAULT}")"
ACCESS_HOST="$(ask_value "${ACCESS_HOST:-}" "Reality access host for generated link" "${ACCESS_HOST:-}")"
if [ -z "${RELAY_NAME}" ] || [ -z "${SS2022_SERVER}" ] || [ -z "${SS2022_PORT}" ] || [ -z "${SS2022_PASSWORD}" ]; then
  echo "Relay name, server, port and password are required." >&2
  exit 1
fi

case "${SS2022_PORT}" in
  *[!0-9]*)
    echo "SS2022 port must be a number from 1 to 65535. For NAT, use the public mapped port." >&2
    exit 1
    ;;
esac
if [ "${SS2022_PORT}" -lt 1 ] || [ "${SS2022_PORT}" -gt 65535 ]; then
  echo "SS2022 port must be a number from 1 to 65535. For NAT, use the public mapped port." >&2
  exit 1
fi

case "${RELAY_NAME}" in
  *[!A-Za-z0-9_-]*)
    echo "Relay name can only contain letters, numbers, underscore and hyphen." >&2
    exit 1
    ;;
esac

RELAY_USER="relay-${RELAY_NAME}"
OUTBOUND_TAG="to-${RELAY_NAME}"
UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || /usr/local/bin/sing-box generate uuid)"
SHORT_ID="$(openssl rand -hex 4)"
BACKUP_PATH="${CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
INFO_APPEND_PATH="${INFO_PATH:-/root/singbox-relay-info.txt}"

cp "${CONFIG_PATH}" "${BACKUP_PATH}"
chmod 600 "${BACKUP_PATH}"

export CONFIG_PATH RELAY_USER OUTBOUND_TAG UUID SHORT_ID SS2022_SERVER SS2022_PORT SS2022_PASSWORD SS2022_METHOD
python3 - <<'PY'
import json
import os
import sys

path = os.environ["CONFIG_PATH"]
relay_user = os.environ["RELAY_USER"]
outbound_tag = os.environ["OUTBOUND_TAG"]
uuid = os.environ["UUID"]
short_id = os.environ["SHORT_ID"]
server = os.environ["SS2022_SERVER"]
port = int(os.environ["SS2022_PORT"])
password = os.environ["SS2022_PASSWORD"]
method = os.environ["SS2022_METHOD"]

with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

inbounds = cfg.setdefault("inbounds", [])
reality = None
for inbound in inbounds:
    tls = inbound.get("tls", {})
    if inbound.get("type") == "vless" and tls.get("reality", {}).get("enabled") is True:
        reality = inbound
        break
if reality is None:
    raise SystemExit("No Reality VLESS inbound found.")

users = reality.setdefault("users", [])
if any(u.get("name") == relay_user or u.get("uuid") == uuid for u in users):
    raise SystemExit(f"Relay user already exists: {relay_user}. Use sb option 3 to delete it first, or use another relay name.")
users.append({"name": relay_user, "uuid": uuid, "flow": "xtls-rprx-vision"})

reality_tls = reality.setdefault("tls", {}).setdefault("reality", {})
short_ids = reality_tls.setdefault("short_id", [])
if short_id not in short_ids:
    short_ids.append(short_id)

outbounds = cfg.setdefault("outbounds", [])
if any(o.get("tag") == outbound_tag for o in outbounds):
    raise SystemExit(f"Outbound already exists: {outbound_tag}. Use sb option 3 to delete the old relay first, or use another relay name.")
outbounds.insert(max(len(outbounds) - 1, 1), {
    "type": "shadowsocks",
    "tag": outbound_tag,
    "server": server,
    "server_port": port,
    "method": method,
    "password": password,
    "network": "tcp",
})

route = cfg.setdefault("route", {})
rules = route.setdefault("rules", [])
if any(outbound_tag == r.get("outbound") for r in rules):
    raise SystemExit(f"Route already exists for: {outbound_tag}. Use sb option 3 to delete the old relay first, or use another relay name.")
rules.append({
    "auth_user": [relay_user],
    "action": "route",
    "outbound": outbound_tag,
})

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
chmod 600 "${CONFIG_PATH}"

if ! /usr/local/bin/sing-box check -c "${CONFIG_PATH}"; then
  cp "${BACKUP_PATH}" "${CONFIG_PATH}"
  chmod 600 "${CONFIG_PATH}"
  echo "Config check failed. Restored backup: ${BACKUP_PATH}" >&2
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart sing-box
else
  service sing-box restart
fi

LINK="vless://${UUID}@${ACCESS_HOST}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${NODE_PREFIX}-${RELAY_USER}"

umask 077
cat >> "${INFO_APPEND_PATH}" <<EOFINFO

Relay added: ${RELAY_NAME}
-------------------------
user: ${RELAY_USER}
uuid: ${UUID}
short_id: ${SHORT_ID}
outbound: ${OUTBOUND_TAG}
ss2022_server: ${SS2022_SERVER}
ss2022_port: ${SS2022_PORT}
ss2022_method: ${SS2022_METHOD}
ss2022_password: ${SS2022_PASSWORD}
link:
${LINK}
EOFINFO
chmod 600 "${INFO_APPEND_PATH}"

echo
echo "Relay Reality node added successfully."
echo "Backup: ${BACKUP_PATH}"
echo "Info appended to: ${INFO_APPEND_PATH}"
echo
echo "Import link:"
echo "${LINK}"
EOF
  chmod 700 "${importer_path}"
}
write_sb_manager() {
  manager_path="/usr/local/bin/sb"
  cat > "${manager_path}" <<'EOF'
#!/usr/bin/env sh
set -eu

SINGBOX_BIN="${SINGBOX_BIN:-/usr/local/bin/sing-box}"
CONFIG_PATH="${CONFIG_PATH:-/etc/sing-box/config.json}"
META_PATH="${META_PATH:-/etc/sing-box/reality-meta.env}"
BACKUP_ROOT="${BACKUP_ROOT:-/etc/sing-box/backups}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root." >&2
  exit 1
fi

if [ ! -r "${META_PATH}" ]; then
  echo "Missing ${META_PATH}." >&2
  exit 1
fi

. "${META_PATH}"

restart_singbox() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sing-box
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box restart
  else
    service sing-box restart
  fi
}

backup_state() {
  label="${1:-manual}"
  backup_dir="${BACKUP_ROOT}/$(date +%Y%m%d%H%M%S)-${label}"
  mkdir -p "${backup_dir}"

  if [ -r "${CONFIG_PATH}" ]; then
    cp "${CONFIG_PATH}" "${backup_dir}/config.json"
  fi
  if [ -r "${META_PATH}" ]; then
    cp "${META_PATH}" "${backup_dir}/reality-meta.env"
  fi
  if [ -x "${SINGBOX_BIN}" ]; then
    cp "${SINGBOX_BIN}" "${backup_dir}/sing-box"
  fi

  chmod 700 "${BACKUP_ROOT}" "${backup_dir}"
  chmod 600 "${backup_dir}"/* 2>/dev/null || true
  printf '%s\n' "${backup_dir}"
}

latest_backup_dir() {
  if [ ! -d "${BACKUP_ROOT}" ]; then
    return 0
  fi
  ls -1dt "${BACKUP_ROOT}"/* 2>/dev/null | head -n 1 || true
}

apply_or_rollback() {
  backup="$1"
  if ! "${SINGBOX_BIN}" check -c "${CONFIG_PATH}"; then
    cp "${backup}" "${CONFIG_PATH}"
    chmod 600 "${CONFIG_PATH}"
    echo "Config check failed. Restored: ${backup}" >&2
    exit 1
  fi
  restart_singbox
}

show_menu() {
  echo
  echo "sing-box manager"
  echo "================"
  echo "1) Regenerate base Reality links for me/friend"
  echo "2) List relay Reality nodes"
  echo "3) Delete a relay Reality node"
  echo "4) Show all current Reality links"
  echo "5) Backup config/meta now"
  echo "6) Restore latest config/meta backup"
  echo "7) Update sing-box core only"
  echo "0) Exit"
  echo
}

menu_choice="${1:-}"
if [ -z "${menu_choice}" ]; then
  show_menu
  printf "Choose: " > /dev/tty
  read -r menu_choice < /dev/tty
fi

case "${menu_choice}" in
  1|regen-base)
    backup="${CONFIG_PATH}.bak.regen-base.$(date +%Y%m%d%H%M%S)"
    cp "${CONFIG_PATH}" "${backup}"
    chmod 600 "${backup}"
    export CONFIG_PATH NODE_PREFIX REALITY_SERVER_NAME REALITY_PUBLIC_KEY ACCESS_HOST INFO_PATH
    python3 - <<'PY'
import json
import os
import subprocess

path = os.environ["CONFIG_PATH"]
node_prefix = os.environ.get("NODE_PREFIX", "NODE")
server_name = os.environ["REALITY_SERVER_NAME"]
public_key = os.environ["REALITY_PUBLIC_KEY"]
access_host = os.environ["ACCESS_HOST"]
info_path = os.environ.get("INFO_PATH", "/root/singbox-info.txt")

with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

reality = None
for inbound in cfg.get("inbounds", []):
    tls = inbound.get("tls", {})
    if inbound.get("type") == "vless" and tls.get("reality", {}).get("enabled") is True:
        reality = inbound
        break
if reality is None:
    raise SystemExit("No Reality inbound found.")

users = reality.get("users", [])
base_users = [u for u in users if not u.get("name", "").startswith("relay-")]
if not base_users:
    raise SystemExit("No base users found.")

short_ids = reality.setdefault("tls", {}).setdefault("reality", {}).setdefault("short_id", [])
relay_short_ids = short_ids[len(base_users):]
new_short_ids = []
links = []
for user in base_users:
    uuid = subprocess.check_output(["cat", "/proc/sys/kernel/random/uuid"], text=True).strip()
    sid = subprocess.check_output(["openssl", "rand", "-hex", "4"], text=True).strip()
    user["uuid"] = uuid
    new_short_ids.append(sid)
    name = user.get("name", "user")
    link = f"vless://{uuid}@{access_host}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni={server_name}&fp=chrome&pbk={public_key}&sid={sid}&type=tcp&headerType=none#{node_prefix}-{name}"
    links.append((name, uuid, sid, link))

reality["tls"]["reality"]["short_id"] = new_short_ids + relay_short_ids

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")

with open(info_path, "a", encoding="utf-8") as f:
    f.write("\nBase Reality users regenerated\n==============================\n")
    for name, uuid, sid, link in links:
        f.write(f"\n{name}\nuuid: {uuid}\nshort_id: {sid}\nlink:\n{link}\n")

for name, uuid, sid, link in links:
    print()
    print(name)
    print("uuid:", uuid)
    print("short_id:", sid)
    print("link:")
    print(link)
PY
    chmod 600 "${CONFIG_PATH}" "${INFO_PATH}"
    apply_or_rollback "${backup}"
    ;;

  2|list-relay)
    python3 - <<'PY'
import json
path = "/etc/sing-box/config.json"
with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)
users = []
for inbound in cfg.get("inbounds", []):
    if inbound.get("type") == "vless":
        users.extend(inbound.get("users", []))
relays = [u.get("name") for u in users if u.get("name", "").startswith("relay-")]
if not relays:
    print("No relay nodes found.")
else:
    for idx, name in enumerate(relays, 1):
        print(f"{idx}) {name}")
PY
    ;;

  3|delete-relay)
    backup="${CONFIG_PATH}.bak.delete-relay.$(date +%Y%m%d%H%M%S)"
    cp "${CONFIG_PATH}" "${backup}"
    chmod 600 "${backup}"
    export CONFIG_PATH
    relay_list="$(python3 - <<'PY'
import json
with open('/etc/sing-box/config.json', 'r', encoding='utf-8') as f:
    cfg = json.load(f)
relays = []
for inbound in cfg.get('inbounds', []):
    if inbound.get('type') == 'vless':
        for user in inbound.get('users', []):
            name = user.get('name', '')
            if name.startswith('relay-'):
                relays.append(name)
for name in relays:
    print(name)
PY
)"
    if [ -z "${relay_list}" ]; then
      echo "No relay nodes found."
      exit 0
    fi
    echo "Relay nodes:" > /dev/tty
    i=1
    for name in ${relay_list}; do
      echo "  ${i}) ${name}" > /dev/tty
      i=$((i + 1))
    done
    printf "Choose relay number to delete: " > /dev/tty
    read -r delete_index < /dev/tty
    relay_name="$(printf '%s\n' ${relay_list} | sed -n "${delete_index}p")"
    if [ -z "${relay_name}" ]; then
      echo "Invalid choice." >&2
      exit 1
    fi
    export RELAY_DELETE_NAME="${relay_name}"
    python3 - <<'PY'
import json
import os

path = os.environ["CONFIG_PATH"]
relay = os.environ["RELAY_DELETE_NAME"]
outbound = "to-" + relay.removeprefix("relay-")

with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

for inbound in cfg.get("inbounds", []):
    if inbound.get("type") == "vless":
        users = inbound.get("users", [])
        remove_indexes = {idx for idx, user in enumerate(users) if user.get("name") == relay}
        inbound["users"] = [user for idx, user in enumerate(users) if idx not in remove_indexes]
        reality = inbound.get("tls", {}).get("reality", {})
        short_ids = reality.get("short_id", [])
        if remove_indexes and short_ids:
            reality["short_id"] = [sid for idx, sid in enumerate(short_ids) if idx not in remove_indexes]

cfg["outbounds"] = [o for o in cfg.get("outbounds", []) if o.get("tag") != outbound]
route = cfg.setdefault("route", {})
route["rules"] = [r for r in route.get("rules", []) if outbound != r.get("outbound") and relay not in r.get("auth_user", [])]

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"Deleted {relay} and {outbound}")
PY
    chmod 600 "${CONFIG_PATH}"
    apply_or_rollback "${backup}"
    ;;

  4|show-links)
    export CONFIG_PATH NODE_PREFIX REALITY_SERVER_NAME REALITY_PUBLIC_KEY ACCESS_HOST
    python3 - <<'PY'
import json
import os

path = os.environ["CONFIG_PATH"]
node_prefix = os.environ.get("NODE_PREFIX", "NODE")
server_name = os.environ["REALITY_SERVER_NAME"]
public_key = os.environ["REALITY_PUBLIC_KEY"]
access_host = os.environ["ACCESS_HOST"]

with open(path, "r", encoding="utf-8") as f:
    cfg = json.load(f)

found = False
for inbound in cfg.get("inbounds", []):
    tls = inbound.get("tls", {})
    reality = tls.get("reality", {})
    if inbound.get("type") != "vless" or reality.get("enabled") is not True:
        continue
    short_ids = reality.get("short_id", [])
    users = inbound.get("users", [])
    for idx, user in enumerate(users):
        name = user.get("name", "user")
        uuid = user.get("uuid", "")
        sid = short_ids[idx] if idx < len(short_ids) else ""
        link = f"vless://{uuid}@{access_host}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni={server_name}&fp=chrome&pbk={public_key}&sid={sid}&type=tcp&headerType=none#{node_prefix}-{name}"
        print()
        print(name)
        print(link)
        found = True
if not found:
    print("No Reality links found.")
PY
    ;;

  5|backup)
    backup_dir="$(backup_state manual)"
    echo "Backup saved: ${backup_dir}"
    ;;

  6|restore-latest)
    latest="$(latest_backup_dir)"
    if [ -z "${latest}" ] || [ ! -d "${latest}" ]; then
      echo "No backup found under ${BACKUP_ROOT}." >&2
      exit 1
    fi
    if [ ! -r "${latest}/config.json" ]; then
      echo "Latest backup has no config.json: ${latest}" >&2
      exit 1
    fi

    if [ "${CONFIRM_RESTORE:-0}" != "1" ]; then
      if [ -r /dev/tty ]; then
        echo "Latest backup: ${latest}" > /dev/tty
        echo "This will replace current config/meta and restart sing-box." > /dev/tty
        printf "Type RESTORE to continue: " > /dev/tty
        read -r confirm < /dev/tty
        [ "${confirm}" = "RESTORE" ] || { echo "Cancelled."; exit 0; }
      else
        echo "No TTY found. Run with CONFIRM_RESTORE=1 sb restore-latest to restore non-interactively." >&2
        exit 1
      fi
    fi

    rollback_dir="$(backup_state before-restore)"
    cp "${latest}/config.json" "${CONFIG_PATH}"
    if [ -r "${latest}/reality-meta.env" ]; then
      cp "${latest}/reality-meta.env" "${META_PATH}"
    fi
    chmod 600 "${CONFIG_PATH}" "${META_PATH}" 2>/dev/null || true
    if ! "${SINGBOX_BIN}" check -c "${CONFIG_PATH}"; then
      cp "${rollback_dir}/config.json" "${CONFIG_PATH}"
      [ -r "${rollback_dir}/reality-meta.env" ] && cp "${rollback_dir}/reality-meta.env" "${META_PATH}"
      chmod 600 "${CONFIG_PATH}" "${META_PATH}" 2>/dev/null || true
      echo "Restored config failed check. Rolled back to: ${rollback_dir}" >&2
      exit 1
    fi
    restart_singbox
    echo "Restored backup: ${latest}"
    echo "Rollback backup: ${rollback_dir}"
    ;;

  7|update-core)
    [ -x "${SINGBOX_BIN}" ] || { echo "Current sing-box binary not found: ${SINGBOX_BIN}" >&2; exit 1; }

    detect_arch_runtime() {
      case "$(uname -m)" in
        x86_64|amd64) SB_ARCH="amd64" ;;
        aarch64|arm64) SB_ARCH="arm64" ;;
        *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
      esac
    }

    latest_version_runtime() {
      if [ -n "${SINGBOX_VERSION:-}" ]; then
        printf '%s' "${SINGBOX_VERSION#v}"
        return
      fi
      version="$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null \
        | sed -n 's/.*"tag_name":[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' \
        | head -n 1)"
      if [ -z "${version}" ]; then
        latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/SagerNet/sing-box/releases/latest 2>/dev/null || true)"
        version="$(printf '%s' "${latest_url}" | sed -n 's#.*/tag/v\{0,1\}\([^/]*\)$#\1#p')"
      fi
      [ -n "${version}" ] || { echo "Cannot detect latest sing-box version. Set SINGBOX_VERSION manually." >&2; exit 1; }
      printf '%s' "${version}"
    }

    detect_arch_runtime
    version="$(latest_version_runtime)"
    if [ -r /etc/alpine-release ]; then
      suffixes="musl standard"
    else
      suffixes="glibc standard"
    fi

    update_backup="$(backup_state update-core)"
    tmp_dir="$(mktemp -d)"
    archive=""
    dir=""
    for suffix in ${suffixes}; do
      if [ "${suffix}" = "standard" ]; then
        candidate_archive="sing-box-${version}-linux-${SB_ARCH}.tar.gz"
        candidate_dir="sing-box-${version}-linux-${SB_ARCH}"
      else
        candidate_archive="sing-box-${version}-linux-${SB_ARCH}-${suffix}.tar.gz"
        candidate_dir="sing-box-${version}-linux-${SB_ARCH}-${suffix}"
      fi
      url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${candidate_archive}"
      echo "Trying sing-box ${version}: ${candidate_archive}"
      if (cd "${tmp_dir}" && curl -fL -O "${url}"); then
        archive="${candidate_archive}"
        dir="${candidate_dir}"
        break
      fi
    done

    if [ -z "${archive}" ]; then
      rm -rf "${tmp_dir}"
      echo "Failed to download sing-box ${version}." >&2
      exit 1
    fi

    (
      cd "${tmp_dir}"
      tar -xzf "${archive}"
      if [ -x "${dir}/sing-box" ]; then
        install -m 755 "${dir}/sing-box" "${SINGBOX_BIN}"
      else
        found_bin="$(find . -type f -name sing-box -perm -111 | head -n 1)"
        [ -n "${found_bin}" ] || { echo "sing-box binary not found inside ${archive}." >&2; exit 1; }
        install -m 755 "${found_bin}" "${SINGBOX_BIN}"
      fi
    )
    rm -rf "${tmp_dir}"

    if ! "${SINGBOX_BIN}" check -c "${CONFIG_PATH}"; then
      cp "${update_backup}/sing-box" "${SINGBOX_BIN}"
      chmod 755 "${SINGBOX_BIN}"
      echo "New sing-box failed config check. Restored old binary from: ${update_backup}" >&2
      exit 1
    fi

    if ! restart_singbox; then
      cp "${update_backup}/sing-box" "${SINGBOX_BIN}"
      chmod 755 "${SINGBOX_BIN}"
      restart_singbox || true
      echo "Restart failed. Restored old binary from: ${update_backup}" >&2
      exit 1
    fi

    echo "sing-box core updated to ${version}."
    echo "Backup: ${update_backup}"
    ;;

  0|exit)
    exit 0
    ;;

  *)
    echo "Unknown choice: ${menu_choice}" >&2
    exit 1
    ;;
esac
EOF
  chmod 700 "${manager_path}"
  ln -sf "${manager_path}" /usr/local/bin/-sb
}
