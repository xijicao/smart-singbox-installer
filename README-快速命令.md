# 快速命令

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

选 `3` 或 `4` 时，脚本会自动识别 Debian/Ubuntu/Alpine，自动选对应 sing-box 包。Alpine 会优先用 musl 包，Debian/Ubuntu 会优先用 glibc 包，对应包不行再退到通用包。

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

## 3. 把家宽 SS2022 导入到 DMIT/HK

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

## 4. NAT/LXC 端口映射怎么改

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

## 5. DMIT/HK 统一管理菜单

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

## 6. Home 落地卸载

只在 home 落地机器上用：

```sh
sing-box-uninstall
```

执行前会要求输入 `UNINSTALL`，并先打包备份。
