#!/bin/sh
OUT=/tmp/final.log
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

echo "########## 1. kill the stale panel from the host side ##########"
for p in $(C 'pidof xfce4-panel'); do kill -9 $p 2>/dev/null; done
sleep 2
C 'pidof xfce4-panel || echo "  none left"'

echo
echo "########## 2. GTK2 rc file (GTK2 wants TRUE/FALSE, not true/false) ##########"
cat > "$ROOT/root/.gtkrc-2.0" <<'EOF'
gtk-theme-name="Xfce"
gtk-icon-theme-name="gnome"
gtk-font-name="Sans 10"
gtk-menu-images=TRUE
gtk-button-images=TRUE
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-enable-animations=FALSE
EOF
C 'cat /root/.gtkrc-2.0'

echo
echo "########## 3. panel config: top panel + bottom icon dock ##########"
C 'mkdir -p /root/.config/xfce4/xfce4-panel'

cat > "$ROOT/root/.config/xfce4/xfce4-panel/panel-1.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<panel name="panel-1">
  <position>1</position>
  <length>100</length>
  <position-offset>0</position-offset>
  <size>30</size>
  <expand>1</expand>
  <border>0</border>
  <plugin>
    <id>applicationsmenu</id>
    <property name="icon-size" type="int" value="0"/>
    <property name="menu-style" type="int" value="0"/>
  </plugin>
  <plugin>
    <id>separator</id>
    <property name="size" type="int" value="0"/>
    <property name="expand" type="bool" value="false"/>
  </plugin>
  <plugin>
    <id>tasklist</id>
    <property name="show-icons" type="bool" value="true"/>
    <property name="show-handles" type="bool" value="false"/>
    <property name="show-tooltips" type="bool" value="true"/>
    <property name="max-size" type="int" value="0"/>
    <property name="icon-size" type="int" value="0"/>
    <property name="show-apps-icons" type="bool" value="true"/>
    <property name="show-other-workspaces" type="bool" value="false"/>
    <property name="show-window-icons" type="bool" value="true"/>
    <property name="show-window-sticky" type="bool" value="true"/>
    <property name="show-window-minimized" type="bool" value="true"/>
    <property name="show-window-desk" type="bool" value="true"/>
    <property name="show-window-manual-placement" type="bool" value="true"/>
    <property name="show-window-zoomed" type="bool" value="true"/>
    <property name="window-list" type="int" value="1"/>
  </plugin>
  <plugin>
    <id>separator</id>
    <property name="size" type="int" value="0"/>
    <property name="expand" type="bool" value="true"/>
  </plugin>
  <plugin>
    <id>pager</id>
    <property name="workspace-count" type="int" value="1"/>
    <property name="show-all-workspaces" type="bool" value="false"/>
    <property name="show-miniature-view" type="bool" value="false"/>
    <property name="rows" type="int" value="1"/>
  </plugin>
  <plugin>
    <id>systray</id>
    <property name="icon-size" type="int" value="0"/>
  </plugin>
  <plugin>
    <id>clock</id>
    <property name="time-format" type="string" value="%H:%M"/>
    <property name="date-format" type="string" value="%Y-%m-%d"/>
    <property name="show-seconds" type="bool" value="false"/>
    <property name="show-date" type="bool" value="true"/>
    <property name="show-weekday" type="bool" value="true"/>
    <property name="show-month" type="bool" value="true"/>
    <property name="show-year" type="bool" value="true"/>
    <property name="show-tooltips" type="bool" value="true"/>
    <property name="tooltip-format" type="string" value="%c"/>
    <property name="font" type="string" value="Sans 10"/>
    <property name="font-color" type="string" value="#000000"/>
    <property name="font-enabled" type="bool" value="true"/>
    <property name="fancy" type="bool" value="false"/>
    <property name="icon-size" type="int" value="0"/>
  </plugin>
</panel>
EOF

