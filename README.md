# Smart sing-box 简化版

这是给 DMIT / HK / 家宽落地使用的简化版安装器。

## 先改 DMIT/HK 的 SSH 端口

DMIT 和 HK 入口机会启用防火墙，只放行：

```text
TCP 443    sing-box Reality
TCP 51398  SSH
```

所以在 DMIT/HK 上运行安装脚本前，先把 Debian/Ubuntu 的 SSH 端口改成 `51398`。

编辑 SSH 配置：

```sh
nano /etc/ssh/sshd_config
```

找到这一行：

```text
#Port 22
```

改成：

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

有些系统服务名是 `sshd`，如果上面失败，就执行：

```sh
systemctl restart sshd
```

然后先不要关闭当前 SSH 窗口，新开一个窗口测试：

```sh
ssh -p 51398 root@你的服务器IP
```

确认 `51398` 可以登录后，再运行本安装脚本。这个步骤很重要，否则防火墙启用后可能进不去机器。

设计目标：

- DMIT 和 HK 只做入口，监听 `443`，Reality 入站。
- 家宽只做 SS2022 落地，生成 `ss://` 链接。
- 在 DMIT/HK 上粘贴家宽的 `ss://`，自动生成一个新的 Reality 中转链接。
- 后续可以添加朋友直连用户，也可以删除朋友或某个家宽落地。
- sing-box 使用 systemd/OpenRC 托管，机器重启后自动拉起。
- DMIT/HK 的 nftables 防火墙只放行入站 TCP `443` 和 `51398`。
- 家宽 SS2022 不要求使用 `443`，公网映射端口可以是面板给你的任意 TCP 端口。
- DMIT/HK 的 direct 出站已设置为 `prefer_ipv4`。DMIT 双栈时会优先 IPv4 出站；HK 如果本来只有 IPv4，不需要额外处理。

## 一键安装

如果新机器提示 `curl: command not found`，先安装 curl：

Debian/Ubuntu：

```sh
apt-get update && apt-get install -y curl ca-certificates
```

Alpine：

```sh
apk update
apk add --no-cache curl ca-certificates iproute2 netcat-openbsd
```

上传到 GitHub 后使用：

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

如果你先在本地测试，也可以直接：

```sh
sh install.sh
```

## 菜单

```text
1. DMIT Debian entry / DMIT 主力入口
2. HK Debian entry / HK 国际互连入口
3. Home landing / 家宽落地或直连
4. Add ss:// to this entry / 给当前入口添加落地
0. Exit
```

DMIT/HK 只支持 Debian/Ubuntu。家宽支持 Debian/Ubuntu/Alpine。

## 家宽机器

在家宽机器上选择 `3`，脚本会生成：

```text
/root/singbox-home-info.txt
```

里面有：

```text
ss_link:
ss://...

ss_link_editable:
ss://method:password@server:port#name
```

安装时会先选择模式：

```text
1. SS2022 landing only
2. Reality direct only
3. SS2022 landing + Reality direct
```

怎么选：

- 家宽直连质量一般，只想给 DMIT/HK 当落地：选 `1`
- 家宽直连质量很好，想客户端直接连家宽：选 `2`
- 既想给 DMIT/HK 当落地，又想保留直连入口：选 `3`

### SS2022 端口

如果启用 SS2022，会问两个端口：

```text
SS internal listen port
SS public mapped port
```

普通独立公网 VPS 可以两个都填 `443`，或者都填你想用的端口。

NAT/LXC/家宽面板机器要分开填。例如面板映射是：

```text
公网 TCP 24496 -> 容器 TCP 443
```

那么填写：

```text
SS internal listen port: 443
SS public mapped port: 24496
```

生成的 `ss_link` 会自动使用公网端口 `24496`，DMIT/HK 导入时就能连对。

### Reality 端口

如果启用 Reality，会问两个端口：

```text
Reality internal listen port
Reality public mapped port
```

端口建议：

- Reality only：优先用 `443`
- SS2022 + Reality 同时安装：建议 SS2022 用 `443`，Reality 用 `8443`
- NAT/LXC 面板机器：内部端口填容器里监听的端口，公网端口填面板映射给你的端口
- 家宽 Reality 配置使用最小兼容模板，不启用 `tcp_fast_open`，也不限制 `max_time_difference`，尽量贴近已验证可用的一键脚本配置。

举例：

