# ANTMINER_ZU2EG — 板卡资料归档

> 一块**没有任何公开资料**的比特大陆矿机控制板的逆向工程与再利用记录。
> 本仓库把散落在聊天、脚本、截图、二进制 dump 中的全部资料整理成可检索的归档，
> 并附带一个可复现的 **VNC 虚拟桌面 + Bad Apple!!** 演示例程。

---

## ⚠️ 板卡身份与来历

| 项目 | 信息 |
|---|---|
| 板卡标识 | `antminer_zu2eg_ctrlboard` |
| 厂商 | 比特大陆（Bitmain） |
| 原用途 | Antminer E7 以太坊矿机的**控制板**（不是算力板） |
| 主控 SoC | Xilinx **Zynq UltraScale+ MP**（ZynqMP），4× Cortex-A53 |
| 算力芯片 | **BM1794**（比特大陆 ASIC，通过 AXI / FPGA 逻辑连到 PS） |
| 内核 | Linux 4.9.0，aarch64，开启 `CONFIG_COMPAT`（可跑 armhf 用户态） |
| 原厂用户态 | Angstrom / BusyBox 1.20.2 |
| 串口 | CH340 USB-TTY（实测 COM13），115200 8N1，`antMiner login:` |
| 默认凭据 | Web `root/root`，SSH `root/admin` |

### 为什么这个仓库有必要

**截至归档时，互联网上搜索 `antminer_zu2eg_ctrlboard` 没有任何有效的公开资料** ——
没有原理图、没有 BSP、没有 DTS 源码、没有 GPIO 定义表。这块板子的资料只存在于
矿机固件和硬件本身里。本仓库的内容全部来自对实板的**黑盒探测**：

- 从 `/proc/device-tree` 经板上 `dtc` 反编译导出完整 DTS（见 [`hardware/dtb/`](hardware/dtb/)）
- 从 DTS 的 pinctrl 节点反推出 MIO 引脚分配（见 [`hardware/MIO_引脚分析.md`](hardware/MIO_引脚分析.md)）
- 通过 SSH  streaming dump 整个 rootfs（36 MB / 1635 条目，符号链接清单见 [`hardware/rootfs/`](hardware/rootfs/)）
- 通过 ARP / ICMP / 端口扫描定位设备（脚本见 [`hardware/network/`](hardware/network/)）

> **注意**：本仓库不包含原厂固件镜像或受版权保护的二进制分发，只包含从运行中系统导出的
> 设备树文本、清单和自研脚本。请自行评估合规风险。

---

## 🔥 头等大事：关闭挖矿程序

**这块板子出厂即运行挖矿程序。把它当开发板用时，第一件事就是关掉挖矿 —— 否则 ASIC 持续满负荷供电发热，且矿池不可达时纯属浪费电。**

### 为什么必须关（实测数据）

对本次归档的板子实测：

| 证据 | 数值 / 现象 |
|---|---|
| 主进程 | `/usr/bin/cgminer`（还有 `SCREEN -S cgminer` 包裹） |
| 看门狗 | `/sbin/monitorcg`，由 **`/etc/inittab` 的 `dcdc:2345:respawn:`** 拉起，20 秒检查一次 |
| 矿池配置 | `stratum+tcp://192.168.100.102:8028` —— 内网地址，已不可达 |
| 实际状态 | cgminer 单线程、`wchan=hrtimer_nanosleep`、22814 次自愿上下文切换、**无任何矿池连接** → 只是空转重连 |
| 散热 | `/tmp/fanstatus` = `0 fans are mounted! please check the fans!` |
| 发热源 | GPIO404（原厂脚本注释 `POWER ASIC`）被拉高，BM1794 ASIC 持续通电 |
| 温度读取 | 老内核 4.9 **不导出** `/sys/class/thermal` / hwmon，读不到数字 |
| 关闭后 | loadavg 从 1.06 → 0.13，GPIO403/404 = 0，桌面栈完好 |

### 关闭步骤（顺序很重要）

完整脚本在 [`mining-disable/`](mining-disable/)，日志在同目录。核心流程：

