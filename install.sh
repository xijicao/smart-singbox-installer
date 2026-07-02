#!/usr/bin/env bash
# smart-singbox-installer-final
# Debian 专用 sing-box 入口机 / 落地机安装与管理脚本
# 设计目标：少维护、可回滚、链接清楚、网络调优分档，不做面板化大杂烩。

set -Eeuo pipefail
umask 077

VERSION="2026.07.02-final"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
ENV_FILE="$CONFIG_DIR/sb.env"
BACKUP_DIR="$CONFIG_DIR/backups"
SB_BIN="/usr/local/bin/sb"
SCRIPT_SELF="${BASH_SOURCE[0]}"
NFT_CONF="/etc/nftables.conf"
JOURNALD_CONF_DIR="/etc/systemd/journald.conf.d"
JOURNALD_CONF="$JOURNALD_CONF_DIR/99-smart-singbox.conf"
SYSCTL_CONF="/etc/sysctl.d/99-smart-singbox.conf"
TC_SERVICE="/etc/systemd/system/sb-tc.service"
TC_ENV="/etc/default/sb-tc"

# ===== 基础输出 =====
red(){ printf '\033[31m%s\033[0m\n' "$*"; }
green(){ printf '\033[32m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
blue(){ printf '\033[34m%s\033[0m\n' "$*"; }
die(){ red "错误：$*"; exit 1; }
need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || die "请使用 root 执行。"; }

pause(){ read -r -p "按回车继续..." _ || true; }

ask(){
  local prompt="$1" default="${2:-}" value
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " value || true
    printf '%s' "${value:-$default}"
  else
    read -r -p "$prompt: " value || true
    printf '%s' "$value"
  fi
}

confirm(){
  local prompt="$1" default="${2:-y}" ans
  read -r -p "$prompt [$default]: " ans || true
  ans="${ans:-$default}"
  case "$ans" in y|Y|yes|YES|是) return 0;; *) return 1;; esac
}

urlencode(){
  python3 - "$1" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
}

b64url(){
  python3 - "$1" <<'PY'
import sys, base64
s=sys.argv[1].encode()
print(base64.urlsafe_b64encode(s).decode().rstrip('='))
PY
}

link_host(){
  # 链接里的 IPv6 host 需要加方括号；IPv4/域名原样输出。
  local h="$1"
  if [[ "$h" == *:* && "$h" != \[*\] ]]; then
    printf '[%s]' "$h"
  else
    printf '%s' "$h"
  fi
}

rand_hex(){ openssl rand -hex "${1:-8}"; }
rand_b64(){
  local n="${1:-16}"
  if command -v sing-box >/dev/null 2>&1; then
    sing-box generate rand --base64 "$n" 2>/dev/null || openssl rand -base64 "$n"
  else
    openssl rand -base64 "$n"
  fi
}

new_uuid(){ cat /proc/sys/kernel/random/uuid; }

safe_name(){
  # 只允许常见节点/用户命名字符，避免写坏 JSON 或链接名称。
  printf '%s' "$1" | tr -cd 'A-Za-z0-9._-'
}

load_env(){
  [ -f "$ENV_FILE" ] || die "未找到 $ENV_FILE，请先安装。"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

save_env_kv(){
  local k="$1" v="$2"
  mkdir -p "$CONFIG_DIR"
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  if grep -q "^${k}=" "$ENV_FILE"; then
    sed -i "s|^${k}=.*|${k}=$(printf '%q' "$v")|" "$ENV_FILE"
  else
    printf '%s=%q\n' "$k" "$v" >> "$ENV_FILE"
  fi
}

backup_config(){
  mkdir -p "$BACKUP_DIR"
  if [ -f "$CONFIG_FILE" ]; then
    cp -a "$CONFIG_FILE" "$BACKUP_DIR/config.$(date +%Y%m%d-%H%M%S).json"
  fi
}

restore_latest(){
  local latest
  latest=$(ls -1t "$BACKUP_DIR"/config.*.json 2>/dev/null | head -n1 || true)
  [ -n "$latest" ] || die "没有找到备份。"
  cp -a "$latest" "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  restart_singbox
  green "已恢复：$latest"
}

check_config(){
  sing-box check -c "$CONFIG_FILE"
}

check_or_fallback_dns(){
  # sing-box 版本变化很快：如果全局 dns.strategy 在未来版本不可用，就自动删除后再检查。
  if sing-box check -c "$CONFIG_FILE" >/tmp/sb-check.log 2>&1; then
    return 0
  fi
  yellow "sing-box check 未通过，尝试移除 dns.strategy 兼容新版 sing-box..."
  cp -a "$CONFIG_FILE" "$CONFIG_FILE.tmp"
  jq 'if .dns then del(.dns.strategy) else . end' "$CONFIG_FILE.tmp" > "$CONFIG_FILE"
  rm -f "$CONFIG_FILE.tmp"
  sing-box check -c "$CONFIG_FILE"
}

restart_singbox(){
  systemctl daemon-reload
  systemctl enable --now sing-box >/dev/null 2>&1 || true
  systemctl restart sing-box
}

apply_checked_config(){
  check_or_fallback_dns || { yellow "配置检查失败，尝试恢复最新备份。"; restore_latest; exit 1; }
  restart_singbox
}

# ===== 系统与依赖 =====
check_debian(){
  [ -r /etc/os-release ] || die "无法识别系统。"
  # shellcheck disable=SC1091
  . /etc/os-release
  [ "${ID:-}" = "debian" ] || die "本版本只支持 Debian。当前系统：${PRETTY_NAME:-unknown}"
  case "${VERSION_ID:-}" in
    12|13) green "检测到 ${PRETTY_NAME}，继续。";;
    *) yellow "当前是 ${PRETTY_NAME}。脚本主要测试 Debian 12/13，仍尝试继续。";;
  esac
}