cat > "$ROOT/root/.config/xfce4/xfce4-panel/panel-2.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<panel name="panel-2">
  <position>0</position>
  <length>100</length>
  <position-offset>0</position-offset>
  <size>56</size>
  <expand>0</expand>
  <border>0</border>
  <plugin>
    <id>separator</id>
    <property name="size" type="int" value="0"/>
    <property name="expand" type="bool" value="false"/>
  </plugin>
  <plugin>
    <id>launcher</id>
    <property name="items" type="array">
      <value type="string" value="/usr/share/applications/xfce4-appfinder.desktop"/>
      <value type="string" value="/usr/share/applications/xfce4-terminal.desktop"/>
      <value type="string" value="/usr/share/applications/Thunar.desktop"/>
      <value type="string" value="/usr/share/applications/exo-web-browser.desktop"/>
      <value type="string" value="/usr/share/applications/mpv.desktop"/>
    </property>
    <property name="icon-size" type="int" value="40"/>
    <property name="force-icon-size" type="bool" value="true"/>
  </plugin>
  <plugin>
    <id>separator</id>
    <property name="size" type="int" value="0"/>
    <property name="expand" type="bool" value="true"/>
  </plugin>
  <plugin>
    <id>showdesktop</id>
    <property name="show-icons" type="bool" value="true"/>
    <property name="icon-size" type="int" value="16"/>
  </plugin>
  <plugin>
    <id>separator</id>
    <property name="size" type="int" value="0"/>
    <property name="expand" type="bool" value="false"/>
  </plugin>
</panel>
EOF
C 'ls -la /root/.config/xfce4/xfce4-panel/'

echo
echo "########## 4. restart the whole xfce session ##########"
C 'killall -9 xfdesktop 2>/dev/null; killall -9 xfwm4 2>/dev/null; killall -9 xfsettingsd 2>/dev/null; killall -9 xfce4-panel 2>/dev/null'
sleep 3
ENVSTR="export DISPLAY=:1; export HOME=/root; export USER=root; export SHELL=/bin/bash; export XDG_RUNTIME_DIR=/tmp/xdg; export XDG_CONFIG_HOME=/root/.config; export XDG_CACHE_HOME=/root/.cache; export XDG_DATA_HOME=/root/.local/share; export XDG_DATA_DIRS=/usr/local/share:/usr/share; export XDG_CONFIG_DIRS=/etc/xdg; export XDG_SESSION_TYPE=x11; export DESKTOP_SESSION=xfce4; export GDK_BACKEND=x11; mkdir -p /tmp/xdg; chmod 700 /tmp/xdg;"
C "$ENVSTR xfsettingsd > /tmp/xfsettingsd.log 2>&1 &"
sleep 4
C "$ENVSTR xfdesktop --disable-wm-check > /tmp/xfdesktop.log 2>&1 &"
sleep 4
C "$ENVSTR xfwm4 --replace > /tmp/xfwm4.log 2>&1 &"
sleep 4
C "$ENVSTR xfce4-panel > /tmp/xfce4-panel.log 2>&1 &"
sleep 10
echo "--- panel log ---"
C 'tail -12 /tmp/xfce4-panel.log'
echo "--- processes ---"
C 'ps | grep -E "Xvfb|x11vnc|xfdesktop|xfwm4|xfce4-panel|xfsettingsd|mpv" | grep -v grep'
echo "--- did the panel rewrite the config? (proves it parsed our XML) ---"
C 'ls -la /root/.config/xfce4/xfce4-panel/'

echo
echo "########## 5. restart the demo video ##########"
C 'killall -9 mpv 2>/dev/null; sleep 2'
C 'nohup /usr/local/bin/badapple --window > /tmp/badapple.log 2>&1 &'
sleep 5
C 'ps | grep mpv | grep -v grep'

echo
echo "########## 6. verify image decoding in the session env ##########"
C 'cd /tmp; gdk-pixbuf-csource /usr/share/icons/gnome/48x48/places/folder.png 2>&1 | head -1'

echo "########## END ##########"
