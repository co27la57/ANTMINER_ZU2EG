# Antminer E7 (ZynqMP) — Linux 桌面 + Bad Apple!! Demo

## 成果

在一台比特大陆 **Antminer E7** 矿机上跑起了完整的 Xfce4 图形桌面，并通过 VNC 对外提供，
同时全屏播放经典的 **Bad Apple!!** 影绘动画。

```
板子    : 172.25.81.151   (Antminer E7, Xilinx Zynq UltraScale+ MP, BM1794 ASIC)
VNC     : vncviewer 172.25.81.151:5900   (无密码)
视频    : /root/videos/badapple.mp4  (H.264 480x360@30fps + AAC, 3:39)
一键启动: sh /mnt/sd2/start_desktop.sh
```

## 架构

| 层 | 内容 |
|---|---|
| 宿主 | Angstrom (armhf, BusyBox 1.20)，内核 4.9.0+antMiner，ZynqMP 64 位内核跑 32 位用户态 |
| 存储 | SD 卡 p1：8 GB ext4 → `/mnt/sd2` |
| 用户态 | Debian **stretch armhf** chroot → `/mnt/sd2/debian`（约 385 MB，330+ 个包） |
| 显示 | Xvfb `:1` 1280×800×24（板子无 /dev/fb0、无 HDMI 输出） |
| 远程 | x11vnc 0.9.13，监听 `0.0.0.0:5900`，`-auth none` |
| 桌面 | xfce4-session（xfce4-panel + xfdesktop + xfwm4） |
| 播放 | mpv 0.23（软件解码，无 GPU 加速） |

## 启动流程

`/mnt/sd2/start_desktop.sh` 按顺序做：

1. 重建 `/dev/mmcblk*` 节点（拔插卡后 major:minor 会变）→ 挂载 SD 卡
2. bind-mount `/proc`、`/sys` 进 chroot（**绝不挂 `/dev`**）
3. 在 chroot 内 `mknod` 造 `/dev/null`、`/dev/zero`、`/dev/ttyS*` 等节点
4. 启动 dbus system bus
5. 启动 Xvfb → 启动 x11vnc → 启动 xfce4 各组件 → 启动 mpv

日志：`/mnt/sd2/desktop.log`

## 踩过的坑（复用时直接照做）

### 1. 绝对不要 bind-mount `/dev` 进 chroot

bind-mount 宿主 `/dev` 会让 devtmpfs 的设备节点从宿主的 `/dev` 里"消失"，
导致 `/dev/null`、`/dev/zero`、`/dev/mmcblk*` 全部消失，且内核把 ext4 强制切成只读。

正确做法：只 bind `/proc` 和 `/sys`，`/dev` 下的节点用 `mknod` 在 chroot 内单独创建。

### 2. chroot 必须有 `/etc/ld.so.conf` 和 `/etc/ld.so.cache`

缺这两个时，动态链接器**找不到 multiarch 目录下任何一个库**（`/usr/lib/arm-linux-gnueabihf/`），
所有程序都报 `cannot open shared object file`。这是排查最久的一个坑。

```sh
cat > /etc/ld.so.conf <<'EOF'
/usr/local/lib/arm-linux-gnueabihf
/lib/arm-linux-gnueabihf
/usr/lib/arm-linux-gnueabihf
/usr/lib
/lib
EOF
/sbin/ldconfig          # ldconfig 在 /sbin，不在 PATH 里
```

### 3. .deb 必须在板子上解包

Windows 无法创建 POSIX 符号链接（需开发者模式），而 Debian 包里符号链接很多。
流程：本机 `busybox ar` + `tar` 抽出 `data.tar.xz` → 用 Python `lzma` 解压成 tar → 推给板子 → 板子上 `tar xf`。

### 4. 包名要用 Contents 索引查，不能靠猜

Debian 包名和 soname 没有简单对应关系：

| soname | 包名 |
|---|---|
| `libsmbclient.so.0` | `libsmbclient` |
| `libsamba-util.so.0` | `samba-libs` |
| `libwebpmux.so.2` | `libwebpmux2` |
| `libavc1394.so.0` | `libavc1394-0` |
| `libiec61883.so.0` | `libiec61883-0` |
| `libopencv_core.so.2.4` | `libopencv-core2.4v5` |

查法：`Contents-armhf.gz` 索引（文件路径 → 包名），不是 `Packages` 的 `Provides` 字段。

### 5. 递归闭包，别逐个补库

逐个试错每次只暴露一个新依赖。正确做法：从 Contents 索引建 `soname → package` 映射，
对每个包的 ELF 读 `DT_NEEDED`，递归展开，一次算全（本次解析出 85 个缺失包）。

### 6. 工具链选择