install_deps(){
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl ca-certificates jq openssl nftables iproute2 systemd python3 procps
}

install_singbox(){
  if command -v sing-box >/dev/null 2>&1; then
    yellow "已检测到 sing-box：$(sing-box version | head -n1)"
    if ! confirm "是否使用官方脚本更新 sing-box？" "n"; then
      return 0
    fi
  fi
  yellow "开始安装/更新 sing-box（官方安装脚本）。"
  curl -fsSL https://sing-box.app/install.sh | sh
  command -v sing-box >/dev/null 2>&1 || die "sing-box 安装失败。"
}

install_systemd_service(){
  cat > /etc/systemd/system/sing-box.service <<EOF2
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
ExecStart=$(command -v sing-box) run -c $CONFIG_FILE
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF2
  systemctl daemon-reload
}

install_self(){
  cp -a "$SCRIPT_SELF" "$SB_BIN"
  chmod 700 "$SB_BIN"
  green "已安装管理命令：sb"
}

setup_journald(){
  mkdir -p "$JOURNALD_CONF_DIR"
  cat > "$JOURNALD_CONF" <<'EOF2'
[Journal]
# 中文说明：限制 systemd journal，避免 sing-box 或系统日志长期堆积。
SystemMaxUse=200M
SystemMaxFileSize=50M
MaxRetentionSec=14day
EOF2
  systemctl restart systemd-journald || true
}

# ===== sing-box 配置生成 =====
base_config(){
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<'JSON'
{
  "log": {
    "disabled": false,
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "local",
        "type": "local"
      }
    ],
    "final": "local",
    "strategy": "prefer_ipv4"
  },
  "inbounds": [],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "rules": [],
    "final": "direct"
  }
}
JSON
  chmod 600 "$CONFIG_FILE"
}

reality_keypair(){
  local out priv pub
  out=$(sing-box generate reality-keypair)
  priv=$(printf '%s\n' "$out" | awk -F': ' '/PrivateKey|Private key|Private/ {print $2; exit}')
  pub=$(printf '%s\n' "$out" | awk -F': ' '/PublicKey|Public key|Public/ {print $2; exit}')
  [ -n "$priv" ] && [ -n "$pub" ] || die "Reality keypair 生成失败：$out"
  printf '%s %s\n' "$priv" "$pub"
}

add_reality_inbound_initial(){
  local node_host="$1" port="$2" sni="$3" username="$4" uuid="$5" priv="$6" pub="$7" sid="$8"
  jq --argjson port "$port" --arg sni "$sni" --arg user "$username" --arg uuid "$uuid" --arg priv "$priv" --arg sid "$sid" \
    '.inbounds += [{
      "type":"vless",
      "tag":"reality-in",
      "listen":"0.0.0.0",
      "listen_port":$port,
      "sniff":true,
      "sniff_override_destination":true,
      "users":[{"name":$user,"uuid":$uuid,"flow":"xtls-rprx-vision"}],
      "tls":{
        "enabled":true,
        "server_name":$sni,
        "reality":{
          "enabled":true,
          "handshake":{"server":$sni,"server_port":443},
          "private_key":$priv,
          "short_id":[$sid]
        }
      }
    }]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  save_env_kv SB_REALITY_PUBLIC_KEY "$pub"
}

add_ss_inbound_initial(){
  local port="$1" username="$2" server_pass="$3" user_pass="$4"
  jq --argjson port "$port" --arg user "$username" --arg sp "$server_pass" --arg up "$user_pass" \
    '.inbounds += [{
      "type":"shadowsocks",
      "tag":"ss2022-in",
      "listen":"::",
      "listen_port":$port,
      "method":"2022-blake3-aes-128-gcm",
      "password":$sp,
      "users":[{"name":$user,"password":$up}]
    }]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

