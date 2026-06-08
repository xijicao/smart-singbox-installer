#!/usr/bin/env sh

profile_home_defaults() {
  HOME_NODE_NAME="${HOME_NODE_NAME:-home}"
  HOME_MODE="${HOME_MODE:-}"
  REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-}"
  ACCESS_HOST_FALLBACK="YOUR_HOME_IP_OR_DOMAIN"

  SS2022_METHOD="${SS2022_METHOD:-2022-blake3-aes-256-gcm}"
  SS2022_PORT="${SS2022_PORT:-8443}"
  REALITY_PORT="${REALITY_PORT:-443}"
  PUBLIC_ACCESS_HOST="${PUBLIC_ACCESS_HOST:-${ACCESS_HOST:-}}"
  PUBLIC_SS2022_PORT="${PUBLIC_SS2022_PORT:-${SS2022_PORT}}"
  PUBLIC_REALITY_PORT="${PUBLIC_REALITY_PORT:-${REALITY_PORT}}"

  INFO_PATH="/root/home-singbox-info.txt"
}

choose_home_mode() {
  if [ -n "${HOME_MODE}" ]; then
    return
  fi

  if [ ! -r /dev/tty ]; then
    HOME_MODE="ss2022"
    return
  fi

  echo "Choose home/NAT install mode:" > /dev/tty
  echo "  1) ss2022 only, for HK/DMIT relay landing" > /dev/tty
  echo "  2) reality only, direct client connection" > /dev/tty
  echo "  3) both, direct Reality + SS2022 landing" > /dev/tty
  printf "Enter choice [1]: " > /dev/tty
  read -r mode_choice < /dev/tty
  case "${mode_choice:-1}" in
    1) HOME_MODE="ss2022" ;;
    2) HOME_MODE="reality" ;;
    3) HOME_MODE="both" ;;
    *) fail "Invalid HOME_MODE choice: ${mode_choice}" ;;
  esac
}

choose_reality_server_name() {
  if ! json_bool_mode_has_reality; then
    return
  fi

  if [ -n "${REALITY_SERVER_NAME}" ]; then
    return
  fi

  if [ ! -r /dev/tty ]; then
    REALITY_SERVER_NAME="www.sony.jp"
    return
  fi

  echo "Choose Reality handshake/SNI region:" > /dev/tty
  echo "  1) JP - www.sony.jp" > /dev/tty
  echo "  2) TW - www.cht.com.tw" > /dev/tty
  echo "  3) HK - www.hkex.com.hk" > /dev/tty
  echo "  4) US - reed.edu" > /dev/tty
  echo "  5) EU - www.siemens.com" > /dev/tty
  echo "  6) Custom domain" > /dev/tty
  printf "Enter choice [1]: " > /dev/tty
  read -r sni_choice < /dev/tty

  case "${sni_choice:-1}" in
    1) REALITY_SERVER_NAME="www.sony.jp" ;;
    2) REALITY_SERVER_NAME="www.cht.com.tw" ;;
    3) REALITY_SERVER_NAME="www.hkex.com.hk" ;;
    4) REALITY_SERVER_NAME="reed.edu" ;;
    5) REALITY_SERVER_NAME="www.siemens.com" ;;
    6)
      printf "Enter Reality handshake/SNI domain: " > /dev/tty
      read -r REALITY_SERVER_NAME < /dev/tty
      ;;
    *) fail "Invalid Reality SNI choice: ${sni_choice}" ;;
  esac
}

validate_home_mode() {
  case "${HOME_MODE}" in
    ss2022|reality|both) ;;
    *) fail "HOME_MODE must be ss2022, reality or both." ;;
  esac
}

validate_reality_server_name() {
  if ! json_bool_mode_has_reality; then
    return
  fi

  case "${REALITY_SERVER_NAME}" in
    ''|*' '*|http://*|https://*|*/*)
      fail "REALITY_SERVER_NAME must be a plain domain, for example www.sony.jp"
      ;;
  esac
}

validate_tcp_port() {
  port_name="$1"
  port_value="$2"

  case "${port_value}" in
    ''|*[!0-9]*)
      fail "${port_name} must be a TCP port number from 1 to 65535, got: ${port_value}"
      ;;
  esac

  if [ "${port_value}" -lt 1 ] || [ "${port_value}" -gt 65535 ]; then
    fail "${port_name} must be a TCP port number from 1 to 65535, got: ${port_value}"
  fi
}