| 需求 | 选择 | 原因 |
|---|---|---|
| SSH/SFTP | PuTTY **plink/pscp** 0.85 | 本机 OpenSSH 9.5 对 dropbear 2012.55 静默失败；`-hostkey` 跳过交互；`-scp` 强制传统 SCP（板子无 sftp-server） |
| 二进制传输 | .NET `Process` + `StandardOutput.BaseStream` | PowerShell `1>` 重定向会把二进制转成 UTF-16LE，文件损坏 |
| 下载 | PowerShell `Invoke-WebRequest` | 本机 `curl.exe` 的 HTTPS 不通 |
| 板子上下载 | `curl` 仅 HTTP | 板子 GnuTLS 太老，TLS 握手失败；只有 Debian 镜像通 |

### 7. 图标全部显示红叉（真正根因，排查了 6 轮才定位）

**症状**：桌面上所有图标、应用菜单里的所有图标，都是红色"破图"叉；
`gdk-pixbuf-csource xxx.png` 报
`Couldn't recognize the image file format for file 'xxx'`。

**根因**：`gdk-pixbuf` 被编译成 `GDK_PIXBUF_USE_GIO_MIME` 模式
（`configure.ac` 里探测 gio 能否嗅探 image/png 时定义），
于是它**不靠魔术字节、而是靠 GIO 的 MIME 类型**来匹配图片：

```c
/* gdk-pixbuf-2.36.5/gdk-pixbuf/gdk-pixbuf-io.c : _gdk_pixbuf_get_module() */
#ifdef GDK_PIXBUF_USE_GIO_MIME
    mime_type = g_content_type_guess (NULL, buffer, size, &uncertain);
    /* 再拿 mime_type 去比 info->mime_types */
#else
    score = format_check (module, buffer, size);   /* 魔术字节路径，本机没走 */
#endif
```

而 GIO 的 `g_content_type_guess()` 依赖 **shared-mime-info 的数据库**：
`/usr/share/mime/magic`（file(1) 风格魔术库）+ `mime.cache` + `globs2` …
这些文件由 shared-mime-info 的 **postinst** 生成：

```sh
# /var/lib/dpkg/info/shared-mime-info.postinst
update-mime-database /usr/share/mime
```

**我们的 .deb 是手工 `tar` 解包安装的，postinst 从未执行** →
`/usr/share/mime/` 只有 XML，`magic` 和 `mime.cache` 都不存在 →
GIO 一律返回 `application/octet-stream` → gdk-pixbuf 一个格式都匹配不上 →
**所有图片都变成红叉**。

**修法**（一行）：

```sh
busybox chroot /mnt/sd2/debian /bin/sh -c 'update-mime-database /usr/share/mime'
```

生成物：`magic` (27 KB)、`mime.cache` (134 KB)、`globs2`、`aliases`、`subclasses`…
之后 `g_content_type_guess` 立刻返回 `image/png` / `image/jpeg`，红叉全部消失。

**排查过程中排除的干扰项**（都曾被误判为元凶，值得记下来）：

| 假设 | 验证方法 | 结论 |
|---|---|---|
| `loaders.cache` 缺失 | `ls /usr/lib/arm-linux-gnueabihf/gdk-pixbuf-2.0/2.10.0/loaders.cache` | 确实缺，但补上后仍失败（该文件只提供格式**元数据**） |
| `loaders.cache` 扩展名字段为空 | 手工重写 cache | 解析正常，无 "Error parsing loader info" |
| gdk-pixbuf runtime 版本错乱 | `md5sum` 对比 Debian 官方 | `libgdk_pixbuf-2.0.so.0.3600.5` md5 完全一致 ✅ |
| loader 模块损坏 | 13 个 loader md5 全部对比官方 | 全部一致 ✅ |
| loader 无法 dlopen | `ctypes.CDLL()` 裸 dlopen | 13 个全部成功 ✅ |
| GModule 坏了 | `g_module_open()` 段错误 | 是 ctypes 调用姿势的问题，**假象** ❌ |
| PNG 文件本身损坏 | 逐 chunk 校验 PNG CRC | 签名/IHDR/所有 chunk CRC 全通过 ✅ |
| `/lib` 是影子库遮蔽 `/usr/lib` | `ls -ld /lib` | `/lib -> usr/lib` 符号链接，无遮蔽 ❌ |
| **shared-mime-info 数据库缺失** | `g_content_type_guess()` 返回 `application/octet-stream` | **✅ 真凶** |

**顺带修的两个小毛病**：
- `~/.gtkrc-2.0` 里 GTK2 的布尔值要写 `TRUE`/`FALSE`，写 `true`/`false` 会刷
  `failed to retrieve property 'gtk-menu-images' of type 'gboolean'` 警告；
  Adwaita 是 GTK3 主题，GTK2 要用 `gtk-theme-name="Xfce"`。
