#!/usr/bin/env sh

profile_defaults() {
  NODE_PREFIX="${NODE_PREFIX:-HK}"
  REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.hkex.com.hk}"
  ACCESS_HOST_FALLBACK="YOUR_HK_IP_OR_DOMAIN"

  ME_NAME="${ME_NAME:-me-direct}"
  FRIEND_NAME="${FRIEND_NAME:-friend-direct}"
  INFO_PATH="/root/hk-singbox-info.txt"
}

profile_generate_values() {
  ME_UUID="${ME_UUID:-$(random_uuid)}"
  FRIEND_UUID="${FRIEND_UUID:-$(random_uuid)}"
  ME_SHORT_ID="$(random_hex 4)"
  FRIEND_SHORT_ID="$(random_hex 4)"
  generate_reality_keypair
}

profile_write_config() {
  mkdir -p "${CONFIG_DIR}"
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
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "::",
      "listen_port": 443,
      "tcp_fast_open": true,
      "users": [
        {
          "name": "${ME_NAME}",
          "uuid": "${ME_UUID}",
          "flow": "xtls-rprx-vision"
        },
        {
          "name": "${FRIEND_NAME}",
          "uuid": "${FRIEND_UUID}",
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
            "${ME_SHORT_ID}",
            "${FRIEND_SHORT_ID}"
          ],
          "max_time_difference": "1m"
        }
      }
    }
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
    "rules": [
      {
        "auth_user": [
          "${ME_NAME}",
          "${FRIEND_NAME}"
        ],
        "action": "route",
        "outbound": "direct"
      }
    ],
    "final": "direct"
  }
}
EOF
}

profile_write_info() {
  umask 077
  cat > "${INFO_PATH}" <<EOF
HK main Reality entry and relay hub installed
=============================================

Role:
  10 Mbps IPv4-only main entry.
  International relay hub for home/NAT SS2022 landings.
  Two base users: you and friend.
  Add one relay node per home landing with sing-box-add-ss2022-relay.

Reality handshake domain: ${REALITY_SERVER_NAME}
Reality public key: ${REALITY_PUBLIC_KEY}
Reality private key: ${REALITY_PRIVATE_KEY}
Access host used for exported links: ${ACCESS_HOST}

Your HK direct node
-------------------
name: ${ME_NAME}
uuid: ${ME_UUID}
short_id: ${ME_SHORT_ID}
link:
vless://${ME_UUID}@${ACCESS_HOST}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${ME_SHORT_ID}&type=tcp&headerType=none#${NODE_PREFIX}-${ME_NAME}

Friend HK direct node
---------------------
name: ${FRIEND_NAME}
uuid: ${FRIEND_UUID}
short_id: ${FRIEND_SHORT_ID}
link:
vless://${FRIEND_UUID}@${ACCESS_HOST}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${FRIEND_SHORT_ID}&type=tcp&headerType=none#${NODE_PREFIX}-${FRIEND_NAME}

Add a home SS2022 landing later
-------------------------------
Run this on HK:

sing-box-add-ss2022-relay

Example relay names:
  jp-home
  tw-home
  us-home
  eu-home

The tool will add a matching HK Reality relay node for manual switching.
EOF
  write_info_file "${INFO_PATH}"
}

profile_show_finish() {
  echo
  echo "Installation finished: hk-debian"
  echo "Client info: ${INFO_PATH}"
  echo "Relay importer: /usr/local/bin/sing-box-add-ss2022-relay"
  echo "Manager menu: sb or -sb"
  echo
  echo "Useful checks:"
  echo "systemctl status sing-box --no-pager"
  echo "sing-box check -c /etc/sing-box/config.json"
  echo "ss -lnpt | grep ':443'"
  echo "cat ${INFO_PATH}"
  echo "ls -l ${INFO_PATH} /etc/sing-box/reality-meta.env"
}

profile_main() {
  require_root_common
  require_os_family debian
  profile_defaults
  install_debian_dependencies
  install_singbox_tarball glibc
  profile_generate_values
  detect_access_host
  profile_write_config
  write_systemd_service
  maybe_enable_nftables_443
  enable_systemd_singbox
  write_reality_meta
  write_ss2022_relay_importer
  write_sb_manager
  profile_write_info
  profile_show_finish
}