```text
公网 TCP 24497 -> 容器 TCP 8443
```

那么填写：

```text
Reality internal listen port: 8443
Reality public mapped port: 24497
```

Reality 的 SNI 默认是日本方向的 `www.sony.jp`。安装时会问 `Reality SNI`，可以按家宽地区手动填：

```text
JP / 日本：www.sony.jp
HK / 香港：www.hkex.com.hk
TW / 台湾：www.cht.com.tw
```

如果你知道某个地区更合适的握手域名，也可以安装时手动输入。这里填的是伪装握手域名，不是你的服务器域名。

## DMIT/HK 添加家宽落地

在 DMIT 或 HK 上执行：

```sh
sb add-ss 'ss://...'
```

或者直接运行：

```sh
sb
```

选择 `Add SS landing`，粘贴家宽链接。脚本会自动：

- 新增一个 `relay-*` Reality 用户
- 新增一个对应的 Shadowsocks outbound
- 新增一条按用户分流的 route rule
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
sb del-relay relay-jp-home-SS
sb add-friend fr1
sb del-user fr1
sb restart
sb uninstall
sb purge
```

说明：

- `add-friend` 添加的是直连 Reality 用户，默认走 direct。
- `add-ss` 添加的是落地中转用户，名字会以 `relay-` 开头。
- 删除落地请用 `del-relay`，删除朋友用 `del-user`。
- 家宽 SS2022 的端口不需要是 `443`。DMIT/HK 连接家宽属于出站流量，入口机防火墙不会限制这个出站端口。
- `test` 会检查 sing-box 版本、配置、服务状态和监听端口。
- `backup` 会把当前配置备份到 `/etc/sing-box/backups`。
- `restore-latest` 会恢复最新配置备份，恢复前会先备份当前状态。
- `uninstall` 会先打包备份到 `/root/singbox-entry-uninstall-backup-*.tar.gz`，再停止 sing-box 并删除入口配置和 `sb` 管理器。
- `purge` 是无备份强制清理，会停止 sing-box、删除 `/etc/sing-box`、删除 `sb` 和信息文件。DMIT/HK 不会自动关闭 nftables，避免意外暴露 SSH。

如果想交互式删除落地，直接运行：

```sh
sb
```

选择 `Delete relay` 后会列出编号，不需要手打完整 `relay-*` 名字。

## 家宽管理命令

家宽机器安装后也有 `sb`：

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

- `info` 查看当前 SS 链接。
- 如果安装了 Reality，`info` 也会显示 `vless://` 直连链接。
- `test` 检查 sing-box 版本、配置、服务状态和监听端口。
- `reset-ss` 会重新生成 SS2022 密码，更新 `/etc/sing-box/config.json`，重启服务，并刷新 `/root/singbox-home-info.txt`。
- Reality only 模式没有 SS2022，不能使用 `reset-ss`。
- `uninstall` 会先打包备份到 `/root/singbox-home-uninstall-backup-*.tar.gz`，再删除家宽落地安装。
- `purge` 是无备份强制清理，会停止 sing-box，删除 `/etc/sing-box`、`/root/singbox-home-info.txt` 和 `sb`。

如果 `sb` 已经坏了或不存在，也可以重新运行安装脚本，选择：

```text
5. Purge current install without backup
```

这个选项不依赖旧的 `sb`，适合反复测试时清空环境后重装。

## 日常维护和检查

### 通用命令

DMIT、HK、家宽机器都可以先用 `sb test` 做一次总检查。这个命令适合在这些情况使用：

- 刚安装完成，想确认 sing-box 是否正常。
- 重启机器后，想确认服务是否自动拉起。
- 节点突然不能用了，先看是不是服务或端口问题。
- 修改配置、添加落地、重置密码之后，想快速确认有没有写坏配置。

```sh
sb test
```

它会依次检查：

```text
sing-box version                         查看 sing-box 版本
sing-box check -c /etc/sing-box/config.json  检查配置文件有没有语法错误
systemd/OpenRC 服务状态                   查看服务是不是 running
监听端口                                  查看 sing-box 有没有监听对应端口
```

重启 sing-box。适合在修改配置、端口、密码后使用：

```sh
sb restart
```

查看服务状态。适合确认 sing-box 是否正在运行：

```sh
sb status
```

如果某台机器的 `sb status` 不可用，可以直接用系统命令。

