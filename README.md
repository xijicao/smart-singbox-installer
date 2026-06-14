# Smart sing-box Installer

这是给 DMIT / HK / 家宽 LXC 使用的简化版 sing-box 安装器。

目标很简单：

- DMIT / HK 做 Reality 入口机。
- 家宽 / LXC 可以做 SS2022 落地，也可以做 Reality 直连。
- DMIT / HK 可以导入家宽生成的 `ss://`，自动生成一个新的 Reality 中转节点。
- 机器重启后 sing-box 自动拉起。
- DMIT / HK 防火墙只放行 `443` 和你自己设置的 SSH 端口。

## 先改 DMIT/HK 的 SSH 端口

DMIT 和 HK 入口机会启用 nftables 防火墙，只放行：

```text
TCP 443      sing-box Reality
TCP 你的 SSH 高位端口
```

所以在运行安装脚本前，先把 SSH 端口改成一个你自己选的高位端口，例如 `51398`、`38471`、`45678`。

不要把你的真实 SSH 端口写到公开仓库里。

编辑 SSH 配置：

```sh
nano /etc/ssh/sshd_config
```

找到：

```text
#Port 22
```

改成你自己选的端口，例如：

```text
Port 51398
```

保存并退出 nano：

```text
Ctrl + O
Enter
Ctrl + X
```

重启 SSH：

```sh
systemctl restart ssh
```

如果服务名是 `sshd`，则执行：

```sh
systemctl restart sshd
```

不要关闭当前 SSH 窗口。新开一个窗口测试：

```sh
ssh -p 51398 root@你的服务器IP
```

把 `51398` 换成你实际设置的端口。确认新端口能登录后，再运行安装脚本。

安装 DMIT/HK 时，脚本会询问：

```text
SSH port to allow in firewall
```

这里必须填写你实际设置的 SSH 端口。

## 一键安装

如果新机器提示 `curl: command not found`，先安装 curl。

Debian / Ubuntu：

```sh
apt-get update && apt-get install -y curl ca-certificates
```

Alpine：

```sh
apk update
apk add --no-cache curl ca-certificates iproute2 netcat-openbsd
```

然后执行：

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

本地测试可以直接：

```sh
sh install.sh
```

## 安装菜单

```text
1. DMIT Debian entry
2. HK Debian entry
3. Home landing/direct
4. Add ss:// to this entry
5. Purge current install without backup
0. Exit
```

说明：

- `1`：DMIT 主力入口机，Debian/Ubuntu。
- `2`：HK 入口机，Debian/Ubuntu。
- `3`：家宽 / LXC，可以安装 SS2022、Reality，或两者同时安装。
- `4`：在已安装的 DMIT/HK 上导入家宽 `ss://`。
- `5`：无备份清理当前安装，适合测试失败后重新安装。

## 家宽 / LXC 模式

选择 `3. Home landing/direct` 后，会出现：

```text
1. SS2022 landing only
2. Reality direct only
3. SS2022 landing + Reality direct
```

怎么选：

- 家宽直连一般，只想给 DMIT/HK 当落地：选 `1`
- 家宽直连很好，想客户端直接连家宽：选 `2`
- 既想给 DMIT/HK 当落地，又想保留直连 Reality：选 `3`

### SS2022 端口

如果启用 SS2022，会问：

```text
SS internal listen port
SS public mapped port
```

普通公网 VPS 可以两个都填一样。

LXC / NAT 面板机器要分清：

```text
公网 TCP 24496 -> LXC TCP 443
```

则填写：

```text
SS internal listen port: 443
SS public mapped port: 24496
```

生成的 `ss_link` 会使用公网端口 `24496`。

### Reality 端口

如果启用 Reality，会问：

```text
Reality internal listen port
Reality public mapped port
```

推荐：

- Reality only：优先用 `443`
- SS2022 + Reality：建议 SS2022 用 `443`，Reality 用 `8443`
- LXC / NAT：内部端口填容器里监听的端口，公网端口填面板映射端口

例如：

```text
公网 TCP 24497 -> LXC TCP 8443
```

则填写：

```text
Reality internal listen port: 8443
Reality public mapped port: 24497
```

Reality SNI 候选：

```text
JP / 日本: www.sony.jp
HK / 香港: www.hkex.com.hk
TW / 台湾: www.cht.com.tw
```

这个 SNI 是伪装握手域名，不是你的服务器域名。

家宽 Reality 使用最小兼容模板，不启用：

```text
tcp_fast_open
max_time_difference
```