validate_home_ports() {
  if json_bool_mode_has_ss2022; then
    validate_tcp_port "SS2022_PORT" "${SS2022_PORT}"
    validate_tcp_port "PUBLIC_SS2022_PORT" "${PUBLIC_SS2022_PORT}"
  fi

  if json_bool_mode_has_reality; then
    validate_tcp_port "REALITY_PORT" "${REALITY_PORT}"
    validate_tcp_port "PUBLIC_REALITY_PORT" "${PUBLIC_REALITY_PORT}"
  fi

  if [ "${HOME_MODE}" = "both" ]; then
    if [ "${SS2022_PORT}" = "${REALITY_PORT}" ]; then
      fail "HOME_MODE=both requires different internal ports. Set SS2022_PORT and REALITY_PORT to different values."
    fi
    if [ "${PUBLIC_SS2022_PORT}" = "${PUBLIC_REALITY_PORT}" ]; then
      fail "HOME_MODE=both requires different public ports. Set PUBLIC_SS2022_PORT and PUBLIC_REALITY_PORT to different values."
    fi
  fi
}

finalize_public_export_values() {
  if [ -z "${PUBLIC_ACCESS_HOST}" ]; then
    PUBLIC_ACCESS_HOST="${ACCESS_HOST}"
  fi
  if [ -z "${PUBLIC_SS2022_PORT}" ]; then
    PUBLIC_SS2022_PORT="${SS2022_PORT}"
  fi
  if [ -z "${PUBLIC_REALITY_PORT}" ]; then
    PUBLIC_REALITY_PORT="${REALITY_PORT}"
  fi
}
build_ss_uri() {
  python3 - <<PY
import base64
from urllib.parse import quote
method = "${SS2022_METHOD}"
password = "${SS2022_PASSWORD}"
server = "${PUBLIC_ACCESS_HOST:-${ACCESS_HOST}}"
port = "${PUBLIC_SS2022_PORT}"
name = "${HOME_NODE_NAME}-SS2022"
raw = f"{method}:{password}@{server}:{port}"
encoded = base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")
print(f"ss://{encoded}#{quote(name)}")
PY
}

build_ss_uri_editable() {
  python3 - <<PY
from urllib.parse import quote
method = "${SS2022_METHOD}"
password = "${SS2022_PASSWORD}"
server = "${PUBLIC_ACCESS_HOST:-${ACCESS_HOST}}"
port = "${PUBLIC_SS2022_PORT}"
name = "${HOME_NODE_NAME}-SS2022"
print(f"ss://{method}:{quote(password, safe='')}@{server}:{port}#{quote(name)}")
PY
}

profile_home_generate_values() {
  case "${HOME_MODE}" in
    ss2022|both)
      SS2022_PASSWORD="${SS2022_PASSWORD:-$(singbox_rand_base64_32)}"
      ;;
  esac

  case "${HOME_MODE}" in
    reality|both)
      REALITY_USER_NAME="${REALITY_USER_NAME:-${HOME_NODE_NAME}-direct}"
      REALITY_UUID="${REALITY_UUID:-$(random_uuid)}"
      REALITY_SHORT_ID="$(random_hex 4)"
      generate_reality_keypair
      ;;
  esac
}

json_bool_mode_has_ss2022() {
  [ "${HOME_MODE}" = "ss2022" ] || [ "${HOME_MODE}" = "both" ]
}

json_bool_mode_has_reality() {
  [ "${HOME_MODE}" = "reality" ] || [ "${HOME_MODE}" = "both" ]
}

profile_home_write_config() {
  mkdir -p "${CONFIG_DIR}"

  inbound_sep=""
  cat > "${CONFIG_PATH}" <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "local",
        "tag": "dns_local"
      }
    ],
    "final": "dns_local",
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
EOF

  if json_bool_mode_has_reality; then
    cat >> "${CONFIG_PATH}" <<EOF
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "::",
      "listen_port": ${REALITY_PORT},
      "tcp_fast_open": true,
      "users": [
        {
          "name": "${REALITY_USER_NAME}",
          "uuid": "${REALITY_UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SERVER_NAME}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_SERVER_NAME}",
            "server_port": 443
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": [
            "${REALITY_SHORT_ID}"
          ],
          "max_time_difference": "1m"
        }
      }
    }
EOF
    inbound_sep=","
  fi

  if json_bool_mode_has_ss2022; then
    if [ -n "${inbound_sep}" ]; then
      printf ',\n' >> "${CONFIG_PATH}"
    fi
    cat >> "${CONFIG_PATH}" <<EOF
    {
      "type": "shadowsocks",
      "tag": "ss2022-in",
      "listen": "::",
      "listen_port": ${SS2022_PORT},
      "method": "${SS2022_METHOD}",
      "password": "${SS2022_PASSWORD}",
      "network": [
        "tcp"
      ]
    }
