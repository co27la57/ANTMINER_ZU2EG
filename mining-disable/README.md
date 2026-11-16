# 关闭挖矿程序 — 完整记录

这个目录包含关闭 Antminer E7 控制板上原厂挖矿程序的**完整排查过程**：脚本、原始日志、验证结果。

## 快速开始

如果只想关掉挖矿，按顺序执行：

```sh
sh /tmp/stopminer.sh      # 第一轮：杀 watchdog + cgminer，禁用启动脚本，断 ASIC 电源
sh /tmp/stopminer2.sh     # 第二轮：处理 inittab respawn（发现 monitorcg 会复活）
sh /tmp/stopminer3.sh     # 第三轮：注释 inittab + kill -HUP 1，最终验证
sh /tmp/verifyboot.sh     # 验证所有自启动项已禁用
```

> 这些脚本是为**实板交互调试**设计的，会重新挂载 SD 卡。请在实际环境中根据注释调整路径。
> 三个脚本是递进关系 —— 完整故事见下面的日志。

## 文件说明

| 文件 | 用途 |
|---|---|
| `miningcheck.sh` | 初始排查：列全部进程、按 CPU 时间排序、查温度节点、查矿池连接 |
| `mining.log` | ↑ 的原始输出 —— **在这里第一次发现 cgminer / monitorcg / GPIO 设备** |
| `cgstatus.sh` / `cg2.sh` / `cg3.sh` | 深入探测：cgminer API、配置、看门狗脚本、进程状态 |
| `cg2.log` / `cg3.log` | ↑ 的原始输出 —— **发现 inittab respawn 是关键** |
| `stopminer.sh` | 第一轮停止（杀进程 + 断 GPIO），但 monitorcg 复活了 |
| `stopminer2.sh` | 第二轮（循环杀 + 改名脚本），仍被 respawn |
| `stopminer3.sh` | 第三轮（**注释 inittab + kill -HUP 1**）→ 彻底干净 |
| `verifyboot.sh` | 最终验证：所有自启动项、GPIO、进程状态 |
| `*.log` | 每轮的实际输出，保留作为证据 |

## 时间线（从日志提炼）

1. **发现**：进程列表里有 `cgminer` (PID 1903)、`SCREEN -S cgminer` (1902)、`monitorcg` (1918)
2. **误判**：以为只是普通进程，直接 kill → 20 秒后 `monitorcg` 把它拉回来
3. **深入**：`/sbin/monitorcg` 内容只有 12 行 —— 死循环每 20 秒检查 cgminer 是否存在
4. **再误判**： kill monitorcg → 又被 init 拉起（新 PID 4892）
5. **根因**：`/etc/inittab` 第 44 行 `dcdc:2345:respawn:/sbin/monitorcg` —— BusyBox init 的 respawn 指令
6. **解决**：注释该行 + `kill -HUP 1` 重载 + 禁用所有 rc 链接 + GPIO 断电
7. **验证**：等待 30 秒（超过 respawn 周期）无进程复活，loadavg 0.13，桌面栈完好

## 重要提醒

- **顺序不能乱**：必须先 watchdog，再 cgminer，否则白杀
- **inittab 必须改**：只杀进程永远杀不完
- **改名前先备份**：所有文件用 `.disabled` / `.bak` 后缀，完全可逆
- **恢复前装风扇**：原板 `/tmp/fanstatus` 显示 0 个风扇。ASIC 通电但无散热会损坏芯片
