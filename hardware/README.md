# 硬件资料

全部来自对实板的黑盒探测（**互联网上无此板公开资料**）。

| 文件 | 内容 |
|---|---|
| `MIO_引脚分析.md` | 从 `/proc/device-tree` 反编译的 DTS 中解析出的 MIO 引脚定义（UART/ENET/SDIO/I2C/GPIO） |
| `dtb/running.dts` | 板上 `dtc` 反编译当前运行 DTB 的结果（43 KB） |
| `dtb/running.dtb` | 原始 DTB 二进制（37 KB） |
| `dtb/raw.dts` | 另一份反编译输出（保留对照） |
| `dtb/dt_pack.tar` | DTB 相关文件打包 |
| `rootfs/` | 原始 rootfs 的符号链接清单（324 条）、探测日志、网络/存储检查结果 |
| `network/` | 局域网 ICMP/端口扫描、ARP 分析、串口登录尝试脚本 |

## 关键结论速查

- **SoC**：Xilinx ZynqMP (4× Cortex-A53)，64 位内核 + armhf 兼容用户态
- **UART0**：TX = MIO31，RX = MIO30（电平 LVCMOS18 / 1.8V）
- **UART1**：TX = MIO32，RX = MIO33
- **Ethernet2 RGMII**：MIO50-59（LVCMOS33 / 3.3V）
- **MIO64-75**：12 根 GPIO，疑似连到 BM1794 ASIC 的链控制信号
- **电平分组**：UART/I2C/GPIO = 1.8V；SDIO/ENET = 3.3V
