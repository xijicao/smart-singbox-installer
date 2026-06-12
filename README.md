# Smart sing-box 简化版

这是给 DMIT / HK / 家宽落地使用的简化版安装器。

设计目标：

- DMIT 和 HK 只做入口，监听 `443`，Reality 入站。
- 家宽只做 SS2022 落地，生成 `ss://` 链接。
- 在 DMIT/HK 上粘贴家宽的 `ss://`，自动生成一个新的 Reality 中转链接。
- 后续可以添加朋友直连用户，也可以删除朋友或某个家宽落地。
- sing-box 使用 systemd/OpenRC 托管，机器重启后自动拉起。
- DMIT/HK 的 nftables 防火墙只放行入站 TCP `443`。

## 一键安装

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
3. Home landing / 家宽 SS 落地
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

如果是 NAT/LXC 面板映射，比如公网 `24496 -> 容器 443`，就改 `ss_link_editable` 里的端口为 `24496`，再粘贴到 DMIT/HK。

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
sb list-relays
sb add-ss 'ss://...'
sb del-relay relay-jp-home-SS
sb add-friend fr1
sb del-user fr1
sb restart
```

说明：

- `add-friend` 添加的是直连 Reality 用户，默认走 direct。
- `add-ss` 添加的是落地中转用户，名字会以 `relay-` 开头。
- 删除落地请用 `del-relay`，删除朋友用 `del-user`。

## 防火墙提醒

DMIT/HK 会写入 nftables，只允许：

```text
入站 TCP 443
已建立连接
loopback
ICMP / IPv6 ICMP
```

这意味着普通 SSH 端口可能会被挡掉。脚本会在启用防火墙前要求输入：

```text
ONLY443
```

如果你确定自己有控制台、救援模式或其他访问方式，也可以用：

```sh
FORCE_ONLY_443_FIREWALL=1 sh install.sh
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
- 443-only 防火墙

舍弃：

- 多 profile 复杂分叉
- 过多 README 和架构图
- 家宽 Reality + SS 混合模式
- 不常用的备份恢复菜单
- 复杂的全自动端口猜测