```sh
# 1. 先杀 watchdog —— 否则 20 秒内它就把 cgminer 拉回来
kill -9 $(pidof monitorcg) 2>/dev/null
#    注意：它在 inittab 里是 respawn，光杀进程会无限复活

# 2. 再杀 cgminer 和 screen
kill -9 $(pidof cgminer) 2>/dev/null
#    另需找到 "SCREEN -S cgminer ..." 进程并 kill

# 3. 注释掉 inittab 的 respawn 行（关键！）
cp /etc/inittab /etc/inittab.bak
sed -i 's|^dcdc:2345:respawn:/sbin/monitorcg|#dcdc:2345:respawn:/sbin/monitorcg  # DISABLED|' /etc/inittab
kill -HUP 1                      # 让 init 重载 inittab

# 4. 禁用开机自启（改名而非删除，可恢复）
mv /etc/rcS.d/S70cgminer.sh      /etc/rcS.d/S70cgminer.sh.disabled
mv /etc/init.d/cgminer.sh        /etc/init.d/cgminer.sh.disabled
mv /sbin/monitorcg               /sbin/monitorcg.disabled

# 5. 断 ASIC 电源（cgminer.sh 里注释 GPIO404 = POWER ASIC）
echo 0 > /sys/class/gpio/gpio404/value
echo 0 > /sys/class/gpio/gpio403/value
```

**验证**（必须等 > 20 秒，超过 watchdog 周期）：

```sh
sleep 25
ps | grep -E 'cgminer|monitorcg' | grep -v grep    # 应为空
cat /sys/class/gpio/gpio404/value                   # 应为 0
cat /proc/loadavg                                  # 应降到 0.1 左右
```

### 恢复挖矿（不推荐）

把上述所有 `.disabled` 改名回去、`/etc/inittab` 取消注释、`kill -HUP 1`、
`echo 1 > /sys/class/gpio/gpio404/value` 上电、最后 `/etc/init.d/cgminer.sh start`。
**恢复前务必确认风扇已装好**，否则会过热损坏 ASIC。

---

## 🖥️ 演示例程：VNC 虚拟桌面 + Bad Apple!!

完整教程在 [`docs/VNC桌面与BadApple-完整技术文档.md`](docs/VNC桌面与BadApple-完整技术文档.md)，
可直接使用的脚本和依赖在 [`demo-vnc-desktop/`](demo-vnc-desktop/)。

### 架构

```
Xvfb :1  (1280x800x24 虚拟帧缓冲)
  └─ x11vnc (0.0.0.0:5900, 无密码)
       └─ xfce4 session (顶栏 + 底部 dock)
            ├─ mpv          → Bad Apple!! 循环播放
            ├─ Dillo        → 轻量浏览器（480MB 内存无法跑 Firefox/Chromium）
            └─ xfdesktop    → 桌面图标
```

**为什么用 Xvfb**：板子没有 `/dev/fb0`，也没有 HDMI 输出，只能用虚拟帧缓冲 + VNC。

### 一键启动

把 `demo-vnc-desktop/scripts/start_desktop.sh` 放到板子 `/mnt/sd2/start_desktop.sh`：

```sh
sh /mnt/sd2/start_desktop.sh
```

脚本会自动完成：重建 SD 卡设备节点 → 挂载 → bind `/proc` `/sys`（**绝不 bind `/dev`**）→
dbus → 生成 MIME 数据库 → Xvfb → x11vnc → xfce4 → mpv → Dillo。

然后用任意 VNC 客户端连 `<板子IP>:5900`。

### 演示例程目录

| 路径 | 内容 |
|---|---|
| [`scripts/start_desktop.sh`](demo-vnc-desktop/scripts/start_desktop.sh) | 一键启动整个桌面 + 视频 + 浏览器 |
| [`scripts/badapple.sh`](demo-vnc-desktop/scripts/badapple.sh) | Bad Apple 播放包装（windowed / fullscreen） |
| [`deps/`](demo-vnc-desktop/deps/) | 浏览器 / 中文字体 / MIME 数据库的 tar 包及清单 |
| [`testpage.html`](demo-vnc-desktop/testpage.html) | 本地测试页（验证 HTML/CSS 渲染） |
| [`screenshots/`](demo-vnc-desktop/screenshots/) | 各阶段 VNC 截图（含中文字体修复前后对比） |

### 部署时的关键坑（详见技术文档）