make_ss_outbound_json(){
  local tag="$1" method="$2" password="$3" server="$4" port="$5"
  jq -n --arg tag "$tag" --arg method "$method" --arg password "$password" --arg server "$server" --argjson port "$port" \
    '{"type":"shadowsocks","tag":$tag,"server":$server,"server_port":$port,"method":$method,"password":$password}'
}

parse_ss_uri(){
  python3 - "$1" <<'PY'
import sys, base64, json, urllib.parse, re
uri=sys.argv[1].strip()
if not uri.startswith('ss://'):
    raise SystemExit('不是 ss:// 链接')
raw=uri[5:]
frag=''
if '#' in raw:
    raw, frag = raw.split('#',1)
frag=urllib.parse.unquote(frag) if frag else ''
query=''
if '?' in raw:
    raw, query = raw.split('?',1)
# 两种常见形式：ss://base64(method:pass@host:port) 或 ss://base64(method:pass)@host:port
if '@' in raw:
    userinfo, hostport = raw.rsplit('@',1)
    try:
        padded=userinfo + '=' * (-len(userinfo)%4)
        decoded=base64.urlsafe_b64decode(padded).decode()
        if ':' in decoded:
            userinfo=decoded
    except Exception:
        userinfo=urllib.parse.unquote(userinfo)
else:
    padded=raw + '=' * (-len(raw)%4)
    decoded=base64.urlsafe_b64decode(padded).decode()
    if '@' not in decoded:
        raise SystemExit('无法解析 ss:// 链接')
    userinfo, hostport=decoded.rsplit('@',1)
if ':' not in userinfo:
    raise SystemExit('userinfo 缺少 method:password')
method, password=userinfo.split(':',1)
if hostport.startswith('['):
    m=re.match(r'^\[([^\]]+)\]:(\d+)$', hostport)
    if not m: raise SystemExit('IPv6 host:port 解析失败')
    server, port=m.group(1), int(m.group(2))
else:
    if ':' not in hostport: raise SystemExit('host:port 缺失')
    server, port_s=hostport.rsplit(':',1)
    port=int(port_s)
print(json.dumps({"method":method,"password":password,"server":server,"port":port,"name":frag}, ensure_ascii=False))
PY
}

# ===== 链接生成 =====
vless_link_for_user(){
  load_env
  local user="$1" uuid name enc_name enc_sni host port pub sid sni
  uuid=$(jq -r --arg u "$user" '.inbounds[]?|select(.tag=="reality-in")|.users[]?|select(.name==$u)|.uuid' "$CONFIG_FILE")
  [ -n "$uuid" ] && [ "$uuid" != "null" ] || return 0
  host=$(link_host "${SB_NODE_HOST:-}")
  port="${SB_REALITY_PORT:-443}"
  sni="${SB_REALITY_SNI:-}"
  pub="${SB_REALITY_PUBLIC_KEY:-}"
  sid="${SB_REALITY_SHORT_ID:-}"
  name="${SB_NODE_NAME:-NODE}-R-${user}"
  enc_name=$(urlencode "$name")
  enc_sni=$(urlencode "$sni")
  printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&headerType=none#%s\n' \
    "$uuid" "$host" "$port" "$enc_sni" "$pub" "$sid" "$enc_name"
}

ss_link_for_user(){
  load_env
  local user="$1" up sp method host port name enc_name userinfo b64
  up=$(jq -r --arg u "$user" '.inbounds[]?|select(.tag=="ss2022-in")|.users[]?|select(.name==$u)|.password' "$CONFIG_FILE")
  [ -n "$up" ] && [ "$up" != "null" ] || return 0
  sp=$(jq -r '.inbounds[]?|select(.tag=="ss2022-in")|.password' "$CONFIG_FILE")
  method=$(jq -r '.inbounds[]?|select(.tag=="ss2022-in")|.method' "$CONFIG_FILE")
  host=$(link_host "${SB_NODE_HOST:-}")
  port="${SB_SS_PORT:-8443}"
  name="${SB_NODE_NAME:-NODE}-SS-${user}"
  enc_name=$(urlencode "$name")
  # SS2022 多用户客户端密码格式：ServerPassword:UserPassword
  userinfo="${method}:${sp}:${up}"
  b64=$(b64url "$userinfo")
  printf 'ss://%s@%s:%s#%s\n' "$b64" "$host" "$port" "$enc_name"
}