Debian/Ubuntu：

```sh
systemctl status sing-box --no-pager
systemctl restart sing-box
journalctl -u sing-box -n 80 --no-pager
```

说明：

- `systemctl status sing-box --no-pager`：查看 sing-box 服务状态。
- `systemctl restart sing-box`：重启 sing-box。
- `journalctl -u sing-box -n 80 --no-pager`：查看最近 80 行日志，排查启动失败、配置错误、端口占用等问题。

Alpine：

```sh
rc-service sing-box status
rc-service sing-box restart
tail -n 80 /var/log/messages
```

说明：

- `rc-service sing-box status`：查看 Alpine/OpenRC 下的服务状态。
- `rc-service sing-box restart`：重启 sing-box。
- `tail -n 80 /var/log/messages`：查看最近系统日志，排查 sing-box 启动问题。

手动检查配置文件。只要你怀疑配置写坏了，先跑这个：

```sh
sing-box check -c /etc/sing-box/config.json
```

如果输出 `configuration file parsed successfully` 或类似成功提示，说明配置语法没问题。

查看监听端口。用来确认 sing-box 是否真的监听了你设置的端口：

```sh
ss -lntp | grep sing-box
```

如果系统没有 `ss`，可以用：

```sh
netstat -lntp | grep sing-box
```

正常情况下：

- DMIT/HK 应该看到 `:443`。
- 家宽 SS2022 应该看到你填写的 `SS internal listen port`。
- 家宽 Reality 应该看到你填写的 `Reality internal listen port`。

### LXC/家宽端口排查

家宽是 LXC 或 NAT 面板时，安装脚本会问：

```text
SS internal listen port
SS public mapped port
Reality internal listen port
Reality public mapped port
```

内部监听端口是容器里 sing-box 真正监听的端口；公网映射端口是面板分配给外面连接的端口。

如果某些端口有问题，优先换“公网映射端口”，比如：

```text
公网 TCP 24496 -> LXC TCP 443
公网 TCP 24497 -> LXC TCP 8443
```

安装时就填：

```text
SS internal listen port: 443
SS public mapped port: 24496

Reality internal listen port: 8443
Reality public mapped port: 24497
```

检查 LXC 内部是否监听成功。这个命令是在家宽 LXC 里面运行的：

```sh
ss -lntp | grep -E ':443|:8443'
```

如果这里没有输出，说明 sing-box 没有监听对应内部端口，先执行：

```sh
sb test
sing-box check -c /etc/sing-box/config.json
```

从 DMIT/HK 测试能否连到家宽公网端口。这个命令是在 DMIT 或 HK 上运行的：

```sh
nc -vz 家宽公网IP或域名 24496
nc -vz 家宽公网IP或域名 24497
```

正常情况会看到类似 `succeeded` 的提示。如果连接失败，优先检查：

- 面板公网端口是否填错。
- 面板映射是否生效。
- 家宽 LXC 内部端口是否监听。
- 家宽运营商或面板是否屏蔽了该端口。
- `ss://` 或 `vless://` 链接里用的是不是公网映射端口，而不是容器内部端口。

如果没有 `nc`，Debian/Ubuntu 可以安装：

```sh
apt-get update && apt-get install -y netcat-openbsd
```

Alpine 可以安装：

```sh
apk add --no-cache iproute2 netcat-openbsd
```

`iproute2` 提供 `ss` 命令，`netcat-openbsd` 提供 `nc` 命令。

## 防火墙提醒

DMIT/HK 会写入 nftables，只允许：

```text
入站 TCP 443
入站 TCP 51398
已建立连接
loopback
ICMP / IPv6 ICMP
```

这意味着普通 SSH `22` 端口会被挡掉。脚本会在启用防火墙前要求输入：

```text
ENTRYFW
```

如果你确定自己已经改好 SSH 端口，或者有控制台、救援模式，也可以用：

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

## 我保留和舍弃的部分

保留：

- DMIT/HK 的 Reality 入口设计
- `ss://` 导入后自动生成 Reality 中转节点
- 朋友用户添加/删除
- 重启自拉起
- 配置检查失败自动回滚
- 443 + 51398 入口防火墙

舍弃：

- 多 profile 复杂分叉
- 过多 README 和架构图
- 家宽 Reality + SS 混合模式
- 不常用的备份恢复菜单
- 复杂的全自动端口猜测
