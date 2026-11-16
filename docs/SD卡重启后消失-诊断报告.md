# 重启后 `/mnt/sd2` 消失 — 诊断报告

## 日期

2026-11-17

## 现象

板子重启后，`/mnt/sd2` 路径"不见了"（实际是目录在、空的、没挂载），
VNC 桌面也不再运行。

## 诊断结果（两个独立问题）

### 问题 A：`/mnt/sd2` 未挂载 —— 设计如此，不是故障

**证据**：

```
/proc/partitions:
  179 0 7864320  mmcblk0       ← SD 卡被正确识别（7.5 GB）
  179 1 7863296  mmcblk0p1     ← 分区表正常
/dev/mmcblk0*                  ← 设备节点存在
/mnt/sd2/                      ← 目录存在，但为空
/proc/mounts                   ← 无任何 mmc 挂载
```

**根因**：系统从来**没有配置开机自动挂载** `/mnt/sd2`。
原厂 fstab 只有：

```
/dev/mmcblk0p3  /config  auto  defaults,sync  0 0
```

（而且 `mmcblk0p3` 在重新格式化后已不存在，`/config` 实际挂的是 `/dev/mtdblock7`）
之前每次挂载都是我手动执行 `mount /dev/mmcblk0p1 /mnt/sd2`，重启自然丢失。

### 问题 B（严重）：SD 卡 I/O 卡死 + 挖矿程序死灰复燃

**B1. SD 卡硬件层 I/O 超时**

内核日志：

```
[314.644126] mmc0: Timeout waiting for hardware interrupt.
[314.649448] sdhci: =========== REGISTER DUMP (mmc0)===========
```

尝试访问卡时，4 个进程卡在 **D 状态（不可中断睡眠）**，连 SIGKILL 都无效：

```
PID 2425  mount /dev/mmcblk0p1 /mnt/sd2   → __wait_on_buffer
PID 3015  dd if=/dev/mmcblk0p1 ...         → __lock_buffer
PID 3927  mount /dev/mmcblk0p1 /mnt/sd2   → grab_super
PID 4957  dd if=/dev/mmcblk0p1 ...         → wait_on_page_bit_killable
```

`kill -9` 后仍在（PID 4957 后来自己退出了）。这是**块设备层**的问题，
不是文件系统或 mount 参数问题。

**B2. 上次关闭的挖矿程序全部复活**

```
inittab 第44行:  dcdc:2345:respawn:/sbin/monitorcg    ← 又变回未注释
/etc/init.d/cgminer.sh                                ← .disabled 后缀消失
/sbin/monitorcg                                       ← .disabled 后缀消失
进程: cgminer(1899) + monitorcg(1914) + SCREEN(1898)  ← 全部在跑
```

**根因（已用时间戳证实）**：

```
stat /etc/inittab → Modify: 2026-11-16 18:18:11
```

这个时间戳远早于我上次修改 inittab 的时间（约 23:00）。说明**写入根本没有落到持久存储**。

虽然 `/proc/mounts` 显示 `/dev/root / ext4 rw,...`，但这是**内存层/overlay 的假象**。
原厂固件把根文件系统设计成**非持久**的（底层 mtdblock 映射，写入掉电丢失），
只有 `/config`（JFFS2，`/dev/mtdblock7`）是真正持久的 —— 这也正是
`bitmainer_setup.sh` 只从 `/config` 恢复 dropbear/shadow/cgminer.conf 的原因。

所以上次改的 `/etc/inittab`、`/etc/rcS.d/*`、`/sbin/monitorcg` 全部在重启后还原。
**结论：任何对 `/etc` 的修改都不持久，必须用 `/config` 或 SD 卡上的脚本。**

## 解决方案

### 恢复 `/mnt/sd2`

**首选**：重新拔插 SD 卡（能清掉硬件超时状态），然后：

```sh
mkdir -p /mnt/sd2
mount /dev/mmcblk0p1 /mnt/sd2
```

如果仍卡死 → 需要断电重启（D 状态进程无法 kill，只能重启）。

**永久方案**（让开机自动挂载）：在 `/etc/fstab` 加一行：

```
/dev/mmcblk0p1  /mnt/sd2  ext4  defaults,noauto  0  0
```

但注意 `/etc/fstab` 也可能被固件恢复机制覆盖 —— 更稳妥的做法是把挂载命令
放进 `start_desktop.sh`（该脚本在 SD 卡上，不受覆盖影响），它已经包含完整的
设备节点重建 + 挂载逻辑。

### 彻底关闭挖矿（持久化）

**关键认知：`/etc` 的修改不持久，只有 `/config`（JFFS2）和 SD 卡是持久的。**

已实施：把关闭挖矿的逻辑加到 `/mnt/sd2/start_desktop.sh` 开头（SD 卡上，重启不丢）。
每次运行桌面脚本时自动杀 cgminer / monitorcg 并断 ASIC 电源（GPIO403/404）。

其他可选方案：

1. **改 `/config/cgminer.conf`**（JFFS2 持久）— 把矿池地址改成无效地址或清空 pools。
   cgminer 进程仍在但不会连接矿池、不会驱动 ASIC 工作。
2. **物理方式**：不装风扇时不要给 ASIC 上电（GPIO404）。
3. **每次开机后手动执行** `mining-disable/` 里的停止脚本。

## 已执行 / 待办

- [x] 确认根因：`/etc` 不持久（inittab mtime 证明）
- [x] 把关挖矿逻辑整合进 `start_desktop.sh`（持久）
- [ ] **需要用户操作**：重新拔插 SD 卡或断电重启，清除 `mmc0` 硬件 I/O 超时
      （D 状态进程无法 kill，只能重启）
- [ ] 重启后执行 `sh /mnt/sd2/start_desktop.sh`，它会：
      自动挂载 SD 卡 → 关挖矿 → 拉起桌面
- [ ] 如拔插后仍报 I/O 错误，考虑在另一台机器上 fsck SD 卡