landing_vless_link(){
  load_env
  local landing="$1" user="relay-$landing" uuid name enc_name enc_sni host port pub sid sni
  uuid=$(jq -r --arg u "$user" '.inbounds[]?|select(.tag=="reality-in")|.users[]?|select(.name==$u)|.uuid' "$CONFIG_FILE")
  [ -n "$uuid" ] && [ "$uuid" != "null" ] || return 0
  host=$(link_host "${SB_NODE_HOST:-}")
  port="${SB_REALITY_PORT:-443}"
  sni="${SB_REALITY_SNI:-}"
  pub="${SB_REALITY_PUBLIC_KEY:-}"
  sid="${SB_REALITY_SHORT_ID:-}"
  name="${SB_NODE_NAME:-NODE}-DE-${landing}"
  enc_name=$(urlencode "$name")
  enc_sni=$(urlencode "$sni")
  printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&headerType=none#%s\n' \
    "$uuid" "$host" "$port" "$enc_sni" "$pub" "$sid" "$enc_name"
}

show_links(){
  load_env
  echo
  yellow "敏感提醒：下面的链接包含密钥，请不要公开上传或发到公共群。"
  echo
  if [ "${SB_ROLE:-}" = "entry" ]; then
    echo "===== Reality 用户 ====="
    jq -r '.inbounds[]?|select(.tag=="reality-in")|.users[]?.name' "$CONFIG_FILE" | while read -r u; do
      case "$u" in relay-*) continue;; esac
      vless_link_for_user "$u"
    done
    echo
    echo "===== SS2022 用户 ====="
    jq -r '.inbounds[]?|select(.tag=="ss2022-in")|.users[]?.name' "$CONFIG_FILE" | while read -r u; do
      ss_link_for_user "$u"
    done
    echo
    echo "===== Landing Relay ====="
    jq -r '.outbounds[]?|select(.tag|startswith("landing-"))|.tag|sub("^landing-";"")' "$CONFIG_FILE" | while read -r l; do
      landing_vless_link "$l"
    done
  else
    echo "===== Landing SS2022 ====="
    jq -r '.inbounds[]?|select(.tag=="ss2022-in")|.users[]?.name' "$CONFIG_FILE" | while read -r u; do
      ss_link_for_user "$u"
    done
  fi
  echo
}

# ===== 用户管理 =====
add_reality_user(){
  load_env
  [ "${SB_ROLE:-}" = "entry" ] || die "只有 Entry 入口机支持 Reality 用户。"
  jq -e '.inbounds[]?|select(.tag=="reality-in")' "$CONFIG_FILE" >/dev/null || die "当前未启用 Reality inbound。"
  local user uuid exists
  user=$(safe_name "${1:-}")
  [ -n "$user" ] || die "用法：sb add-reality friend1"
  exists=$(jq -r --arg u "$user" '.inbounds[]?|select(.tag=="reality-in")|.users[]?|select(.name==$u)|.name' "$CONFIG_FILE")
  [ -z "$exists" ] || die "Reality 用户已存在：$user"
  uuid=$(new_uuid)
  backup_config
  jq --arg u "$user" --arg id "$uuid" '(.inbounds[]|select(.tag=="reality-in").users) += [{"name":$u,"uuid":$id,"flow":"xtls-rprx-vision"}]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  apply_checked_config
  green "已添加 Reality 用户：$user"
  vless_link_for_user "$user"
}

del_reality_user(){
  load_env
  local user
  user=$(safe_name "${1:-}")
  [ -n "$user" ] || die "用法：sb del-reality friend1"
  backup_config
  jq --arg u "$user" '(.inbounds[]?|select(.tag=="reality-in").users) |= map(select(.name!=$u))' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  apply_checked_config
  green "已删除 Reality 用户：$user"
}

add_ss_user(){
  load_env
  jq -e '.inbounds[]?|select(.tag=="ss2022-in")' "$CONFIG_FILE" >/dev/null || die "当前未启用 SS2022 inbound。"
  local user pass exists
  user=$(safe_name "${1:-}")
  [ -n "$user" ] || die "用法：sb add-ss-user friend1"
  exists=$(jq -r --arg u "$user" '.inbounds[]?|select(.tag=="ss2022-in")|.users[]?|select(.name==$u)|.name' "$CONFIG_FILE")
  [ -z "$exists" ] || die "SS2022 用户已存在：$user"
  pass=$(rand_b64 16)
  backup_config
  jq --arg u "$user" --arg p "$pass" '(.inbounds[]|select(.tag=="ss2022-in").users) += [{"name":$u,"password":$p}]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  apply_checked_config
  green "已添加 SS2022 用户：$user"
  ss_link_for_user "$user"
}

del_ss_user(){
  load_env
  local user
  user=$(safe_name "${1:-}")
  [ -n "$user" ] || die "用法：sb del-ss-user friend1"
  backup_config
  jq --arg u "$user" '(.inbounds[]?|select(.tag=="ss2022-in").users) |= map(select(.name!=$u))' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  apply_checked_config
  green "已删除 SS2022 用户：$user"
}

