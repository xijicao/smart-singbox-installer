# GitHub 部署步骤

## 1. 上传目录

把这些文件上传到 GitHub 仓库根目录：

```text
install.sh
lib/common.sh
profiles/dmit-debian.sh
profiles/hk-debian.sh
profiles/home-debian.sh
profiles/home-alpine.sh
tools/self-check.sh
.github/workflows/self-check.yml
README.md
README-快速命令.md
GITHUB-部署步骤.md
.gitignore
VERSION
```

可选上传：

```text
思维导图.md
详细架构树状图.svg
```

旧的 JP/IPLC/TW 固定 profile 可以留作本地历史备份，但最终 GitHub 一键流程不再依赖它们。

## 2. 修改 raw 地址

改 `install.sh` 顶部：

```sh
REPO_RAW_BASE_DEFAULT="https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main"
```

## 3. 安装入口机器

DMIT：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=dmit-debian sh
```

HK：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=hk-debian sh
```

安装后看：

```sh
cat /root/dmit-singbox-info.txt
cat /root/hk-singbox-info.txt
```

## 4. 安装落地/中转机器

Alpine 只装 SS2022：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=ss2022 HOME_NODE_NAME=jp-home sh
```

Alpine 同时装 Reality + SS2022：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=both HOME_NODE_NAME=jp-iplc sh
```

Debian 落地把 `PROFILE=home-alpine` 改成 `PROFILE=home-debian`。

如果是 NAT/LXC 面板映射，比如公网 `24496 -> 443`，最省事是先正常安装：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=ss2022 HOME_NODE_NAME=jp-home SS2022_PORT=443 sh
```

然后看 `/root/home-singbox-info.txt` 里的 `ss_link_editable`，把里面的 `:443` 手动改成 `:24496`，再喂给 HK/DMIT。

如果 `HOME_MODE=both`，SS2022 和 Reality 要使用不同端口：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=both HOME_NODE_NAME=jp-iplc SS2022_PORT=443 REALITY_PORT=8443 sh
```

安装后 SS2022 的 `ss_link_editable` 端口按面板公网端口手动改；Reality 链接也在客户端里手动改成面板给 Reality 的公网端口。

## 5. 获取 SS2022 链接

在落地机器上：

```sh
cat /root/home-singbox-info.txt
```

复制：

```text
ss_link:
ss://...

ss_link_editable:
ss://method:password@server:port#name
```

普通公网机器直接复制 `ss_link` 就行。NAT/LXC 映射机器建议复制 `ss_link_editable`，手动把端口改成面板公网端口后再导入。

## 6. 导入到 DMIT 或 HK

在 DMIT 或 HK 上：

```sh
sing-box-add-ss2022-relay
```

第一步直接粘贴 `ss://` 链接。后面如果提示 relay name，可以直接回车使用链接里的名字，也可以手动填：

```text
jp-home
tw-home
us-home
eu-home
```

完成后会返回一个新的 Reality 链接，比如：

```text
HK-relay-jp-home
DMIT-relay-us-home
```

## 7. 检查命令

Debian：

```sh
systemctl status sing-box --no-pager
sing-box check -c /etc/sing-box/config.json
ss -lnpt | grep -E ':443|:8443'
ls -l /root/*singbox-info.txt /etc/sing-box/reality-meta.env
```

Alpine：

```sh
rc-service crond status
rc-service sing-box status
sing-box check -c /etc/sing-box/config.json
ss -lnptu | grep -E ':443|:8443'
ls -l /root/*singbox-info.txt
```
## 8. 统一管理和删除家宽落地

在 DMIT 或 HK 上运行：

```sh
sb
```

或：

```sh
-sb
```

常用操作：

```text
1) Regenerate base Reality links for me/friend
3) Delete a relay Reality node
5) Backup config/meta now
6) Restore latest config/meta backup
7) Update sing-box core only
```

如果某个家宽不用了，选第 `3` 项，按编号删除即可。

如果只是想重新生成你和朋友的基础节点，选第 `1` 项。

如果更新 sing-box core，选第 `7` 项；它只更新二进制，不改配置，并会自动备份和检查。

home 落地机器卸载：

```sh
sing-box-uninstall
```

## 9. GitHub 自检

上传后 GitHub Actions 会跑：

```sh
sh tools/self-check.sh
```

它会做脚本语法检查、active 文件存在性检查、危险旧文案残留检查和假值泄露检查。

## 10. 快速命令文档

更多直接复制的命令看：`README-快速命令.md`
