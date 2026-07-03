# Smart sing-box Installer

自用 sing-box 安装脚本。目标是少问问题、固定端口、固定用户、方便排障。

核心规则：

```text
Reality: 443
SS2022: 8443
SSH: 你自己提前改好的高位端口
```

线路机默认生成三个用户：

```text
CAO
WEI
TAO
```

落地机默认只生成一个用户：

```text
landing，或你安装时输入的落地机名称
```

## 先改 SSH 端口

入口/落地都会写 nftables 防火墙。安装前先把 SSH 改成高位端口，例如 `51398`。

```sh
nano /etc/ssh/sshd_config
```

找到：

```text
#Port 22
```

改成：

```text
Port 51398
```

检查配置并重启 SSH：

```sh
sshd -t
systemctl restart ssh
```

如果服务名是 `sshd`：

```sh
systemctl restart sshd
```

不要关闭当前 SSH 窗口。新开一个窗口测试：

```sh
ssh -p 51398 root@你的服务器IP
```

确认新端口能登录后，再运行安装脚本。安装时问 `SSH port to allow in firewall`，就填这个端口。

## 安装

如果机器没有 curl，先安装：

```sh
apt-get update && apt-get install -y curl ca-certificates
```

下载脚本：

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh -o install.sh
chmod +x install.sh
sh install.sh
```

主菜单：

```text
1. Entry line machine
2. Landing machine
3. Add ss:// landing to this entry
4. Purge current install without backup
5. Purge all, including nftables firewall
6. Install/switch network profile only
7. Remove network profile only
8. Show network profile status
0. Exit
```

## 菜单说明

`1. Entry line machine`

安装线路机。脚本会继续问：

```text
1. DMIT
2. Other region/provider
```

线路机行为：

```text
自动获取公网 IPv4，Reality 链接使用这个 IPv4
问你有没有 IPv6，完全按你的回答决定是否安装 SS2022
手动输入 Reality SNI / 伪装站点
有 IPv6：安装 Reality + SS2022
没 IPv6：只安装 Reality
固定生成 CAO / WEI / TAO 三个用户
Reality 固定监听 443
SS2022 固定监听 8443
DMIT 才询问是否安装网络优化档位
```

线路机防火墙：

```text
TCP SSH高位端口
TCP 443
如果安装 SS2022，再放行 TCP 8443 和 UDP 8443
```

`2. Landing machine`

安装落地机。脚本会问安装哪个协议：

```text
1. SS2022 landing only
2. Reality direct only
3. SS2022 landing + Reality direct
```

落地机行为：

```text
只生成一个用户
协议由你选择，和有没有 IPv6 不绑定
问你有没有 IPv6，只影响 SS2022 链接使用 IPv6 还是 IPv4
启用 Reality 时，手动输入 Reality SNI / 伪装站点
Reality 固定 443
SS2022 固定 8443
```

落地机防火墙：

```text
TCP SSH高位端口
启用 Reality 时放行 TCP 443
启用 SS2022 时放行 TCP 8443 和 UDP 8443
```

`3. Add ss:// landing to this entry`

在线路机上导入落地机的 `ss://` 链接。名称从 `ss://` 的备注里取。

执行后会自动：

```text
添加一个 Shadowsocks outbound 指向落地机
添加一个 relay-* Reality 用户
添加分流规则
返回一个新的 Reality 链接
```

这个新 Reality 链路是：

```text
客户端 -> 线路机 Reality -> 落地机 SS2022 -> 目标网站
```

`4. Purge current install without backup`

无备份清理 sing-box，但保留 nftables 防火墙。适合安装失败后重新安装，同时不突然改变 SSH 暴露状态。

`5. Purge all, including nftables firewall`

完全清理，包括：

```text
sing-box 服务
/etc/sing-box
/usr/local/bin/sb
sing-box 二进制
nftables 规则和 /etc/nftables.conf
DMIT 网络优化服务和 sysctl 文件
```

注意：这个会执行 `nft flush ruleset`，只在你确认不会断开 SSH 或暴露机器时使用。

`6. Install/switch network profile only`

只安装或切换网络优化档位，不改 sing-box 配置。

`7. Remove network profile only`

只移除网络优化档位，不动 sing-box。

`8. Show network profile status`

查看当前 sysctl、tc 队列、tc 限速服务状态。

## 安装后检查

检查 sing-box 配置：

```sh
sing-box check -c /etc/sing-box/config.json
```

查看服务状态：

```sh
systemctl status sing-box --no-pager
journalctl -u sing-box -n 100 --no-pager
```

查看监听端口：

```sh
ss -tulpn | grep -E '(:51398|:443|:8443|sing-box|sshd)'
```

把 `51398` 换成你的 SSH 端口。

查看防火墙：

```sh
systemctl is-enabled nftables
systemctl status nftables --no-pager
nft list ruleset
```

查看 sing-box 是否开机自动拉起：

```sh
systemctl is-enabled sing-box
systemctl status sing-box --no-pager
```

脚本写入的 systemd 服务包含：

