# 通过串口进 U-Boot 修改内核参数（mem=496M → 1024M）

> 这块 `antminer_zu2eg_ctrlboard` 有 4 颗 Micron MT41K128M16（D9PTK）DDR3L，
> 每颗 2Gb = 256MB，共 **1GB**（设备树 `memory@0` 也声明了 0x40000000）。
> 但 U-Boot 的 `bootargs` 里有 `mem=496M`，内核只用了 496MB。
> 本教程记录如何通过串口进 U-Boot 把它改回 1024M。

## ⚠️ 风险提示（务必先读）

| 风险 | 说明 |
|---|---|
| **变砖** | 这块板 JTAG 不可用。U-Boot/环境改错且无法串口救回时，没有 JTAG 兜底 |
| **RAM disk 冲突** | cmdline 里 `root=/dev/ram ramdisk_size=33554432`，ramdisk 加载在高端地址。放开到 1GB 后要确认 ramdisk 和 kernel 加载区不重叠 |
| **无回滚** | 没有第二套启动镜像（`nand-uramdisk-bak` 是备份 ramdisk，不是备份 env）|

**建议**：先只读查看（`printenv`），确认每一步再写。改之前把原始 env 完整抄下来存档。

---

## 背景：cmdline 是怎么来的

实测证据链：

```
/proc/cmdline:
  earlycon clk_ignore_unused mem=496M console=ttyPS0,115200 \
  ramdisk_size=33554432 root=/dev/ram rw earlyprintk

/proc/device-tree/chosen/bootargs:
  earlycon                                    ← DTS 里只有这一句

NAND 分区:
  mtd0/1/2  "nand-fsbl-uboot"  (3 份冗余，各 8MB)
  mtd4      "nand-linux-uimage"
  mtd5      "device-tree"
  mtd6      "nand-uramdisk-image"
```

也就是说：**`mem=496M ...` 这一大串是 U-Boot 环境变量 `bootargs`，启动时由 U-Boot 拼好传给内核**。改就要改 U-Boot 的 env。

---

## 准备工作

### 硬件
- **USB-TTL 串口线**（CH340 / CP2102 / FT232 均可），按之前资料接 **MIO31=TX / MIO30=RX**（板子 UART0，LVCMOS18 = **1.8V 电平**！）
  - ⚠️ 用 1.8V 的串口线，别用 5V/3.3V 硬怼（除非确认板上有电平转换）
- 串口参数：**115200 8N1**，无流控

### 软件
- Windows：PuTTY / MobaXterm / SecureCRT
- Linux/macOS：`screen /dev/ttyUSB0 115200` 或 `minicom`

### 关键：找对串口设备
之前归档的 MIO 分析：UART0 (`serial@ff000000`) 的 TX=MIO31、RX=MIO30，
但设备上 `/dev/ttyPS0` 是 PS 串口，`/etc/inittab` 里 `getty 115200 ttyPS0`。
**板子引出的是 CH340 USB-TTY（实测识别为 COM 口）**，接电脑 USB 即可。

---

## 操作步骤

### 第 1 步：进 U-Boot 命令行

1. 接好串口线，打开串口终端（115200 8N1）
2. 给板子上电，**紧盯输出**
3. 看到类似以下提示时**立刻按键**打断自动启动：

```
U-Boot 2019.01 (...)
...
Hit any key to stop autoboot:  3  2  1  0
```

看到倒计时就按任意键（建议按空格）。成功后提示符变成：

```
ZynqMP>
```

> 如果错过倒计时进了 Linux，断电重启再来一次。

### 第 2 步：备份原始环境（必做）

在 `ZynqMP>` 提示符下：

```sh
printenv
```

把**完整输出复制保存到本地文本文件**。尤其注意这几个变量：

```sh
printenv bootargs
printenv bootcmd
printenv ramdisk_size
printenv kernel_addr
printenv devicetree_load_address
printenv ramdisk_load_address
```

### 第 3 步：验证 1GB 内存确实可用

在改参数之前，先在 U-Boot 里测一下物理内存到底多大：

```sh
mtest 0x00000000 0x3FFFFFFF 1 1
```

- 如果跑完不报错 → 物理内存至少到 0x3FFFFFFF（1GB），可以改
- 如果中途报 ECC/timeout → 可能是某颗颗粒坏了，别改

也可以只测高端一小段（更快）：

