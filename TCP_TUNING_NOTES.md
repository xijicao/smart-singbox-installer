# TCP 调优说明

这份说明用于解释脚本里的网络 profile，不是玄学调参合集。

## 1. 为什么 DMIT 要限速？

你的 DMIT EB Corona 是 2Gbps 接口，但跨境线路真正影响体验的是：

- 晚高峰拥塞
- RTT
- 瞬时突发
- 本机队列
- TCP 重传

原脚本 800M 稳定，说明核心思路是对的：**不要追满 2G，而是把突发压平。**

本版保留：

```text
HTB + fq
BBR
tcp_mtu_probing=1
```

并扩展为 profile：

```text
dmit-safe：800M
dmit-balanced：900M
dmit-performance：1000M
custom：自定义
```

---

## 2. tcp_limit_output_bytes 是什么？

它控制每条 TCP 连接最多允许在本机 qdisc/device 队列里堆多少待发送数据。

可以粗略理解为：

```text
值越小：队列短、突发小、延迟稳，但峰值可能保守
值越大：吞吐更容易上去，但拥塞时延迟/重传风险更高
```

本版使用：

```text
512KB：safe
1MB：balanced/performance
```

不默认使用 2MB，因为你是给朋友长期用，不是只跑测速截图。

---

## 3. 32MB rmem/wmem 是什么？

它是 TCP 接收/发送缓冲区自动调优的上限，不是每条连接固定占 32MB。

高 RTT + 高带宽链路需要更大的窗口。例如：

```text
1000Mbps × 150ms ≈ 18.75MB
1000Mbps × 200ms ≈ 25MB
```

所以 32MB 对 900M/1000M 有意义，但不能保证 2G 稳。

本版只在：

```text
dmit-balanced
dmit-performance
custom
```

启用 32MB rmem/wmem。

Generic entry / landing 默认不启用。

---

## 4. 为什么不用 BBRv3 / CAKE 默认？

因为当前目标是稳定维护，不是内核实验。

BBRv3、CAKE 可以单独测试，但不适合作为默认写进给朋友用的生产入口。

默认主线仍是：

```text
HTB + fq + BBR
```

---

## 5. 怎么观测？

即时状态：

```bash
sb net-status
```

短时观察 60 秒：

```bash
sb net-watch 60
```

重点看：

```text
TcpRetransSegs
TcpOutSegs
Retrans ratio
tc dropped / overlimits
```

`net-watch` 默认不写日志文件，只输出到屏幕。