1. **绝对不要 bind-mount `/dev` 进 chroot** —— 会摧毁宿主机 devtmpfs，导致 ext4 被强制只读
2. chroot 必须有 `/etc/ld.so.conf` 并跑 `/sbin/ldconfig`，否则所有动态程序都报 `cannot open shared object file`
3. **Windows 无法创建 POSIX 符号链接** —— .deb 必须在板子上解包
4. BusyBox tar 用 `-X` 而不是 `--exclude`
5. gdk-pixbuf 用 GIO MIME 嗅探，**图标红叉的真因是 shared-mime-info 的 postinst 没跑**，
   修复：`update-mime-database /usr/share/mime`
6. Xvfb 默认只有 6 个内置字体，需 `mkfontdir` + `xset +fp` 才有 CJK
7. mpv 默认失焦自动暂停，需 `--input-vo-keyboard=no`
8. Debian 的 xfce4-panel 不含 dock 插件，底部 dock 用 `launcher` 插件实现

### 演示视频素材

`Bad Apple!!` 视频（7.3 MB，H.264 480×360 30fps，3:39）未随仓库分发，获取方式：

```
https://cdn.jsdelivr.net/gh/aloyak/badapple@master/video/badapple.mp4
```

放到板子 `/root/videos/badapple.mp4` 即可。

---

## 📁 仓库目录总览

```
.
├── README.md                          ← 本文件
├── hardware/
│   ├── MIO_引脚分析.md                 ← 从 DTB 反推的引脚定义
│   ├── dtb/                           ← running.dtb / running.dts / raw.dts
│   ├── rootfs/                        ← 原始 rootfs 的清单、符号链接、探测记录
│   └── network/                       ← 局域网扫描 / 串口探测脚本
├── docs/
│   └── VNC桌面与BadApple-完整技术文档.md  ← 踩坑全集（10 大坑）
├── demo-vnc-desktop/                  ← 可复现的 VNC 桌面演示例程
│   ├── scripts/                       ← 一键启动脚本
│   ├── deps/                          ← 依赖 tar 包与官方 md5 清单
│   ├── screenshots/                   ← 过程截图
│   └── testpage.html                  ← 浏览器渲染测试页
├── mining-disable/                    ← 挖矿进程排查与关闭（脚本 + 原始日志）
├── scripts/                           ← 通用工具（二进制流传输、RFB 截图客户端）
└── screenshots/                       ← 最终桌面 / 浏览器截图集

docs/U-Boot修改内存参数教程.md         ← 串口进 U-Boot 放开 1GB 内存
```

## 内存真相：物理 1GB，被 `mem=496M` 砍半

板上有 **4 颗 Micron MT41K128M16（FBGA `D9PTK`）**，是 **DDR3L**（非 DDR4）、
每颗 2Gb = 256MB、x16 位宽。四颗组成 64-bit 总线接在 PS DDR 控制器上，
**物理容量 1GB**（设备树 `memory@0` 声明 `0x40000000`）。

但 U-Boot 的 `bootargs` 里有 `mem=496M`，内核只用了 496MB：
```
/proc/cmdline: ... mem=496M console=ttyPS0,115200 root=/dev/ram rw ...
```
实测 `devmem2 0x30000000`（768MB 处）能读到有效数据，证明高位物理内存完好。

完整分析与三种修改方案见 [`docs/U-Boot修改内存参数教程.md`](docs/U-Boot修改内存参数教程.md)。

## 硬件参数速查

```
CPU      4× ARM Cortex-A53 (ARMv8, NEON/ASIMD), Xilinx Zynq UltraScale+ MP
RAM      物理 1GB (4×256MB DDR3L)，内核参数限制为 496MB，无 swap
Flash    NAND 128MB: mtd0-2 FSBL+U-Boot(3份冗余), mtd4 uImage,
         mtd5 DTB, mtd6/mtd9 uramdisk, mtd7 config(JFFS2)
根文件系统 原厂从 NAND 恢复，/etc /sbin 修改不持久；持久存储只有 /config 和 SD 卡
SD       8 GB ext4, chroot 根目录约 886 MB
Kernel   4.9.0+ SMP aarch64, CONFIG_COMPAT (armhf 兼容)
网络     1× 千兆 eth0 (GEM2, MIO50-59), DHCP
显示     无 /dev/fb0, 无 HDMI → Xvfb 虚拟帧缓冲
温度     内核不导出 thermal/hwmon 节点
```

## 许可与致谢

本仓库为个人逆向工程与学习记录，不构成比特大陆官方资料。
`Bad Apple!!` 相关素材版权归原作者所有，仓库只提供获取链接与播放方案。

归档时间：2026-11-16
