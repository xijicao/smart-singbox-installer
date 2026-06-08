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
架构树状图.svg
详细架构树状图.svg
```

旧的 JP/IPLC/TW 固定 profile 可以留作本地历史备份，但最终 GitHub 一键流程不再依赖它们。

## 2. 确认 raw 地址

当前仓库地址已经写进 `install.sh`：

```sh
REPO_RAW_BASE_DEFAULT="https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main"
```

上传后浏览器打开这个地址测试：

```text
https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh
```

能看到脚本文本就说明 raw 地址正常。

## 3. 唯一安装命令

所有机器都运行这一条：

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

如果极简系统没有 `curl`，用备用命令：

```sh
wget -qO- https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

然后按菜单选择：

```text
1) DMIT entry machine
2) HK entry machine
3) Home/landing machine - SS2022 only
4) Home/landing machine - Reality + SS2022
```

## 4. 选择规则

DMIT 入口机：

```text
选 1
```

HK 入口/中转机：

```text
选 2
```

家宽、LXC、NAT、IPLC 只装 SS2022 给 DMIT/HK 当落地：

```text
选 3
```

家宽、LXC、NAT、IPLC 同时装直连 Reality + SS2022 落地：

```text
选 4
```

选 `3` 或 `4` 时，脚本会自动识别 Debian/Ubuntu/Alpine。

## 5. 获取安装输出

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

## 6. 导入落地到 DMIT/HK

在 home 落地机器上复制：

```text
ss_link:
ss://...
```

如果是 NAT/LXC 面板端口映射，复制：

```text
ss_link_editable:
ss://method:password@server:port#name
```

把端口手动改成面板公网端口。

然后在 DMIT 或 HK 上运行：

```sh
sing-box-add-ss2022-relay
```

粘贴 `ss://` 链接。完成后会返回一个新的 Reality 链接，比如：

```text
HK-relay-jp-home
DMIT-relay-us-home
```

## 7. 检查命令

Debian/Ubuntu：

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
2) List relay Reality nodes
3) Delete a relay Reality node
4) Show all current Reality links
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

## 10. 记忆规则

后续不用记 profile 参数，也不用记多条安装命令。

只记这一条：

```sh
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

剩下全部交给菜单选择。