add_landing(){
  load_env
  [ "${SB_ROLE:-}" = "entry" ] || die "只有 Entry 入口机支持导入落地。"
  jq -e '.inbounds[]?|select(.tag=="reality-in")' "$CONFIG_FILE" >/dev/null || die "导入落地需要 Reality inbound，用于生成 relay 链接。"
  local name uri parsed method password server port tag relay_user uuid exists
  name=$(safe_name "${1:-}")
  uri="${2:-}"
  [ -n "$name" ] && [ -n "$uri" ] || die "用法：sb add-landing netcup-de 'ss://...'"
  tag="landing-$name"
  exists=$(jq -r --arg t "$tag" '.outbounds[]?|select(.tag==$t)|.tag' "$CONFIG_FILE")
  [ -z "$exists" ] || die "落地已存在：$name"
  parsed=$(parse_ss_uri "$uri")
  method=$(printf '%s' "$parsed" | jq -r .method)
  password=$(printf '%s' "$parsed" | jq -r .password)
  server=$(printf '%s' "$parsed" | jq -r .server)
  port=$(printf '%s' "$parsed" | jq -r .port)
  relay_user="relay-$name"
  uuid=$(new_uuid)
  backup_config
  # 添加 Shadowsocks outbound、添加 relay 专用 Reality 用户，并用 auth_user 分流到落地 outbound。
  jq --arg tag "$tag" --arg method "$method" --arg password "$password" --arg server "$server" --argjson port "$port" \
     --arg ru "$relay_user" --arg uuid "$uuid" \
    '.outbounds += [{"type":"shadowsocks","tag":$tag,"server":$server,"server_port":$port,"method":$method,"password":$password}]
     | (.inbounds[]|select(.tag=="reality-in").users) += [{"name":$ru,"uuid":$uuid,"flow":"xtls-rprx-vision"}]
     | .route.rules = ([{"inbound":"reality-in","auth_user":$ru,"outbound":$tag}] + (.route.rules // []))' \
     "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  apply_checked_config
  green "已导入落地：$name -> $server:$port"
  landing_vless_link "$name"
}

del_landing(){
  load_env
  local name tag ru
  name=$(safe_name "${1:-}")
  [ -n "$name" ] || die "用法：sb del-landing netcup-de"
  tag="landing-$name"
  ru="relay-$name"
  backup_config
  jq --arg tag "$tag" --arg ru "$ru" \
    '.outbounds |= map(select(.tag!=$tag))
     | (.inbounds[]?|select(.tag=="reality-in").users) |= map(select(.name!=$ru))
     | .route.rules |= map(select(.outbound!=$tag))' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  apply_checked_config
  green "已删除落地：$name"
}

# 旧命令兼容
add_friend(){ add_reality_user "$@"; }
del_user(){ del_reality_user "$@"; }
add_ss_compat(){ add_landing "landing-$(date +%H%M%S)" "$1"; }

# ===== 防火墙 =====
setup_firewall(){
  local ssh_port="$1" reality_port="$2" ss_port="$3" enable_reality="$4" enable_ss="$5"
  cp -a "$NFT_CONF" "$NFT_CONF.bak.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  local tcp_ports="$ssh_port"
  [ "$enable_reality" = "1" ] && tcp_ports="$tcp_ports, $reality_port"
  [ "$enable_ss" = "1" ] && tcp_ports="$tcp_ports, $ss_port"
  cat > "$NFT_CONF" <<EOF2
#!/usr/sbin/nft -f
# smart-singbox-installer 防火墙
# 中文说明：默认丢弃入站，只放行 SSH、Reality、SS2022、ICMP/ICMPv6 与已建立连接。
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif "lo" accept
    ct state established,related accept
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept
    tcp dport { $tcp_ports } accept
EOF2
  if [ "$enable_ss" = "1" ]; then
    cat >> "$NFT_CONF" <<EOF2
    udp dport { $ss_port } accept
EOF2
  fi
  cat >> "$NFT_CONF" <<'EOF2'
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
EOF2
  nft -f "$NFT_CONF"
  systemctl enable --now nftables >/dev/null 2>&1 || true
}

# ===== 网络 profile =====
default_iface(){ ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}'; }

write_sysctl_basic(){
  local limit="$1" buffer32="$2"
  cat > "$SYSCTL_CONF" <<EOF2
# smart-singbox-installer 网络基础优化
# 中文说明：BBR + fq 是通用基础；tcp_mtu_probing=1 用于规避部分 MTU blackhole。
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_limit_output_bytes=$limit
EOF2
  if [ "$buffer32" = "1" ]; then
    cat >> "$SYSCTL_CONF" <<'EOF2'
# 中文说明：32MB 是 TCP 自动调优的上限，不是每条连接固定占用 32MB。
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 16384 33554432
EOF2
  fi
  sysctl --system >/dev/null
}

install_tc_service(){
  local rate="$1" iface="$2"
  cat > "$TC_ENV" <<EOF2
SB_TC_IFACE="$iface"
SB_TC_RATE="$rate"
EOF2
  cat > "$TC_SERVICE" <<'EOF2'
[Unit]
Description=smart-singbox HTB + fq shaper
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/default/sb-tc
RemainAfterExit=yes
ExecStart=/bin/sh -c 'tc qdisc replace dev "$SB_TC_IFACE" root handle 1: htb default 10; tc class replace dev "$SB_TC_IFACE" parent 1: classid 1:10 htb rate "$SB_TC_RATE" ceil "$SB_TC_RATE"; tc qdisc replace dev "$SB_TC_IFACE" parent 1:10 handle 10: fq'
ExecStop=/bin/sh -c 'tc qdisc del dev "$SB_TC_IFACE" root 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
EOF2
  systemctl daemon-reload
  systemctl enable --now sb-tc.service
}

remove_tc_service(){
  systemctl disable --now sb-tc.service >/dev/null 2>&1 || true
  rm -f "$TC_SERVICE" "$TC_ENV"
  systemctl daemon-reload
}

net_install(){
  need_root
  local profile="${1:-}" rate iface
  iface=$(default_iface)
  [ -n "$iface" ] || die "无法识别默认网卡。"
  case "$profile" in
    basic|generic)
      remove_tc_service
      write_sysctl_basic 524288 0
      green "已应用 basic：BBR + fq + MTU probing，不限速。"
      ;;
    dmit-safe|safe)
      rate="800mbit"; write_sysctl_basic 524288 0; install_tc_service "$rate" "$iface"; green "已应用 dmit-safe：$rate + 512KB。";;
    dmit-balanced|balanced)
      rate="900mbit"; write_sysctl_basic 1048576 1; install_tc_service "$rate" "$iface"; green "已应用 dmit-balanced：$rate + 1MB + 32MB buffer。";;
    dmit-performance|performance)
      rate="1000mbit"; write_sysctl_basic 1048576 1; install_tc_service "$rate" "$iface"; green "已应用 dmit-performance：$rate + 1MB + 32MB buffer。";;
    custom)
      rate="${2:-}"; [ -n "$rate" ] || die "用法：sb net-install custom 1200mbit"
      write_sysctl_basic 1048576 1; install_tc_service "$rate" "$iface"; green "已应用 custom：$rate + 1MB + 32MB buffer。";;
    none|off|remove)
      remove_tc_service; green "已移除 HTB 限速服务，sysctl 不变。";;
    *)
      cat <<'EOF2'