这是为了兼容 LXC / NAT / 家宽环境。

## DMIT/HK 添加家宽 SS 落地

在家宽机器上查看：

```sh
sb info
```

复制里面的 `ss_link`。

然后在 DMIT 或 HK 上执行：

```sh
sb add-ss 'ss://...'
```

脚本会自动：

- 新增一个 `relay-*` Reality 用户
- 新增一个 Shadowsocks outbound
- 新增分流规则
- 检查配置
- 重启 sing-box
- 输出新的 `vless://` Reality 中转链接

## DMIT/HK 管理命令

```sh
sb
sb links
sb test
sb backup
sb restore-latest
sb list-relays
sb add-ss 'ss://...'
sb del-relay relay-xxx
sb add-friend fr1
sb del-user fr1
sb restart
sb stable-install
sb stable-remove
sb stable-status
sb uninstall
sb purge
```

说明：

- `add-friend`：添加直连 Reality 用户，默认走 direct。
- `add-ss`：添加家宽 SS2022 落地中转。
- `del-relay`：删除某个 `relay-*` 落地节点。
- `links`：显示所有 Reality 链接。
- `test`：检查版本、配置、服务状态、监听端口。
- `stable-install`：安装 DMIT EB CORONA 稳定网络优化 profile。
- `stable-remove`：卸载稳定网络优化 profile。
- `stable-status`：查看稳定网络优化 profile 状态。
- `backup`：备份当前配置到 `/etc/sing-box/backups`。
- `restore-latest`：恢复最新备份。
- `uninstall`：带备份卸载。
- `purge`：无备份强制清理。

## 家宽管理命令

```sh
sb
sb info
sb test
sb status
sb restart
sb reset-ss
sb uninstall
sb purge
```

说明：

- `info`：查看 SS / Reality 链接。
- `test`：检查版本、配置、服务状态、监听端口。
- `reset-ss`：重新生成 SS2022 密码并刷新链接。Reality only 模式不能用。
- `uninstall`：带备份卸载。
- `purge`：无备份强制清理。

如果 `sb` 已经坏了，可以重新运行安装脚本，选择：

```text
5. Purge current install without backup
```

## systemd 服务配置

Debian / Ubuntu 会写入 `/etc/systemd/system/sing-box.service`：

```ini
[Unit]
Description=sing-box service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/sing-box
ExecStartPre=/usr/local/bin/sing-box check -c /etc/sing-box/config.json
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
```

说明：

- `ExecStartPre`：启动前检查配置，避免带病启动。
- `Restart=on-failure`：异常退出自动拉起，手动 stop 不会反复复活。
- `RestartSec=3`：异常退出后 3 秒重启。
- `LimitNOFILE=1048576`：提高连接上限，适合 DMIT 主力入口。
- 不设置 `OOMScoreAdjust=-1000`，对 1G 内存机器更稳妥。

Alpine 使用 OpenRC，并开启 respawn 自动拉起。

## 日常维护和检查

所有机器都可以先用：

```sh
sb test
```

它会检查：

```text
sing-box version
sing-box check -c /etc/sing-box/config.json
服务状态
监听端口
```

重启：

```sh
sb restart
```

手动检查配置：

```sh
sing-box check -c /etc/sing-box/config.json
```

Debian / Ubuntu 查看日志：

```sh
journalctl -u sing-box -n 80 --no-pager
```

Alpine 查看日志：

```sh
tail -n 80 /var/log/messages
```

查看监听端口：

```sh
ss -lntp | grep sing-box
```

如果没有 `ss`：

```sh
netstat -lntp | grep sing-box
```

从 DMIT/HK 测试家宽公网端口：

```sh
nc -vz 家宽公网IP或域名 端口
```

## 防火墙提醒

DMIT/HK 会写入 nftables，只允许：

```text
入站 TCP 443
入站 TCP 你填写的 SSH 端口
已建立连接
loopback
ICMP / IPv6 ICMP
```

启用前会要求输入：

```text
ENTRYFW
```

如果你确定 SSH 端口已经改好，也可以用：

```sh
FORCE_ENTRY_FIREWALL=1 sh install.sh
```

## 生成文件

入口机：

```text
/etc/sing-box/config.json
/etc/sing-box/entry.env
/root/singbox-entry-info.txt
/usr/local/bin/sb
```

家宽机：

```text
/etc/sing-box/config.json
/etc/sing-box/home.env
/root/singbox-home-info.txt
/usr/local/bin/sb
```

## 安全注意

不要上传这些文件到 GitHub：

