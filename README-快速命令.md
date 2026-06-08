# 快速命令

把 `YOUR_GITHUB_USERNAME/YOUR_REPO_NAME` 换成你的仓库。

## 1. 安装 DMIT 入口

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=dmit-debian sh
```

## 2. 安装 HK 入口

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=hk-debian sh
```

## 3. Alpine 落地，只装 SS2022

默认内外端口一样，例如都用 `8443`：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=ss2022 HOME_NODE_NAME=jp-home sh
```

## 4. Alpine 落地，Reality + SS2022 都装

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=both HOME_NODE_NAME=jp-iplc sh
```

## 5. NAT/LXC 端口映射例子

如果 sing-box 在机器里监听 `443`，但面板映射是：

```text
公网 TCP 24496 -> 容器 TCP 443
```

那安装时只写机器内部监听端口：

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=ss2022 HOME_NODE_NAME=jp-home SS2022_PORT=443 sh
```

安装完看 `ss_link_editable`，把里面的 `:443` 改成 `:24496`，再粘给 HK/DMIT。

如果 `both` 同时装 SS2022 和 Reality，要给它们不同的内外端口。比如：

```text
公网 TCP 24496 -> 容器 TCP 443   # SS2022
公网 TCP 24497 -> 容器 TCP 8443  # Reality
```

```sh
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME/main/install.sh | PROFILE=home-alpine HOME_MODE=both HOME_NODE_NAME=jp-iplc SS2022_PORT=443 REALITY_PORT=8443 sh
```

安装后 SS2022 的 `ss_link_editable` 端口按面板公网端口手动改；Reality 的直连链接也同理，客户端里填面板给 Reality 映射的公网端口。

注意：同一个公网端口不能同时给 SS2022 和 Reality 两个不同协议共用，除非你明确知道面板和协议能这样转发。更稳是给它们映射不同公网端口。

## 6. 查看落地机器输出

```sh
cat /root/home-singbox-info.txt
```

复制里面的：

```text
ss_link:
ss://...
```

## 7. 导入到 DMIT/HK

在 DMIT 或 HK 上：

```sh
sing-box-add-ss2022-relay
```

粘贴 `ss://` 链接。

## 8. 管理菜单

```sh
sb
```

或：

```sh
-sb
```

常用：

```text
1) 重新生成你和朋友基础 Reality 链接
3) 删除某个 relay 家宽落地
4) 查看所有当前 Reality 链接
5) 备份当前 config/meta
6) 恢复最新备份
7) 只更新 sing-box core
```

也可以直接这样跑：

```sh
sb backup
sb restore-latest
sb update-core
```

## 9. Home 落地卸载

只在 home 落地机器上用：

```sh
sing-box-uninstall
```

执行前会要求输入 `UNINSTALL`，并先打包备份。

## 10. ss:// 链接长什么样

标准形式大概像这样：

```text
ss://MjAyMi1ibGFrZTMtYWVzLTI1Ni1nY206cGFzc3dvcmRAZXhhbXBsZS5jb206MjQ0OTY#jp-home-SS2022
```

它本质上包含：

```text
method:password@server:port
```

其中 `port` 必须是客户端实际访问的公网端口。比如 `24496 -> 443`，链接里就写 `24496`。

能不能手动改 `ss://` 里的端口？可以。脚本会额外输出一条明文形式：

```text
ss_link_editable:
ss://method:password@server:443#jp-home-SS2022
```

如果面板是 `24496 -> 443`，你把这条明文链接里的 `:443` 改成 `:24496`，再粘给 HK/DMIT 就行。home 机器实际监听端口不用改。
