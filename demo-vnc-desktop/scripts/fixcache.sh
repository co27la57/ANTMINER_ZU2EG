#!/bin/sh
OUT=/tmp/fixcache.log
exec > "$OUT" 2>&1
ROOT=/mnt/sd2/debian

rm -f /dev/mmcblk0 /dev/mmcblk0p1 /dev/mmcblk0p2 2>/dev/null
grep -E 'mmcblk' /proc/partitions | while read MAJ MIN BLKS NAME; do
    mknod "/dev/$NAME" b "$MAJ" "$MIN" 2>/dev/null && chmod 660 "/dev/$NAME"
done
umount /mnt/sd2/debian/proc 2>/dev/null
umount /mnt/sd2/debian/sys 2>/dev/null
umount /mnt/sd2/debian/dev/shm 2>/dev/null
umount /mnt/sd2 2>/dev/null
sleep 1
mkdir -p /mnt/sd2
for dev in /dev/mmcblk0p1 /dev/mmcblk0p2 /dev/mmcblk0; do
    [ -b "$dev" ] || continue
    mount "$dev" /mnt/sd2 2>/dev/null
    grep -q "^$dev /mnt/sd2 " /proc/mounts 2>/dev/null && break
done
mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev/shm"
mount --bind /proc "$ROOT/proc" 2>/dev/null
mount --bind /sys  "$ROOT/sys" 2>/dev/null
C() { busybox chroot "$ROOT" /bin/sh -c "$1" 2>&1; }
C 'mount -t tmpfs -o size=32M tmpfs /dev/shm 2>/dev/null'

L36=/usr/lib/arm-linux-gnueabihf/gdk-pixbuf-2.0/2.10.0
LD=$L36/loaders

echo "########## A. generate a fresh loaders.cache ##########"
C "gdk-pixbuf-query-loaders > /tmp/loaders.cache.new 2>/tmp/ql.err; echo exit=\$?; wc -c < /tmp/loaders.cache.new; echo '--- stderr ---'; cat /tmp/ql.err"
echo
echo "--- how many loaders got discovered ---"
C "grep -c '^\"' /tmp/loaders.cache.new"
echo
echo "--- the png block ---"
C "grep -A6 'libpixbufloader-png.so' /tmp/loaders.cache.new"

echo
echo "########## B. install it into BOTH plausible locations ##########"
C "cp -f /tmp/loaders.cache.new $L36/loaders.cache; echo cp1=\$?"
C "cp -f /tmp/loaders.cache.new $LD/loaders.cache;   echo cp2=\$?"
C "ls -la $L36/loaders.cache $LD/loaders.cache"

echo
echo "########## C. decode test ##########"
C "cd /tmp; rm -f /tmp/o.c /tmp/o.err; gdk-pixbuf-csource /usr/share/icons/gnome/48x48/places/folder.png >/tmp/o.c 2>/tmp/o.err; if [ -s /tmp/o.c ]; then echo 'PNG DECODE OK'; head -2 /tmp/o.c; else echo 'PNG DECODE FAIL'; cat /tmp/o.err; fi"
echo "--- jpeg test ---"
C "cd /tmp; rm -f /tmp/o2.c /tmp/o2.err; gdk-pixbuf-csource /usr/share/icons/gnome/48x48/places/user-home.png >/tmp/o2.c 2>/tmp/o2.err; if [ -s /tmp/o2.c ]; then echo 'OK2'; else echo 'FAIL2'; cat /tmp/o2.err; fi"

echo
echo "########## D. icon themes present? ##########"
C "ls /usr/share/icons/ 2>/dev/null"
echo "--- gnome theme sample ---"
C "ls /usr/share/icons/gnome/48x48/places/ 2>/dev/null | head -8"
echo "--- hicolor index? ---"
C "ls /usr/share/icons/hicolor/ 2>/dev/null | head -20"
C "ls /usr/share/icons/hicolor/index.theme 2>/dev/null && echo 'index.theme OK'"

echo
echo "########## E. GTK2 settings ##########"
C "ls -la /root/.gtkrc-2.0 /root/.config/gtk-2.0 2>/dev/null"
C "cat /root/.gtkrc-2.0 2>/dev/null"
echo "--- available GTK2 themes ---"
C "ls /usr/share/themes/ 2>/dev/null"

echo
echo "########## F. which pixbuf does GTK2 actually use? ##########"
C "ls -la /usr/lib/arm-linux-gnueabihf/libgdk_pixbuf-2.0.so* /usr/lib/arm-linux-gnueabihf/libgdk_pixbuf_x11-2.0.so* 2>/dev/null"
C "dpkg -l 2>/dev/null | grep -E 'gdk-pixbuf|libgtk2.0|gtk-update' | head -20"

echo "########## END ##########"
