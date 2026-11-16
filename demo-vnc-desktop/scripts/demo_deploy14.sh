#!/bin/sh
# Install OpenCV libs, rebuild the linker cache, launch Bad Apple!!.
OUT=/mnt/sd2/demo.log
exec > "$OUT" 2>&1

ROOT=/mnt/sd2/debian
DISP=:1

rm -f /dev/mmcblk0 /dev/mmcblk0p1 /dev/mmcblk0p2 2>/dev/null
grep -E 'mmcblk' /proc/partitions | while read MAJ MIN BLKS NAME; do
    mknod "/dev/$NAME" b "$MAJ" "$MIN" 2>/dev/null && chmod 660 "/dev/$NAME"
done
umount /mnt/sd2/debian/proc 2>/dev/null
umount /mnt/sd2/debian/sys 2>/dev/null
umount /mnt/sd2/debian/dev/pts 2>/dev/null
umount /mnt/sd2/debian/dev/shm 2>/dev/null
umount /mnt/sd2 2>/dev/null
sleep 1
mkdir -p /mnt/sd2
for dev in /dev/mmcblk0p1 /dev/mmcblk0p2 /dev/mmcblk0; do
    [ -b "$dev" ] || continue
    mount "$dev" /mnt/sd2 2>/dev/null
    grep -q "^$dev /mnt/sd2 " /proc/mounts 2>/dev/null && break
done
mkdir -p "$ROOT/proc" "$ROOT/sys"
mount --bind /proc "$ROOT/proc" 2>/dev/null
mount --bind /sys  "$ROOT/sys" 2>/dev/null
C() { busybox chroot "$ROOT" /bin/sh -c "$1" 2>&1; }

echo "############ demo deploy v14: $(date) ############"

echo "=== install mp17 (opencv) ==="
mkdir -p /mnt/sd2/w17
cd /mnt/sd2/w17 && tar xf /mnt/sd2/mp17.tar 2>/dev/null
n=0; okc=0
for f in /mnt/sd2/w17/*.tar; do
    [ -e "$f" ] || continue
    n=$((n+1))
    cd "$ROOT" && tar xf "$f" 2>/dev/null && okc=$((okc+1))
done
echo "  unpacked $n ok=$okc"
rm -rf /mnt/sd2/w17

echo "=== rebuild linker cache ==="
C "/sbin/ldconfig 2>&1 | tail -3"
C "ls -la /etc/ld.so.cache"

echo "=== player status ==="
echo "-- mpv --";     C "mpv --version 2>&1 | sed -n '1,1p'"
echo "-- mplayer --"; C "mplayer -h 2>&1 | sed -n '1,1p'"
echo "-- ffmpeg --";  C "ffmpeg -version 2>&1 | sed -n '1,1p'"

echo "=== ffmpeg decode test ==="
C "ffmpeg -i /root/videos/badapple.mp4 2>&1 | grep -E 'Duration|Stream'"

echo "=== LAUNCH ==="
C 'killall mplayer mpv 2>/dev/null'
sleep 2
C "nohup /usr/local/bin/badapple > /tmp/badapple.log 2>&1 &"
sleep 30
echo "  log:"
C "cat /tmp/badapple.log 2>/dev/null | tail -14"
echo "  processes:"
C "ps | grep -E 'mplayer|mpv'"
echo "=== windows on :1 ==="
C "DISPLAY=:1 xwininfo -root -children 2>&1 | grep -vE '10x10|1x1' | sed -n '1,18p'"
echo "=== load ==="
cat /proc/loadavg
echo "############ demo deploy v14 done ############"