```ini
Restart=on-failure
RestartSec=3
ExecStartPre=/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

意思是 sing-box 崩溃后 systemd 会自动重启；启动前会先检查配置。

## 线路机命令

```sh
sb
```

打开线路机管理菜单。

```sh
sb links
```

显示所有 Reality 链接；如果安装了 SS2022，也显示 CAO / WEI / TAO 三个 SS2022 链接。

```sh
sb add-ss 'ss://...'
```

导入落地机 SS2022 链接，生成新的链式代理 Reality 链接。名称从 `ss://` 的备注里取。

```sh
sb list-relays
```

列出已经导入的落地中转节点。

```sh
sb del-relay relay-xxx
```

删除某个落地中转节点。

```sh
sb test
```

检查 sing-box 版本、配置、服务状态和监听端口。

```sh
sb restart
```

重启 sing-box。

```sh
sb backup
```

备份当前配置到 `/etc/sing-box/backups`。

```sh
sb restore-latest
```

恢复最近一次配置备份。

```sh
sb stable-install dmit-safe
sb stable-install dmit-balanced
sb stable-install dmit-performance
```

切换 DMIT 网络优化档位。

```sh
sb stable-status
```

查看网络优化状态。

```sh
sb stable-remove
```

移除网络优化。

```sh
sb uninstall
```

带备份卸载 sing-box，保留 nftables。

```sh
sb purge
```

无备份清理 sing-box，保留 nftables。

```sh
sb purge-all
```

无备份完全清理 sing-box 和 nftables。

## 落地机命令

```sh
sb
```

打开落地机管理菜单。

```sh
sb info
```

显示落地机链接。SS2022 链接可以复制到线路机执行 `sb add-ss 'ss://...'`。

```sh
sb test
```

检查 sing-box 版本、配置、服务状态和监听端口。

```sh
sb status
```

查看 sing-box 服务状态。

```sh
sb restart
```

重启 sing-box。

```sh
sb reset-ss
```

重置落地机 SS2022 密码，并刷新 `sb info` 输出。Reality only 模式不能使用。

```sh
sb uninstall
sb purge
sb purge-all
```

卸载或清理，含义同线路机。

## DMIT 网络优化档位

网络优化只改系统网络参数，不改 sing-box 协议。

```sh
sb stable-install basic
sb stable-install dmit-safe
sb stable-install dmit-balanced
sb stable-install dmit-performance
sb stable-install custom 750mbit
```

`basic`：

```text
BBR + fq + MTU probing
不安装 HTB 限速
适合非 DMIT 或只想基础优化
```

`dmit-safe`：

```text
HTB 800mbit + fq
tcp_limit_output_bytes=524288
优先稳定，建议先跑这个观察
```

`dmit-balanced`：

```text
HTB 900mbit + fq
tcp_limit_output_bytes=1048576
启用 32MB TCP buffer 上限
日常推荐
```

`dmit-performance`：

```text
HTB 1000mbit + fq
tcp_limit_output_bytes=1048576
启用 32MB TCP buffer 上限
追求峰值，线路不稳时可能重传升高
```

查看是否生效：

```sh
sysctl net.core.default_qdisc
sysctl net.ipv4.tcp_congestion_control
sysctl net.ipv4.tcp_mtu_probing
sysctl net.ipv4.tcp_limit_output_bytes
sysctl net.core.rmem_max
sysctl net.core.wmem_max
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem
```

查看默认网卡：

```sh
ip route get 1.1.1.1
```

查看 tc 限速：

```sh
tc -s qdisc show dev eth0
tc -s class show dev eth0
systemctl status tc-htb-fq.service --no-pager
```

把 `eth0` 换成你的实际网卡。

观察 60 秒 TCP 重传：

```sh
nstat -az > /tmp/nstat.before
sleep 60
nstat -az > /tmp/nstat.after
python3 - <<'PY'
keys=['TcpRetransSegs','TcpOutSegs','TcpExtTCPTimeouts','TcpExtTCPLostRetransmit']
def load(p):
    d={}
    for line in open(p, errors='ignore'):
        parts=line.split()
        if len(parts)>=2 and parts[0] in keys:
            d[parts[0]]=int(parts[1])
    return d
b=load('/tmp/nstat.before')
a=load('/tmp/nstat.after')
for k in keys:
    print(f'{k}: {a.get(k,0)-b.get(k,0)}')
out=a.get('TcpOutSegs',0)-b.get('TcpOutSegs',0)
ret=a.get('TcpRetransSegs',0)-b.get('TcpRetransSegs',0)
if out:
    print(f'Retrans ratio: {ret/out:.6%}')
PY
```

大致判断：

```text
0.01% 以下       很好
0.01% - 0.1%    正常
0.1% - 1%       可能有压力，建议降档观察
1% 以上          明显不稳
```

## sing-box 1.13+ 兼容

脚本不生成旧 inbound 字段：

```json
"sniff": true
"sniff_override_destination": true
```

保留顶层 DNS IPv4 优先：

```json
"strategy": "prefer_ipv4"
```

这只影响 sing-box 出站解析目标域名优先 IPv4，不影响客户端用 IPv6 连接你的服务器。
