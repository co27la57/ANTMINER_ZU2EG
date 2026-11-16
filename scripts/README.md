# 通用工具脚本

| 文件 | 用途 |
|---|---|
| `xfer.ps1` | 二进制流传输（解决 PowerShell `1>` 重定向把二进制转 UTF-16LE 的问题） |
| `upload_run.ps1` | 上传并在板端执行脚本（pscp 必须用 `-scp` 模式，板子无 sftp-server） |
| `rfb_capture.py` | 纯标准库 RFB/VNC 客户端，用于无 GUI 环境下抓板子屏幕截图 |
| `stream_binary.ps1` / `stream_tar.sh` | 流式传输 rootfs（36 MB，不落盘中间文件） |
| `remote_probe.sh` / `probe3.sh` / `net_check.sh` | 板端环境探测 |

## 典型用法

```bash
# 从板子下载二进制文件（保持字节不变）
xfer.ps1 -LocalFile running.dtb -RemotePath /proc/device-tree/... -Mode download

# 抓 VNC 截图（板子 IP 为 172.25.81.151）
python rfb_capture.py 172.25.81.151 5900 screen.png
```

## 传输工具的设计要点

板子只有 BusyBox + dropbear（无 sftp-server），Windows 侧又有执行策略限制。
`xfer.ps1` 用 .NET `Process` + `StandardOutput.BaseStream.Read()` + latin1 编码，
绕开 PowerShell 管道对二进制的破坏，实测 36 MB rootfs 逐字节正确传输。