- xfce4-panel 的单实例检查基于 GApplication，**上一个 Xvfb 时代残留的 panel
  进程会让新 panel 拒绝启动**（`There is already a running instance`）。
  必须在 chroot **外面**用 `kill -9 $(pidof xfce4-panel)` 清掉。

### 7b. Debian 官方 xfce4-panel 没有 dock 插件

`Contents` 索引查证：`xfce4-panel` 4.12.2 只提供
`actions / applicationsmenu / clock / directorymenu / launcher / pager /
pulseaudio-plugin / separator / showdesktop / systray / tasklist / thunar-tpa /
windowmenu` —— **没有 `dock`，也没有 `spacer`**。
底部 dock 用 `launcher` 插件（大图标横向排列）实现，效果等同。

`panel-1.xml`（顶栏）+ `panel-2.xml`（底部 dock）的 XML 写在
`/root/.config/xfce4/xfce4-panel/`。注意：`spacer` 插件不存在，
弹性空白要用 `separator` + `expand=true` 代替。

### 8. SD 卡拔插后设备号会变

`/dev/mmcblk0` 的 major:minor 每次重新枚举都不同（179:0/1/2 → 179:8/9/10 → 179:16/17）。
脚本必须从 `/proc/partitions` 解析并重建节点，不能硬编码。

### 9. 视频素材获取路径

本机 HTTPS 对 GitHub/Wikimedia 不通，但 **cdn.jsdelivr.net** 和 **api.github.com** 可用。
Bad Apple!! 视频取自 `aloyak/badapple` 仓库的 `video/badapple.mp4`：

```
https://cdn.jsdelivr.net/gh/aloyak/badapple@master/video/badapple.mp4
```

### 10. mpv 在无头 VNC 里会"失焦自动暂停"

mpv 默认 `--input-vo-keyboard=yes`，会通过 X 窗口抓键盘；
**一旦窗口失去焦点就暂停播放**。在 headless 的 Xvfb + VNC 场景里，
焦点几乎立刻就丢了，视频会定格在第一帧。

修法：`--input-vo-keyboard=no`（另加 `--keep-open=always`）。

判断"到底播没播"不要看 mpv 的状态行（它是节流输出的，`AV: 00:00:08` 看着像卡住），
**用两帧 RFB 截图做字节级 diff** 更可靠：

```python
# 两张截图间隔 6 秒，像素差异 > 1% 就说明画面在动
diff = sum(1 for x, y in zip(rawA, rawB) if x != y) / len(rawA)
```

本次实测差异 12.53% —— 播放正常。
另外这颗 A53 没有硬件解码，480x360 H.264 软解会掉帧（约丢 50%），
属于算力极限，不是配置问题。



## 挖矿进程的排查与关闭（功耗/温度问题）

### 现象
板子功耗和温度都很高。排查发现原厂挖矿栈仍在运行。

### 发现
| 项 | 内容 |
|---|---|
| 主进程 | PID 1903 `/usr/bin/cgminer`（带 `--api-listen --api-groups ...`）|
| 包裹进程 | PID 1902 `SCREEN -S cgminer` |
| **看门狗** | `/sbin/monitorcg`（由 **`/etc/inittab` 的 `dcdc:2345:respawn:`** 拉起，20 秒检查一次，cgminer 死了就重启）|
| 启动脚本 | `/etc/rcS.d/S70cgminer.sh`、`/etc/init.d/cgminer.sh` |
| 矿池配置 | `/config/cgminer.conf` → `stratum+tcp://192.168.100.102:8028`（内网地址，已不可达）|
| 硬件节点 | cgminer 持有 `/dev/axi_fpga_dev`；启动脚本操作 GPIO403/404 给 ASIC 供电/复位 |
| 风扇 | `/tmp/fanstatus` = `0 fans are mounted! please check the fans!` |

**关键判断**：cgminer 只有 1 个线程、`wchan=hrtimer_nanosleep`、
22814 次自愿上下文切换、CPU 3 秒仅涨 69 ticks，**矿池无连接** →
它没有产出算力，只是在空转重连；功耗主要来自被 GPIO404 通着电的 **BM1794 ASIC**。
加上 0 风扇，热量散不出去。

### 关闭步骤（顺序很重要）
```sh
# 1. 先杀 watchdog，否则 20 秒内会把 cgminer 拉回来
kill -9 $(pidof monitorcg) ...
# 2. 再杀 cgminer + screen
# 3. 注释掉 inittab 里的 respawn 行，然后 kill -HUP 1 让 init 重载
sed -i 's|^dcdc:2345:respawn:/sbin/monitorcg|#dcdc:...  # DISABLED|' /etc/inittab
kill -HUP 1
# 4. 禁用启动脚本（改名，可恢复）
mv /etc/rcS.d/S70cgminer.sh{,.disabled}
mv /etc/init.d/cgminer.sh{,.disabled}
# 5. 断 ASIC 电源（cgminer.sh 里注释：GPIO404 = POWER ASIC）
echo 0 > /sys/class/gpio/gpio404/value
echo 0 > /sys/class/gpio/gpio403/value
```
**验证**：等待 > 20 秒后复查无进程；GPIO403/404 = 0；loadavg 降到 0.1 左右。

