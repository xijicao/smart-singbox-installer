# 快速命令

## 日常操作索引

```text
新装机器：看第 1 节
查看安装输出：看第 2 节
装完自检：看第 3 节
home SS2022 导入 DMIT/HK：看第 4 节
NAT/LXC 改公网端口：看第 5 节
DMIT/HK 删除 relay、备份、恢复、更新 core：看第 6 节
DMIT/HK 整机卸载/恢复：看第 7 节
Home 落地卸载/恢复：看第 8 节
```

最常用命令：

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
sing-box version
sing-box check -c /etc/sing-box/config.json
sb
sing-box-add-ss2022-relay
```

## 1. 唯一需要记的安装命令

所有机器都用这一条：

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

如果极简系统没有 `curl`，用这条备用：

```sh
wget -qO- https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

运行后看菜单选择：

```text
1) DMIT entry machine
2) HK entry machine
3) Home/landing machine - SS2022 only
4) Home/landing machine - Reality + SS2022
```

怎么选：

1. DMIT 2G 主力入口机：选 `1`
2. HK 10M 小水管入口/中转机：选 `2`
3. 家宽、NAT、LXC、IPLC 只做 SS2022 落地：选 `3`
4. 家宽、NAT、LXC、IPLC 同时直连 Reality + SS2022 落地：选 `4`

重要：DMIT/HK 入口机默认会启用 nftables 防火墙。安装前先把 SSH 改到 `51398`，并确认你能用 `51398` 登录。

入口机默认放行 IPv4/IPv6：

```text
TCP 51398  # SSH
TCP 443    # Reality
ICMP / IPv6 ICMP
```

其它入站默认 drop。Home 家宽/NAT/LXC 机器不会默认启用 nftables。

选 `3` 或 `4` 时，脚本会自动识别 Debian/Ubuntu/Alpine，自动选对应 sing-box 包。Alpine 会优先用 musl 包，Debian/Ubuntu 会优先用 glibc 包，对应包不行再退到通用包。

选 `4` 时还会让你选择 Reality 握手/SNI 地区：

```text
1) JP - www.sony.jp
2) TW - www.cht.com.tw
3) HK - www.hkex.com.hk
4) US - reed.edu
5) EU - www.siemens.com
6) Custom domain
```

日本机器选 `1`，台湾机器选 `2`。如果你自己测到了更好的目标域名，选 `6` 手动输入纯域名，不要带 `https://`。

## 2. 查看安装后输出

DMIT：

```sh
cat /root/dmit-singbox-info.txt
```

HK：

```sh
cat /root/hk-singbox-info.txt
```

home 落地机器：

```sh
cat /root/home-singbox-info.txt
```

这些 info 文件默认 `600` 权限，只有 root 能读。

## 3. 装完自检命令

Alpine 机器运行：

```sh
sing-box version
sing-box check -c /etc/sing-box/config.json
rc-service sing-box status
cat /root/home-singbox-info.txt
```

Debian/Ubuntu 机器运行：

```sh
sing-box version
sing-box check -c /etc/sing-box/config.json
systemctl status sing-box --no-pager
cat /root/dmit-singbox-info.txt 2>/dev/null || cat /root/hk-singbox-info.txt 2>/dev/null || cat /root/home-singbox-info.txt
```

DMIT/HK 入口机再看防火墙：

```sh
nft list ruleset | grep -E '51398|443'
```

含义：

```text
sing-box version  查看 sing-box 版本
sing-box check    检查配置文件是否正确
status            检查服务是否正在运行
cat info          查看节点链接、端口、密码、SNI
nft list ruleset  查看入口机防火墙是否放行 SSH 51398 和 Reality 443
```

## 4. 把家宽 SS2022 导入到 DMIT/HK

先在 home 落地机器上复制：

```text
ss_link:
ss://...
```

如果是 NAT/LXC 端口映射，优先复制：

```text
ss_link_editable:
ss://method:password@server:port#name
```

然后把里面的端口手动改成面板公网端口。

再到 DMIT 或 HK 上运行：

```sh
sing-box-add-ss2022-relay
```

粘贴 `ss://` 链接，脚本会自动返回一个新的 `vless://` Reality 中转链接。

## 5. NAT/LXC 端口映射怎么改

比如面板是：

```text
公网 TCP 24496 -> 容器 TCP 443
```

home 机器里 sing-box 实际监听的是 `443`，但喂给 DMIT/HK 的 `ss://` 要写公网端口 `24496`。

安装后如果看到：

```text
ss_link_editable:
ss://method:password@server:443#jp-home-SS2022
```

你直接改成：

```text
ss://method:password@server:24496#jp-home-SS2022
```

再粘给 `sing-box-add-ss2022-relay` 即可。机器里的监听端口不用跟着改。

如果选 `4` 同时装 Reality + SS2022，两个协议不要共用同一个端口。推荐类似这样：

```text
公网 TCP 24496 -> 容器 TCP 443   # SS2022
公网 TCP 24497 -> 容器 TCP 8443  # Reality
```

## 6. DMIT/HK 统一管理菜单

在 DMIT 或 HK 上运行：

```sh
sb
```

或者：

```sh
-sb
```

常用功能：

```text
1) 重新生成你和朋友的基础 Reality 链接
2) 列出所有 relay 家宽落地
3) 删除某个 relay 家宽落地
4) 查看所有当前 Reality 链接
5) 备份当前 config/meta/core
6) 恢复最新备份
7) 只更新 sing-box core
```

也可以直接跑：

```sh
sb backup
sb restore-latest
sb update-core
```

注意：`sb` 的第 `3` 项只是删除某个 `relay-*` 家宽落地中转节点，不会卸载 DMIT/HK 入口机。

## 7. DMIT/HK 入口机整机卸载

只在 DMIT/HK 入口机上用：

```sh
sing-box-entry-uninstall
```

执行前会要求输入：

```text
UNINSTALL_ENTRY
```

它会先备份到：

```text
/root/sing-box-entry-uninstall-backup-*.tar.gz
```

然后删除这套入口机 sing-box 服务、配置、info 文件、`sing-box-add-ss2022-relay`、`sb`、`-sb` 和 `/usr/local/bin/sing-box`。

它不会卸载 apt 依赖包，也不是完整恢复机器初始状态。

恢复最近一次入口机卸载备份：

```sh
sing-box-entry-restore
```

指定某个备份恢复：

```sh
sing-box-entry-restore /root/sing-box-entry-uninstall-backup-YYYYMMDDHHMMSS.tar.gz
```

恢复前会先生成一份当前状态备份：

```text
/root/sing-box-entry-pre-restore-backup-*.tar.gz
```

## 8. Home 落地卸载

只在 home 落地机器上用：

```sh
sing-box-uninstall
```

执行前会要求输入 `UNINSTALL`，并先打包备份。

它会删除 home 落地机器上的 sing-box 服务、配置、healthcheck、info 文件和 `/usr/local/bin/sing-box`。它不会卸载系统依赖包，也不是完整恢复机器初始状态。

恢复最近一次 home 卸载备份：

```sh
sing-box-restore
```

指定某个备份恢复：

```sh
sing-box-restore /root/sing-box-uninstall-backup-YYYYMMDDHHMMSS.tar.gz
```

恢复前会先生成一份当前状态备份：

```text
/root/sing-box-pre-restore-backup-*.tar.gz
```