```sh
mtest 0x30000000 0x30001000 1 1
```

（Linux 里我已经用 `devmem2 0x30000000` 读到有效数据 `0x57F5389E`，说明 768MB 处物理上是好的）

### 第 4 步：修改 bootargs

**方法 A：替换整串（推荐，可控）**

```sh
setenv bootargs 'earlycon clk_ignore_unused mem=1024M console=ttyPS0,115200 ramdisk_size=33554432 root=/dev/ram rw earlyprintk'
```

**方法 B：只替换 mem= 部分（如果 U-Boot 支持 env 变量展开）**

```sh
setenv bootargs ${bootargs/mem=496M/mem=1024M}
```

> 方法 B 依赖 U-Boot 的字符串替换语法支持，不保证所有版本可用，**优先用 A**。

### 第 5 步：确认改动

```sh
printenv bootargs
```

输出应该是：

```
bootargs=earlycon clk_ignore_unused mem=1024M console=ttyPS0,115200 ramdisk_size=33554432 root=/dev/ram rw earlyprintk
```

### 第 6 步：先临时启动测试（不保存）

**重要**：先不要 `saveenv`！先用修改后的 env 直接启动，确认系统能起来：

```sh
boot
```

或（如果 `boot` 不改 env 而走 bootcmd 的旧值）：

```sh
run nandboot
```

等待 Linux 起来后，SSH 进去验证：

```sh
cat /proc/cmdline     # 应看到 mem=1024M
grep MemTotal /proc/meminfo    # 应接近 1024 MB（约 1000 MB 左右）
free -m
```

### 第 7 步：确认无误后永久保存

如果第 6 步成功：

```sh
# 重启回 U-Boot（断电或 reboot）
# 再次 setenv（上一步改的没 saveenv，重启会丢）
setenv bootargs 'earlycon clk_ignore_unused mem=1024M console=ttyPS0,115200 ramdisk_size=33554432 root=/dev/ram rw earlyprintk'

# 保存到 NAND
saveenv
```

输出应类似：

```
Saving Environment to NAND...
Erasing NAND...
Writing to NAND... done
```

再 `boot` 启动，确认 `cat /proc/cmdline` 仍是 `mem=1024M`。

---

## 回滚（如果出问题）

进 U-Boot 后恢复原始值：

```sh
setenv bootargs 'earlycon clk_ignore_unused mem=496M console=ttyPS0,115200 ramdisk_size=33554432 root=/dev/ram rw earlyprintk'
saveenv
boot
```

如果 U-Boot 都进不去，硬件层面还有一条路：NAND 的 mtd0/1/2 是 3 份 FSBL+U-Boot 冗余，断电重上可能自动从另一份启动。

---

## 替代方案（不改 U-Boot，零风险）

如果只是想在用户态访问高位内存，**无需改 cmdline**：

```sh
# 直接通过 /dev/mem mmap 访问 0x30000000 (768MB 处)
devmem2 0x30000000          # 已验证返回 0x57F5389E
```

但这样内核不把这段纳入页管理，只能自己 mmap 裸访问，不能 malloc。

---

## 实测记录（本板）

| 项 | 值 |
|---|---|
| 串口 | CH340 USB-TTY，115200 8N1，1.8V LVCMOS18 |
| U-Boot 分区 | mtd0/1/2 `nand-fsbl-uboot`（3 份 8MB 冗余）|
| 环境变量位置 | `bootargs` 在 mtd1/mtd2 各 4 处匹配 |
| 原 bootargs | `earlycon clk_ignore_unused mem=496M console=ttyPS0,115200 ramdisk_size=33554432 root=/dev/ram rw earlyprintk` |
| 物理内存 | 4 × MT41K128M16 = 1GB（DTS 声明 0x40000000）|
| 高位访问验证 | `devmem2 0x30000000` = `0x57F5389E` ✓ |
| 状态 | 教程已验证路径，**实际修改待用户执行**（避免无 JTAG 时变砖）|

---

## 参考

- 颗粒型号：Micron `MT41K128M16JT-125:K`，FBGA code `D9PTK`，DDR3L-1600 2Gb x16
- 相关文档：`hardware/MIO_引脚分析.md`、`docs/SD卡重启后消失-诊断报告.md`
- 归档仓库：`https://github.com/co27la57/ANTMINER_ZU2EG`
