# smart-singbox-installer-final

Debian 专用的 sing-box 入口机 / 落地机安装与管理脚本。

这版是按以下实际架构整理的：

- **DMIT 美西**：主力 Entry 入口机，使用 DMIT 专属网络 profile。
- **HK / JP / SG / EU / 其他线路机**：Generic Entry 入口机，默认不限速，只做基础优化。
- **netcup DE / 普通 VPS / 家宽 NAT**：Landing 落地机，默认 SS2022，只给 Entry 导入。

脚本目标不是做面板，而是做到：

- 安装稳
- 链接清楚
- 用户好删
- 日志不爆
- 网络 profile 可回滚
- 配置改动前自动备份，改动后先 `sing-box check`

---

## 1. 系统要求

仅支持 Debian：

- Debian 13：推荐用于新重建机器
- Debian 12：兼容，可继续用到 LTS 周期

不支持 Alpine、OpenWrt、CentOS、Ubuntu。本版故意收窄系统范围，减少维护复杂度。

---

## 2. 快速安装

推荐从 GitHub 直接拉取安装。下面默认使用本仓库地址：

```bash
curl -fsSL https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh | sh
```

如果你 fork 到自己的 GitHub，把 `xijicao/smart-singbox-installer` 改成你自己的 `用户名/仓库名` 即可。

也可以先下载到本地检查后再执行：

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/xijicao/smart-singbox-installer/main/install.sh
chmod +x install.sh
./install.sh
```

如果你是手动上传或解压 ZIP，也可以在项目目录里运行：

```bash
chmod +x install.sh
./install.sh
```

安装菜单：

```text
1) 安装 Entry 入口机
2) 安装 Landing 落地机
3) 只安装/更新管理命令 sb
```

安装完成后会复制管理命令到：

```text
/usr/local/bin/sb
```

---

## 3. Entry 入口机

Entry 是给朋友客户端直连的机器。

适合：

- DMIT 主力机
- HK 备用机
- 日本 / 新加坡 / 欧洲 / 韩国等线路机
- 未来新增的任意优化线路机

Entry 支持：

- Reality only
- SS2022 only
- Reality + SS2022
- 添加/删除 Reality 用户
- 添加/删除 SS2022 用户
- 导入 Landing 落地节点
- 生成 Reality -> Landing 的共用 relay 链接

### Entry 类型

安装时会问：

```text
1) DMIT optimized entry
2) Generic entry（HK/JP/SG/EU/其他线路机）
```

区别：

| 类型 | 用途 | 网络策略 |
|---|---|---|
| DMIT optimized | DMIT 美西主力机 | 可选 800M / 900M / 1000M profile |
| Generic entry | HK、日本、新加坡、欧洲等 | 默认不限速，只做 BBR + fq |

HK 不单独作为安装类型，因为它和 Generic entry 技术逻辑一样，只是节点名前缀填 `HK`。

---

## 4. Landing 落地机

Landing 是给 Entry 拉的出口机，不直接作为朋友主入口。

适合：

- netcup 德国 1 欧机
- 普通欧洲 VPS
- 家宽 NAT 机器
- LXC / 小鸡落地

Landing 类型：

```text
1) Generic landing（netcup/普通 VPS/德国落地）
2) Home/NAT landing（家宽/NAT/端口映射）
```

Landing 默认只安装 SS2022，并输出一个：

```text
ss://...
```

然后在 Entry 机器上导入：

```bash
sb add-landing netcup-de 'ss://...'
```

导入后 Entry 会生成类似：

```text
DMIT-US-DE-netcup-de
```

这是 Reality 入口 -> netcup DE SS2022 落地的共用链路。

---

## 5. 常用命令

### 查看链接

```bash
sb links
```

### Reality 用户

```bash
sb add-reality friend1
sb del-reality friend1
```

兼容旧命令：

```bash
sb add-friend friend1
sb del-user friend1
```

### SS2022 用户

```bash
sb add-ss-user friend1
sb del-ss-user friend1
```

### Landing 落地

```bash
sb add-landing netcup-de 'ss://...'
sb del-landing netcup-de
```

兼容旧命令：

```bash
sb add-ss 'ss://...'
```

---

## 6. 网络 profile

### Generic 基础优化

适合 HK / JP / SG / EU / netcup / 家宽落地：

```bash
sb net-install basic
```

效果：

```text
BBR + fq
tcp_mtu_probing=1
tcp_limit_output_bytes=512KB
不做 HTB 限速
不强制 32MB rmem/wmem
```

### DMIT profile

```bash
sb net-install dmit-safe
sb net-install dmit-balanced
sb net-install dmit-performance
```

对应：

| profile | 速率 | tcp_limit_output_bytes | rmem/wmem |
|---|---:|---:|---:|
| dmit-safe | 800mbit | 512KB | 不强制 |
| dmit-balanced | 900mbit | 1MB | 32MB |
| dmit-performance | 1000mbit | 1MB | 32MB |

自定义：

```bash
sb net-install custom 1200mbit
```

移除 HTB 限速：

```bash
sb net-install remove
```

不建议把 2G 作为长期日常档。2G 可以测试，但给朋友长期共享建议优先稳定。

---

## 7. 观测与诊断

即时查看，不写长期日志：

```bash
sb net-status
```

短时观测，不落盘：

```bash
sb net-watch 60
```

完整诊断：

```bash
sb doctor
```

`sb doctor` 会输出：

- 系统版本
- sing-box 版本
- `sing-box check` 结果
- 监听端口
- nftables 防火墙摘要
- 最近 sing-box 日志
- 当前 TCP / tc 状态
- journald 占用

---

## 8. 日志策略

sing-box 默认：

```json
"log": {
  "level": "warn",
  "timestamp": true
}
```

不写独立日志文件，默认走 systemd journal。

脚本会写入 journald 限制：

```ini
SystemMaxUse=200M
SystemMaxFileSize=50M
MaxRetentionSec=14day
```

查看日志占用：

```bash
journalctl --disk-usage
```

---

## 9. 安全提醒

以下文件包含密钥或节点信息：

```text
/etc/sing-box/config.json
/etc/sing-box/sb.env
/etc/sing-box/backups/
```

不要公开上传到 GitHub。

如果要把项目放到自己的 GitHub，只上传本仓库脚本和文档，不要上传服务器上的 `/etc/sing-box`。

---

## 10. 推荐机器分工

```text
DMIT-US：Entry -> DMIT optimized -> dmit-balanced
HK：Entry -> Generic entry -> basic
未来 JP/SG/EU 线路机：Entry -> Generic entry -> basic 或 custom
netcup DE：Landing -> Generic landing -> basic
家宽 NAT：Landing -> Home/NAT landing -> basic
```

---

## 11. 已知设计取舍

本版没有做：

- SSH priority
- 默认 BBRv3
- 默认 CAKE
- 默认 2G profile
- 流量统计 / 到期时间 / 限速用户
- Web 面板
- 订阅转换
- Alpine/Ubuntu/OpenWrt 支持

这些不是不能做，而是当前目标是少维护、可预测。