用法：
  sb net-install basic              # 通用入口/落地：BBR+fq，不限速
  sb net-install dmit-safe          # DMIT 800M + 512KB
  sb net-install dmit-balanced      # DMIT 900M + 1MB + 32MB buffer
  sb net-install dmit-performance   # DMIT 1000M + 1MB + 32MB buffer
  sb net-install custom 1200mbit    # 自定义速率，不建议长期 2G
  sb net-install remove             # 移除 HTB 限速
EOF2
      ;;
  esac
}

net_status(){
  echo "===== sysctl ====="
  sysctl net.core.default_qdisc net.ipv4.tcp_congestion_control net.ipv4.tcp_mtu_probing net.ipv4.tcp_limit_output_bytes 2>/dev/null || true
  sysctl net.core.rmem_max net.core.wmem_max net.ipv4.tcp_rmem net.ipv4.tcp_wmem 2>/dev/null || true
  echo
  echo "===== tc qdisc ====="
  tc -s qdisc show 2>/dev/null || true
  echo
  echo "===== tc class ====="
  tc -s class show 2>/dev/null || true
  echo
  echo "===== TCP counters ====="
  nstat -az 2>/dev/null | grep -E 'TcpRetransSegs|TcpOutSegs|TcpExtTCPTimeouts|TcpExtTCPLostRetransmit' || true
  echo
  echo "===== journal disk ====="
  journalctl --disk-usage 2>/dev/null || true
}

