#!/bin/sh
OUT=/tmp/mimegen.log
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

echo "########## 1. stage update-mime-database into the chroot ##########"
rm -rf /tmp/mimesrc; mkdir -p /tmp/mimesrc
tar xf /tmp/sharedmime.tar -C /tmp/mimesrc 2>&1 | head -3
ls -la /tmp/mimesrc/usr/bin/ 2>&1
echo "--- what kind of file is it? ---"
head -c 60 /tmp/mimesrc/usr/bin/update-mime-database | od -c 2>/dev/null | head -3
cp -f /tmp/mimesrc/usr/bin/update-mime-database "$ROOT/usr/bin/update-mime-database" 2>&1
chmod 755 "$ROOT/usr/bin/update-mime-database"
C "ls -la /usr/bin/update-mime-database"
echo "--- make sure the XML is in place ---"
C "ls -la /usr/share/mime/packages/freedesktop.org.xml"
cp -f /tmp/mimesrc/usr/share/mime/packages/freedesktop.org.xml "$ROOT/usr/share/mime/packages/freedesktop.org.xml" 2>/dev/null
C "ls -la /usr/share/mime/packages/"

echo
echo "########## 2. RUN update-mime-database ##########"
C "update-mime-database /usr/share/mime 2>&1 | head -20; echo exit=\$?"
echo "--- what got created? ---"
C "ls -la /usr/share/mime/"

echo
echo "########## 3. does GIO guess image/png now? ##########"
C "python3 -u /tmp/gt.py"

echo
echo "########## 4. gdk-pixbuf decode test ##########"
C "cd /tmp; rm -f /tmp/o.c /tmp/o.err; gdk-pixbuf-csource /usr/share/icons/gnome/48x48/places/folder.png >/tmp/o.c 2>/tmp/o.err; if [ -s /tmp/o.c ]; then echo '*** PNG DECODE OK ***'; head -2 /tmp/o.c; else echo 'PNG DECODE FAIL'; cat /tmp/o.err; fi"
C "cd /tmp; rm -f /tmp/o2.c /tmp/o2.err; gdk-pixbuf-csource /usr/share/backgrounds/xfce/xfce-teal.jpg >/tmp/o2.c 2>/tmp/o2.err; if [ -s /tmp/o2.c ]; then echo '*** JPEG DECODE OK ***'; else echo 'JPEG DECODE FAIL'; cat /tmp/o2.err; fi"

echo
echo "########## 5. thumbnailer ##########"
C "gdk-pixbuf-thumbnailer -s 48 /usr/share/icons/gnome/48x48/places/folder.png /tmp/t.png 2>&1; ls -la /tmp/t.png 2>&1"

echo "########## END ##########"
