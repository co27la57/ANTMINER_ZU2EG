#!/bin/sh
OUT=/tmp/mimefix.log
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

echo "########## 1. install the mime database ##########"
C "ls -la $ROOT/usr/share/mime/packages/ 2>&1"
cp /tmp/sharedmime.tar /mnt/sd2/sharedmime.tar 2>/dev/null
echo "--- extracting into chroot ---"
C "cd /; tar xf /mnt/sd2/sharedmime.tar 2>&1 | head -5; echo tar-exit=\$?"
C "ls -la /usr/share/mime/packages/ 2>&1"
C "ls -la /usr/share/mime/packages/freedesktop.org.xml 2>&1"

echo
echo "########## 2. does GIO now guess image/png ? ##########"
C "python3 -u /tmp/gt.py"

echo
echo "########## 3. gdk-pixbuf decode test ##########"
C "cd /tmp; rm -f /tmp/o.c /tmp/o.err; gdk-pixbuf-csource /usr/share/icons/gnome/48x48/places/folder.png >/tmp/o.c 2>/tmp/o.err; if [ -s /tmp/o.c ]; then echo '*** PNG DECODE OK ***'; head -2 /tmp/o.c; else echo 'PNG DECODE FAIL'; cat /tmp/o.err; fi"
C "cd /tmp; rm -f /tmp/o2.c /tmp/o2.err; gdk-pixbuf-csource /usr/share/backgrounds/xfce/xfce-teal.jpg >/tmp/o2.c 2>/tmp/o2.err; if [ -s /tmp/o2.c ]; then echo '*** JPEG DECODE OK ***'; else echo 'JPEG DECODE FAIL'; cat /tmp/o2.err; fi"

echo
echo "########## 4. thumbnailer test ##########"
C "gdk-pixbuf-thumbnailer -s 48 /usr/share/icons/gnome/48x48/places/folder.png /tmp/t.png 2>&1; ls -la /tmp/t.png 2>&1"

echo
echo "########## 5. gdk_pixbuf_get_formats + new_from_file ##########"
C "python3 -u /tmp/real2.py 2>&1 | head -8"

echo "########## END ##########"