net_watch(){
  local seconds="${1:-60}"
  [[ "$seconds" =~ ^[0-9]+$ ]] || die "用法：sb net-watch 60"
  local before after
  before=$(mktemp); after=$(mktemp)
  nstat -az > "$before" || true
  yellow "观察 ${seconds}s，不写日志文件，只在屏幕输出..."
  sleep "$seconds"
  nstat -az > "$after" || true
  echo "===== nstat delta ====="
  python3 - "$before" "$after" <<'PY'
import sys
keys=['TcpRetransSegs','TcpOutSegs','TcpExtTCPTimeouts','TcpExtTCPLostRetransmit']
def load(p):
    d={}
    for line in open(p, errors='ignore'):
        parts=line.split()
        if len(parts)>=2 and parts[0] in keys:
            try: d[parts[0]]=int(parts[1])
            except: pass
    return d
b,a=load(sys.argv[1]),load(sys.argv[2])
for k in keys:
    print(f'{k}: {a.get(k,0)-b.get(k,0)}')
out=a.get('TcpOutSegs',0)-b.get('TcpOutSegs',0)
ret=a.get('TcpRetransSegs',0)-b.get('TcpRetransSegs',0)
if out>0:
    print(f'Retrans ratio: {ret/out:.6%}')
PY
  rm -f "$before" "$after"
}

# ===== 安装流程 =====
install_entry(){
  need_root; check_debian; install_deps; install_singbox; install_systemd_service; setup_journald
  local entry_type node host protocol ssh_port reality_port ss_port sni user enable_reality=0 enable_ss=0
  echo "入口类型："
  echo "1) DMIT optimized entry"
  echo "2) Generic entry（HK/JP/SG/EU/其他线路机）"
  read -r -p "请选择 [1-2]: " entry_type
  case "$entry_type" in 1) entry_type="dmit";; 2) entry_type="generic";; *) die "无效选择";; esac
  node=$(ask "节点前缀/机器名" "${entry_type^^}")
  host=$(ask "节点链接使用的 IPv4/域名" "")
  [ -n "$host" ] || die "host 不能为空。"
  echo "协议：1) Reality  2) SS2022  3) Reality + SS2022"
  read -r -p "请选择 [1-3]: " protocol
  case "$protocol" in
    1) enable_reality=1;;
    2) enable_ss=1;;
    3) enable_reality=1; enable_ss=1;;
    *) die "无效协议选择";;
  esac
  ssh_port=$(ask "SSH 端口" "22")
  reality_port=$(ask "Reality 端口" "443")
  ss_port=$(ask "SS2022 端口" "8443")
  user=$(safe_name "$(ask "初始朋友/默认用户名称" "default")")
  base_config
  save_env_kv SB_ROLE "entry"
  save_env_kv SB_ENTRY_TYPE "$entry_type"
  save_env_kv SB_NODE_NAME "$node"
  save_env_kv SB_NODE_HOST "$host"
  save_env_kv SB_REALITY_PORT "$reality_port"
  save_env_kv SB_SS_PORT "$ss_port"
  if [ "$enable_reality" = "1" ]; then
    sni=$(ask "Reality SNI/伪装站点（每台机器一个）" "www.microsoft.com")
    local kp priv pub sid uuid
    kp=$(reality_keypair); priv=$(awk '{print $1}' <<<"$kp"); pub=$(awk '{print $2}' <<<"$kp")
    sid=$(rand_hex 8); uuid=$(new_uuid)
    add_reality_inbound_initial "$host" "$reality_port" "$sni" "$user" "$uuid" "$priv" "$pub" "$sid"
    save_env_kv SB_REALITY_SNI "$sni"
    save_env_kv SB_REALITY_SHORT_ID "$sid"
  fi
  if [ "$enable_ss" = "1" ]; then
    local sp up
    sp=$(rand_b64 16); up=$(rand_b64 16)
    add_ss_inbound_initial "$ss_port" "$user" "$sp" "$up"
  fi
  if confirm "是否启用 nftables 防火墙？会只放行 SSH/启用协议端口" "y"; then
    setup_firewall "$ssh_port" "$reality_port" "$ss_port" "$enable_reality" "$enable_ss"
  fi
  install_self
  check_or_fallback_dns
  restart_singbox
  if [ "$entry_type" = "dmit" ]; then
    yellow "DMIT 网络 profile 可稍后执行：sb net-install dmit-balanced"
  else
    net_install basic
  fi
  show_links
  green "Entry 安装完成。"
}

