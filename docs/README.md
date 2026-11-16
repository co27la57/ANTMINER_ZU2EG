# 技术文档

| 文件 | 内容 |
|---|---|
| `VNC桌面与BadApple-完整技术文档.md` | 从零在矿板上搭 Debian chroot + Xvfb + xfce4 + VNC + mpv 的完整记录，含 10 个已定位并修复的坑 |

这份文档是最长、最详细的一份第一手资料，包括：

- chroot 构建、依赖闭包解析、二进制流传输的实现
- 图标红叉问题的**六轮排查**（最终定位到 shared-mime-info postinst 未执行）
- 面板/dock 恢复、GTK2 主题、mpv 失焦暂停
- 浏览器（Dillo）部署与中文字体配置
- 挖矿进程排查与关闭