EOF
  fi

  cat >> "${CONFIG_PATH}" <<EOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "default_domain_resolver": "dns_local",
    "auto_detect_interface": true,
    "final": "direct"
  }
}
EOF
}

profile_home_write_info() {
  umask 077
  cat > "${INFO_PATH}" <<EOF
Home/NAT sing-box install completed
===================================

Node name: ${HOME_NODE_NAME}
Mode: ${HOME_MODE}
Access host: ${ACCESS_HOST}
Public access host in exported links: ${PUBLIC_ACCESS_HOST:-${ACCESS_HOST}}
EOF

  if json_bool_mode_has_ss2022; then
    cat >> "${INFO_PATH}" <<EOF

SS2022 landing for HK/DMIT relay
--------------------------------
name: ${HOME_NODE_NAME}
server: ${PUBLIC_ACCESS_HOST:-${ACCESS_HOST}}
port: ${PUBLIC_SS2022_PORT}
listen_port_inside_server: ${SS2022_PORT}
method: ${SS2022_METHOD}
password: ${SS2022_PASSWORD}
network: tcp
ss_link:
$(build_ss_uri)

ss_link_editable:
$(build_ss_uri_editable)

Paste the ss_link into sing-box-add-ss2022-relay on HK or DMIT.
If this is a NAT/LXC panel mapping such as public 24496 -> internal ${SS2022_PORT}, edit the port in ss_link_editable to 24496 before pasting it into HK/DMIT.
EOF
  fi

  if json_bool_mode_has_reality; then
    cat >> "${INFO_PATH}" <<EOF

Reality direct node
-------------------
handshake domain: ${REALITY_SERVER_NAME}
public key: ${REALITY_PUBLIC_KEY}
private key: ${REALITY_PRIVATE_KEY}
user: ${REALITY_USER_NAME}
uuid: ${REALITY_UUID}
short_id: ${REALITY_SHORT_ID}
link:
vless://${REALITY_UUID}@${PUBLIC_ACCESS_HOST:-${ACCESS_HOST}}:${PUBLIC_REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&headerType=none#${HOME_NODE_NAME}-Reality
EOF
  fi

  cat >> "${INFO_PATH}" <<EOF

Notes
-----
1. If ACCESS_HOST is private or wrong, replace it with public IP/domain in client or relay importer.
2. For NAT/LXC panel mapping, sing-box listens on internal TCP ${SS2022_PORT}; HK/DMIT must connect to the public mapped TCP port.
3. For Reality, map public TCP ${PUBLIC_REALITY_PORT} to internal TCP ${REALITY_PORT} when Reality is enabled.
4. The ss_link_editable line is easier to hand-edit. For example, if the panel maps 24496 -> ${SS2022_PORT}, change the editable link port to 24496 before importing it on HK/DMIT.
EOF
  write_info_file "${INFO_PATH}"
}

profile_home_finish() {
  echo
  echo "Installation finished: home landing"
  echo "Info file: ${INFO_PATH}"
  echo
  echo "Useful checks:"
  echo "sing-box check -c /etc/sing-box/config.json"
  echo "cat ${INFO_PATH}"
  echo "ls -l ${INFO_PATH}"
  echo "NAT reminder: local ss checks use internal listen ports; HK/DMIT imports must use the public mapped port."
  if json_bool_mode_has_ss2022; then echo "ss -lnpt | grep ':${SS2022_PORT}'"; fi
  if json_bool_mode_has_reality; then echo "ss -lnpt | grep ':${REALITY_PORT}'"; fi
}

profile_main() {
  require_root_common
  require_os_family alpine
  profile_home_defaults
  choose_home_mode
  validate_home_mode
  choose_reality_server_name
  validate_reality_server_name
  validate_home_ports
  install_alpine_dependencies
  install_singbox_tarball musl
  profile_home_generate_values
  detect_access_host
  finalize_public_export_values
  profile_home_write_config
  write_openrc_service
  ports=""
  if json_bool_mode_has_ss2022; then ports="${SS2022_PORT}"; fi
  if json_bool_mode_has_reality; then ports="${ports} ${REALITY_PORT}"; fi
  write_alpine_healthcheck "${ports}"
  write_home_uninstall_script
  write_home_restore_script
  enable_openrc_singbox
  profile_home_write_info
  profile_home_finish
}
