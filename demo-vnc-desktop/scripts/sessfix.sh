#!/bin/sh
OUT=/tmp/sessfix.log
exec > "$OUT" 2>&1
ROOT=/mnt/sd2/debian

rm -f /dev/mmcblk0 /dev/mmcblk0p1 /dev/mmcblk0p2 2>/dev/null
grep -E 'mmcblk' /proc/partitions | while read MAJ MIN BLKS NAME; do
    mknod "/dev/$NAME" b "$MAJ" "$MIN" 2>/dev/null && chmod 660 "/dev/$NAME"
done
umount "$ROOT/proc" 2>/dev/null; umount "$ROOT/sys" 2>/dev/null
umount "$ROOT/dev/shm" 2>/dev/null; umount /mnt/sd2 2>/dev/null
sleep 1; mkdir -p /mnt/sd2
for dev in /dev/mmcblk0p1 /dev/mmcblk0p2 /dev/mmcblk0; do
    [ -b "$dev" ] || continue
    mount "$dev" /mnt/sd2 2>/dev/null
    grep -q "^$dev /mnt/sd2 " /proc/mounts 2>/dev/null && break
done
mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev/shm"
mount --bind /proc "$ROOT/proc" 2>/dev/null
mount --bind /sys  "$ROOT/sys" 2>/dev/null
C() { busybox chroot "$ROOT" /bin/sh -c "$1" 2>&1; }
C 'mount -t tmpfs -o size=48M tmpfs /dev/shm 2>/dev/null'

echo "########## 1. available panel plugins ##########"
C 'ls /usr/lib/*/xfce4/panel/plugins/*.so 2>/dev/null | xargs -n1 basename 2>/dev/null'
C 'ls /usr/lib/*/xfce4/panel/plugins/ 2>/dev/null | head -30'

echo
echo "########## 2. MIME database (idempotent) ##########"
C 'update-mime-database /usr/share/mime 2>&1 | head -5; echo exit=$?'
C 'ls -la /usr/share/mime/magic /usr/share/mime/mime.cache 2>&1'

echo
echo "########## 3. GTK2 theme (Adwaita is GTK3 -> switch to Xfce) ##########"
cat > "$ROOT/root/.gtkrc-2.0" <<'EOF'
gtk-theme-name="Xfce"
gtk-icon-theme-name="gnome"
gtk-font-name="Sans 10"
gtk-menu-images=true
gtk-button-images=true
gtk-toolbar-style=GTK_TOOLBAR_ICONS
EOF
C 'cat /root/.gtkrc-2.0'

echo
echo "########## 4. rebuild icon caches ##########"
C 'gtk-update-icon-cache -f -t /usr/share/icons/gnome 2>&1 | tail -2'
C 'gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>&1 | tail -2'
C 'ls -la /usr/share/icons/gnome/icon-theme.cache /usr/share/icons/hicolor/icon-theme.cache 2>&1'

echo
echo "########## 5. restart the xfce session so it picks up the new MIME DB ##########"
C 'pkill -9 -f xfdesktop; pkill -9 -f xfce4-panel; pkill -9 -f xfwm4; pkill -9 -f xfsettingsd'
sleep 3
C 'pkill -9 -f mpv; pkill -9 -f badapple'
sleep 2

ENVSTR="export DISPLAY=:1; export HOME=/root; export USER=root; export SHELL=/bin/bash; export XDG_RUNTIME_DIR=/tmp/xdg; export XDG_CONFIG_HOME=/root/.config; export XDG_CACHE_HOME=/root/.cache; export XDG_DATA_HOME=/root/.local/share; export XDG_DATA_DIRS=/usr/local/share:/usr/share; export XDG_CONFIG_DIRS=/etc/xdg; export XDG_SESSION_TYPE=x11; export DESKTOP_SESSION=xfce4; export GDK_BACKEND=x11; mkdir -p /tmp/xdg; chmod 700 /tmp/xdg;"

C "$ENVSTR xfsettingsd > /tmp/xfsettingsd.log 2>&1 &"
sleep 4
C "$ENVSTR xfdesktop --disable-wm-check > /tmp/xfdesktop.log 2>&1 &"
sleep 4
C "$ENVSTR xfwm4 --replace > /tmp/xfwm4.log 2>&1 &"
sleep 4
C "$ENVSTR xfce4-panel > /tmp/xfce4-panel.log 2>&1 &"
sleep 8
echo "--- panel log ---"
C 'tail -20 /tmp/xfce4-panel.log'
C 'cat /tmp/xfdesktop.log'

echo
echo "########## 6. restart the BadApple demo ##########"
C 'nohup /usr/local/bin/badapple > /tmp/badapple.log 2>&1 &'
sleep 4
C 'ps | grep -E "Xvfb|x11vnc|xfdesktop|xfwm4|xfce4-panel|xfsettingsd|mpv" | grep -v grep'

echo
echo "########## 7. final verification: decode works inside the session ##########"
C 'cd /tmp; gdk-pixbuf-csource /usr/share/icons/gnome/48x48/places/folder.png 2>&1 | head -1'

echo "########## END ##########"