### 恢复方法（如果想恢复挖矿）
把所有 `.disabled` 后缀去掉，`/etc/inittab` 取消注释，`kill -HUP 1`，
再 `echo 1 > /sys/class/gpio/gpio404/value` 给 ASIC 上电，最后
`/etc/init.d/cgminer.sh start`。
**注意：恢复前务必确认风扇已装好**，否则会过热损坏。

## 浏览器部署（Dillo）

### 可行性结论
现代浏览器（Firefox/Chromium）在这块板上**不可行**：空闲就吃 500MB+，
而板子只有 481MB RAM、无 swap；强行跑必然 OOM。
**Dillo 3.0.5** 是务实选择：安装后 1MB、运行约 20MB、
真正的 X11/FLTK 图形浏览器，支持 HTTP/HTTPS、图片、CSS 子集。
代价：**不支持 JavaScript**（百度会自动跳到 `baidu.html?from=noscript` 无脚本版）。

### 装了什么
- `dillo_3.0.5-5_armhf` — 来自 Debian buster 归档源
  （`http://archive.debian.org/debian/pool/main/d/dillo/`）
- `libfltk1.3_1.3.4-9_armhf` — FLTK GUI 工具包
  （**注意别下 1.3.5**，它要求 libc ≥ 2.29，而 chroot 是 buster 的 libc 2.28）
- `wget_1.20.1-1.1_armhf` — Dillo 的推荐依赖
- `fonts-wqy-microhei_0.2.0-beta-3_all` — 中文显示

### 关键配置
1. **DNS**：chroot 原来没有 `/etc/resolv.conf`，从宿主复制过来；
   否则 Dillo 的 `dillo_dns_init` 起不来。
2. **中文字体**：Xvfb 默认只有 `built-ins`，且字体目录缺 `fonts.dir` 索引：
   ```sh
   mkfontdir /usr/share/fonts/X11/misc
   mkfontdir /usr/share/fonts/X11/75dpi
   xset +fp /usr/share/fonts/X11/misc
   xset +fp /usr/share/fonts/X11/75dpi
   xset fp rehash     # 字体从 6 个涨到 1000+，含 JIS X 0208 中文
   ```
   这些已固化进 `start_desktop.sh`（重启自动生效）。
3. **Dillo 字体配置**在 `/root/.dillo/dillorc`，注意配置项是
   `font_sans_serif`（**下划线**，不是连字符）。

### 联网实测
- 境外站点（example.com → Cloudflare IP）**超时** —— 国内网络连不上，与浏览器无关
- 国内站点 `http://www.baidu.com/` **正常**，整页加载（含 PNG 图片、CSS、跳转）
- 判定方法：`wget -O /tmp/t.html -T 10 http://...` 看 exit code，
  与浏览器表现一致就说明是网络层而非浏览器问题

### 入口
- 底部 dock 的浏览器图标（已改为 Dillo）
- 桌面 `Web Browser` 快捷方式
- 启动时自动打开百度（可通过 `start_desktop.sh` 改 URL）

## 工具脚本

| 文件 | 用途 |
|---|---|
| `/mnt/sd2/start_desktop.sh` | 一键启动整个桌面 + 视频 + 浏览器 |
| `/mnt/sd2/deploy.sh` | 全新部署 chroot（解包 + 配置 + 启动） |
| `/mnt/sd2/badapple` | 播放器包装（mpv 优先，回退 mplayer） |
| `/root/Desktop/BadApple.desktop` | 桌面快捷方式（全屏播放） |
| `/root/Desktop/Browser.desktop` | 浏览器快捷方式 |
| `/root/www/index.html` | 本地测试页（HTML/CSS 渲染验证） |

本机侧：`board_dump/debs/closure.py`（依赖闭包解析）、`board_dump/debs/fetch.py`（批量下载）、
`build_lean.py` / `closure.py`（精简包与闭包）、`xfer.ps1`（二进制流传输）、
`rfb_capture.py`（RFB 协议截图）。

## 性能

ZynqMP 4×A53 软件解码 480×360 H.264，mpv 进程稳定，负载 ~0.3–0.7。
VA-API/VDPAU 会报错（无 GPU），mpv 自动回退软件渲染，不影响播放。
内存：492 MB 总量，桌面 + 播放 + 浏览器后可用约 290 MB（Dillo 增量约 20 MB）。