```text
config.json
entry.env
home.env
singbox-*.txt
*.tar.gz
*.bak
*.log
```

它们可能包含 UUID、Reality 私钥、SS 密码、节点链接。

## DMIT EB CORONA 长期稳定网络优化

这一节用于 DMIT EB CORONA 这类晚高峰容易出现 YouTube QUIC 中断、Telegram 下载瞬时卡顿、TCP 快速重传偏高的机器。

目标不是跑满 2G 口，而是做成长期不用维护的稳定版本：

- 服务端使用 `BBR + fq`。
- 开启 `tcp_mtu_probing=1`，缓解路径 MTU/PMTUD 黑洞问题。
- 设置 `tcp_limit_output_bytes=524288`，减少 TCP 突发和本机队列堆积。
- 使用 `HTB + fq` 将服务端出口稳定限制在 `800mbit`。
- 浏览器端建议禁用 QUIC，YouTube 走 TCP 后稳定性通常更好。

### 推荐固定参数

写入 `/etc/sysctl.d/99-dmit-stable.conf`：

```conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_limit_output_bytes=524288
```

应用：

```sh
sysctl --system
```

### 推荐限速方式

不要只用 `tbf` 替换根队列。推荐使用 `HTB` 控制总出口，再在下面挂 `fq` 保留 BBR pacing：

```sh
tc qdisc replace dev eth0 root handle 1: htb default 10
tc class replace dev eth0 parent 1: classid 1:10 htb rate 800mbit ceil 800mbit
tc qdisc replace dev eth0 parent 1:10 handle 10: fq
```

如果网卡不是 `eth0`，请先查看默认出口网卡：

```sh
ip route get 1.1.1.1
```

然后把命令里的 `eth0` 换成实际网卡名，例如 `ens3`。

### 建议脚本菜单

脚本已集成稳定网络优化。主安装菜单提供：

```text
6. Install stable network profile only
7. Remove stable network profile only
8. Show stable network profile status
```

已安装 entry 后，也可以在 `sb` 管理菜单中使用：

```text
13. Install stable network profile
14. Remove stable network profile
15. Show stable network profile status
```

也可以直接执行命令：

```sh
sb stable-install
sb stable-remove
sb stable-status
```

注意：稳定网络优化是可选 profile，不会在安装 DMIT/HK/Home 时自动启用，也不会修改 sing-box 配置或 nftables 防火墙。只有手动选择菜单项或执行 `sb stable-install` 时才会生效。Home 模式的 `sb` 管理器不内置这些菜单项，如需在 Home 机器上使用，请从主安装菜单选择 `6/7/8`。

安装后应创建：

```text
/etc/sysctl.d/99-dmit-stable.conf
/etc/systemd/system/tc-htb-fq.service
```

卸载时应删除上面两个文件，并执行：

```sh
systemctl disable --now tc-htb-fq.service
systemctl daemon-reload
sysctl --system
```

### 状态检查

查看 sysctl：

```sh
sysctl net.core.default_qdisc
sysctl net.ipv4.tcp_congestion_control
sysctl net.ipv4.tcp_mtu_probing
sysctl net.ipv4.tcp_limit_output_bytes
```

查看限速和队列：

```sh
tc -s qdisc show dev eth0
tc -s class show dev eth0
```

正常应能看到：

```text
qdisc htb ... root
qdisc fq ... parent 1:10
class htb 1:10 ... rate 800Mbit ceil 800Mbit
```

### 浏览器 QUIC

如果 YouTube 仍然提示网络中断，优先禁用浏览器 QUIC：

```text
chrome://flags/#enable-quic
```

将 `Experimental QUIC protocol` 设置为 `Disabled`，然后重启浏览器。

实测中，DMIT EB CORONA 在禁用 QUIC 后，YouTube 通常会从 UDP/QUIC 回落到 TCP，稳定性明显提升。

### 影响和取舍

这套优化的主要取舍：

- 机器出口峰值会被限制在约 `800mbit`，无法跑满 2G 口。
- 限速作用于整台机器的出站流量，包括 sing-box、scp、apt 下载等。
- `fq` 是按 flow 公平，不是按用户公平；多线程下载会比单线程占更多份额。
- 对代理下载场景有效，因为大流量方向通常是 `DMIT -> 客户端`，也就是服务端出站。

如果主要用途是 sing-box 代理、YouTube、Telegram 和日常下载，推荐固定 `800mbit`。如果追求更高峰值，可以临时测试 `900mbit`，但长期稳定档建议保持 `800mbit`。
