# 演示例程：VNC 虚拟桌面 + Bad Apple!!

一个可复现的演示例程：在这块没有显示输出的矿板上，用 Xvfb 造一个虚拟屏幕，
通过 VNC 暴露出来，运行 xfce4 桌面、播放 Bad Apple!! 动画、打开浏览器。

## 目录

```
scripts/start_desktop.sh   一键启动（放到板子 /mnt/sd2/start_desktop.sh）
scripts/badapple.sh        视频播放包装（--window 窗口模式 / 默认全屏）
deps/                     浏览器、中文字体、MIME 数据库 tar 包 + 官方 md5 清单
screenshots/              各阶段 VNC 截图
testpage.html             本地测试页
```

## 运行

```sh
# 板子上
sh /mnt/sd2/start_desktop.sh

# 本机：用任意 VNC 客户端连接 <板子IP>:5900（无密码）
```

详见 [`../docs/VNC桌面与BadApple-完整技术文档.md`](../docs/VNC桌面与BadApple-完整技术文档.md)
和根目录 [`../README.md`](../README.md)。

## 视频素材

Bad Apple!! mp4 未随仓库分发。获取：

```
https://cdn.jsdelivr.net/gh/aloyak/badapple@master/video/badapple.mp4
```

保存到 `/root/videos/badapple.mp4`（7.3 MB，H.264 480×360）。
