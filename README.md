# Smart sing-box Installer

![详细架构树状图](./详细架构树状图.svg)

这是给你放到 GitHub 上用的 sing-box 智能一键安装器。

## 快速命令

常用安装、导入、删除、NAT 端口映射示例看：

[README-快速命令.md](./README-快速命令.md)

## 最终架构

只分两类机器：

1. 入口机器：`DMIT`、`HK`
2. 落地/中转机器：家宽、LXC、NAT、IPLC

IPLC 不再单独特殊处理。它性能好就装 `both`，性能一般或直连不好就只装 `ss2022`。

## 入口机器

### DMIT

1. 2G 带宽，双栈，日常主力
2. 默认生成两个 Reality 节点：你和朋友
3. 以后可粘贴任意 `ss://` 落地链接，自动生成对应 Reality 中转节点

### HK

1. 10 Mbps 小水管，IPv4 单栈
2. 默认生成两个 Reality 节点：你和朋友
3. 作为国际互联中心，中转日本、台湾、美国、欧洲等落地
4. 每粘贴一个 `ss://`，自动生成一个新的 Reality 中转节点用于手动切换

DMIT/HK 安装后都会有：

```sh
sing-box-add-ss2022-relay
```

## 落地/中转机器

统一使用：

```text
home-alpine
home-debian
```

安装模式：

1. `ss2022`：只做落地，给 DMIT/HK 中转
2. `reality`：只做直连 Reality
3. `both`：同时做直连 Reality + SS2022 落地

安装完会自动生成：

```text
/root/home-singbox-info.txt
```

如果启用了 SS2022，里面会直接给出 `ss_link`，复制到 DMIT/HK 的 `sing-box-add-ss2022-relay` 即可。

## 一行命令示例

DMIT：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=dmit-debian sh
```

HK：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=hk-debian sh
```

Alpine 落地，只装 SS2022：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=ss2022 HOME_NODE_NAME=jp-home sh
```

Alpine 落地，同时装 Reality + SS2022：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=both HOME_NODE_NAME=jp-iplc sh
```

Debian 落地同理，把 `home-alpine` 改成 `home-debian`。

## 导入落地到 DMIT/HK

在落地机器上：

```sh
cat /root/home-singbox-info.txt
```

复制里面的：

```text
ss_link:
ss://...
```

然后在 DMIT 或 HK 上运行：

```sh
sing-box-add-ss2022-relay
```

粘贴 `ss://` 链接即可。脚本会自动：

1. 解析 method/password/server/port/name
2. 备份 `/etc/sing-box/config.json`
3. 新增 SS2022 outbound
4. 新增 Reality UUID 和 short_id
5. 把这个 Reality 用户路由到该 SS2022 落地
6. `sing-box check` 通过后重启
7. 返回新的 `vless://` Reality 中转链接

## sing-box 下载顺序

默认拉 GitHub latest。

1. Debian/Ubuntu：先尝试 `glibc` 包，再尝试通用包
2. Alpine：先尝试 `musl` 包，再尝试通用包

也可以锁定版本：

```sh
SINGBOX_VERSION="1.13.13"
```

## 安全

敏感信息默认保存在：

```text
/root/*singbox-info.txt
/etc/sing-box/reality-meta.env
```

权限默认 `600`，只有 root 能读写。不要上传到 GitHub。
## 统一管理菜单

DMIT/HK 安装后可以运行：

```sh
sb
```

或者：

```sh
-sb
```

菜单功能：

1. 重新生成你和朋友的基础 Reality UUID / short_id，并输出新链接
2. 列出所有 `relay-*` 家宽落地中转节点
3. 删除指定 `relay-*` 家宽落地中转节点
4. 查看所有当前 Reality 链接
5. 立刻备份当前 config/meta/core 到 `/etc/sing-box/backups`
6. 恢复最新一份 config/meta 备份，并检查配置后重启
7. 只更新 sing-box core，不改配置，失败会恢复旧 core

删除家宽落地时，选择第 `3` 项即可。脚本会自动删除对应 Reality 用户、SS2022 outbound 和 route 规则，并在修改前备份配置。

更新 sing-box core 时，选择第 `7` 项即可。它会先备份旧二进制和配置，再下载新版本，`sing-box check` 通过后才重启；失败会恢复旧二进制。

home 落地机器安装后还会有一个卸载命令：

```sh
sing-box-uninstall
```

这个只用于家宽/LXC/NAT/IPLC 落地机器，执行前需要输入 `UNINSTALL` 确认，并会先打包备份到 `/root/sing-box-uninstall-backup-*.tar.gz`。

## GitHub 自检

仓库里带了：

```text
tools/self-check.sh
.github/workflows/self-check.yml
```

上传到 GitHub 后，每次 push 会自动检查 active 脚本是否能 `sh -n` 通过、关键文件是否存在、旧的危险 Reality 全量轮换文案是否残留、假 IP/假密钥是否漏进 active 文件。
## NAT/LXC 端口映射

这里分清两个端口就行：

1. `SS2022_PORT` 是 home 机器里面 sing-box 实际监听的端口。
2. 面板公网映射端口是 HK/DMIT 真正要连接的端口。
3. 比如面板是 `24496 -> 443`，home 机器里监听 `443`，但喂给 HK/DMIT 的 `ss://` 端口要写 `24496`。

安装后 `/root/home-singbox-info.txt` 会给两种 SS 链接：

```text
ss_link:
ss://base64...

ss_link_editable:
ss://method:password@server:443#jp-home-SS2022
```

如果是 `24496 -> 443`，你直接把 `ss_link_editable` 里的 `:443` 改成 `:24496`，再粘贴到 HK/DMIT 的 `sing-box-add-ss2022-relay` 即可。机器实际监听端口不需要跟着改。

如果同一台机器用 `HOME_MODE=both`，SS2022 和 Reality 必须使用不同端口。推荐这样分开：

```text
公网 TCP 24496 -> 容器 TCP 443   # SS2022 落地
公网 TCP 24497 -> 容器 TCP 8443  # Reality 直连
```

安装时只需要写机器内部监听端口：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=both HOME_NODE_NAME=jp-iplc SS2022_PORT=443 REALITY_PORT=8443 sh
```

安装后 SS2022 用 `ss_link_editable` 手动改公网端口；Reality 直连链接也在客户端里手动改成面板映射给 Reality 的公网端口。
