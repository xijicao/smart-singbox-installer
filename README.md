# Smart sing-box Installer

自用 sing-box 安装脚本，主要用于：

- DMIT / HK 入口机：Reality inbound。
- Home / LXC / 落地机：SS2022 landing、Reality direct，或两者同时启用。
- DMIT / HK 导入落地机生成的 `ss://`，自动生成 Reality 中转节点。

## 先改 SSH 端口

入口机会启用 nftables 防火墙，只放行：

```text
TCP 443              sing-box Reality
TCP 你的 SSH 端口     SSH
```

安装前建议先把 SSH 改成自己的高位端口，例如 `51398`。

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

检查 SSH 配置并重启：

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

确认新端口能登录后，再运行安装脚本。安装入口机时，`SSH port to allow in firewall` 必须填写这个真实 SSH 端口。

## 安装

Debian / Ubuntu 如果没有 curl，先安装：

```sh
apt-get update && apt-get install -y curl ca-certificates
```

下载后执行：

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh -o install.sh
chmod +x install.sh
sh install.sh
```

菜单：

```text
1. DMIT Debian entry
2. HK Debian entry
3. Home landing/direct
4. Add ss:// to this entry
5. Purge current install without backup
6. Purge all, including nftables firewall
7. Install stable network profile only
8. Remove stable network profile only
9. Show stable network profile status
0. Exit
```

## 安装后检查

检查 sing-box 配置：

```sh
sing-box check -c /etc/sing-box/config.json
```

看服务状态：

```sh
systemctl status sing-box --no-pager
journalctl -u sing-box -n 100 --no-pager
```

看监听端口：

```sh
ss -tulpn | grep -E '(:443|:8443|sing-box|sshd)'
```

如果你改了 SSH 端口，把命令里的端口也加进去，例如：

```sh
ss -tulpn | grep -E '(:51398|:443|:8443|sing-box|sshd)'
```

看 nftables 是否开机启动：

```sh
systemctl is-enabled nftables
systemctl status nftables --no-pager
nft list ruleset
```

入口机正常应看到类似：

```text
tcp dport 51398 accept
tcp dport 443 accept
```

Home / landing 模式默认不主动写 nftables；云厂商安全组或面板防火墙仍需手动放行对应端口。

## 管理命令

入口机：

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
sb purge-all
```

Home / landing：

```sh
sb
sb info
sb test
sb status
sb restart
sb reset-ss
sb uninstall
sb purge
sb purge-all
```

## 卸载

保守卸载，带备份，保留 nftables：

```sh
sb uninstall
```

无备份清理，保留 nftables：

```sh
sb purge
```

完全清理，包括 nftables 防火墙规则：

```sh
sb purge-all
```

如果 `sb` 已经损坏，可以重新下载 `install.sh` 后运行：

```sh
sh install.sh
```

然后选择：

```text
5. Purge current install without backup
```

或完全清理：

```text
6. Purge all, including nftables firewall
```

注意：`purge-all` 会执行 `nft flush ruleset` 并删除 `/etc/nftables.conf`，只建议在你确认不会因此断开 SSH 或暴露机器时使用。

## Home / LXC 模式端口

选择 `3. Home landing/direct` 后：

```text
1. SS2022 landing only
2. Reality direct only
3. SS2022 landing + Reality direct
```

SS2022 会询问：

```text
SS internal listen port
SS public mapped port
```

普通公网 VPS 可以两个都填一样。LXC / NAT 场景要区分内部监听端口和公网映射端口。

例如：

```text
公网 TCP 24496 -> LXC TCP 443
```

则填写：

```text
SS internal listen port: 443
SS public mapped port: 24496
```

生成的 `ss://` 会使用公网端口 `24496`。

## sing-box 1.13+ 兼容

新版 sing-box 已经移除旧 inbound 字段，本脚本不再生成：

```json
"sniff": true
"sniff_override_destination": true
```

脚本保留顶层 DNS 策略：

```json
"strategy": "prefer_ipv4"
```

这只影响 sing-box 出站解析目标域名时优先选择 IPv4，不影响客户端用 IPv6 连接你的服务器。如果你用旧配置遇到类似错误：

```text
legacy inbound fields are deprecated ... removed in sing-box 1.13.0
```

说明旧配置里还有这些字段，重新用新版脚本安装或手动删除即可。