install_landing(){
  need_root; check_debian; install_deps; install_singbox; install_systemd_service; setup_journald
  local landing_type node host ssh_port ss_port public_host public_port user sp up
  echo "落地类型："
  echo "1) Generic landing（netcup/普通 VPS/德国落地）"
  echo "2) Home/NAT landing（家宽/NAT/端口映射）"
  read -r -p "请选择 [1-2]: " landing_type
  case "$landing_type" in 1) landing_type="generic";; 2) landing_type="home-nat";; *) die "无效选择";; esac
  node=$(ask "落地节点名" "DE-Landing")
  host=$(ask "本机监听地址" "::")
  ss_port=$(ask "SS2022 本机监听端口" "8443")
  ssh_port=$(ask "SSH 端口" "22")
  if [ "$landing_type" = "home-nat" ]; then
    public_host=$(ask "公网 IPv4/域名（端口映射后的地址）" "")
    public_port=$(ask "公网映射端口" "$ss_port")
  else
    public_host=$(ask "对外链接使用的 IPv4/域名" "")
    public_port="$ss_port"
  fi
  [ -n "$public_host" ] || die "对外 host 不能为空。"
  user=$(safe_name "$(ask "落地用户名称" "landing")")
  sp=$(rand_b64 16); up=$(rand_b64 16)
  base_config
  save_env_kv SB_ROLE "landing"
  save_env_kv SB_LANDING_TYPE "$landing_type"
  save_env_kv SB_NODE_NAME "$node"
  save_env_kv SB_NODE_HOST "$public_host"
  save_env_kv SB_SS_PORT "$public_port"
  # 覆盖 listen 地址：落地机可监听 :: 或 0.0.0.0；NAT 机器按用户输入。
  add_ss_inbound_initial "$ss_port" "$user" "$sp" "$up"
  jq --arg listen "$host" '(.inbounds[]|select(.tag=="ss2022-in").listen)=$listen' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  if confirm "是否启用 nftables 防火墙？" "y"; then
    setup_firewall "$ssh_port" 443 "$ss_port" 0 1
  fi
  install_self
  check_or_fallback_dns
  restart_singbox
  net_install basic
  show_links
  green "Landing 安装完成。把上面的 ss:// 导入 Entry：sb add-landing 名称 'ss://...'"
}

install_menu(){
  need_root
  blue "smart-singbox-installer-final $VERSION"
  echo "1) 安装 Entry 入口机"
  echo "2) 安装 Landing 落地机"
  echo "3) 只安装/更新管理命令 sb"
  read -r -p "请选择 [1-3]: " c
  case "$c" in
    1) install_entry;;
    2) install_landing;;
    3) install_self;;
    *) die "无效选择";;
  esac
}

# ===== 诊断 =====
doctor(){
  echo "===== smart-singbox ====="
  echo "version: $VERSION"
  [ -f "$ENV_FILE" ] && cat "$ENV_FILE" || true
  echo
  echo "===== system ====="
  cat /etc/os-release 2>/dev/null | grep -E 'PRETTY_NAME|VERSION_ID' || true
  uname -a
  echo
  echo "===== sing-box ====="
  command -v sing-box >/dev/null 2>&1 && sing-box version | head -n3 || true
  [ -f "$CONFIG_FILE" ] && sing-box check -c "$CONFIG_FILE" || true
  systemctl --no-pager --full status sing-box 2>/dev/null | sed -n '1,18p' || true
  echo
  echo "===== ports ====="
  ss -tulpn | grep -E '(:443|:8443|sing-box|sshd)' || true
  echo
  echo "===== firewall ====="
  nft list ruleset 2>/dev/null | sed -n '1,120p' || true
  echo
  echo "===== recent logs ====="
  journalctl -u sing-box -n 30 --no-pager 2>/dev/null || true
  echo
  net_status
}

usage(){
  cat <<'EOF'
smart-singbox-installer-final

安装：
  bash install.sh                 # 交互安装
  bash install.sh install-entry    # 安装 Entry 入口机
  bash install.sh install-landing  # 安装 Landing 落地机

管理：
  sb links
  sb add-reality friend1
  sb del-reality friend1
  sb add-ss-user friend1
  sb del-ss-user friend1
  sb add-landing netcup-de 'ss://...'
  sb del-landing netcup-de
  sb net-install basic|dmit-safe|dmit-balanced|dmit-performance|custom 1200mbit|remove
  sb net-status
  sb net-watch 60
  sb doctor
  sb backup
  sb restore-latest

兼容旧命令：
  sb add-friend friend1
  sb del-user friend1
  sb add-ss 'ss://...'
EOF
}

main(){
  local cmd="${1:-menu}"; shift || true
  case "$cmd" in
    menu|install) install_menu;;
    install-entry) install_entry;;
    install-landing) install_landing;;
    links) show_links;;
    add-reality) add_reality_user "$@";;
    del-reality) del_reality_user "$@";;
    add-ss-user) add_ss_user "$@";;
    del-ss-user) del_ss_user "$@";;
    add-landing) add_landing "$@";;
    del-landing) del_landing "$@";;
    add-friend) add_friend "$@";;
    del-user) del_user "$@";;
    add-ss) add_ss_compat "$@";;
    net-install) net_install "$@";;
    net-status|stable-status) net_status;;
    net-watch) net_watch "$@";;
    doctor) doctor;;
    backup) backup_config; green "已备份配置。";;
    restore-latest) restore_latest;;
    test|check) check_config;;
    help|-h|--help) usage;;
    *) usage; exit 1;;
  esac
}

main "$@"
