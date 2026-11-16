#!/bin/sh
# After the SD card was re-formatted the layout is:
#   /dev/mmcblk0p1  -> the whole 7.5 GB ext4 filesystem
# The old /dev/mmcblk0p2 mount entry is stale (that device no longer exists)
# and makes "mount" report "Device or resource busy".
#
# Fix the mounts, restore a consistent buster (2.38.1) gdk-pixbuf stack and
# regenerate the loader cache.
OUT=/mnt/sd2/deploy2.log
exec > "$OUT" 2>&1

ROOT=/mnt/sd2/debian
LD=/usr/lib/arm-linux-gnueabihf/gdk-pixbuf-2.0
A=/usr/lib/arm-linux-gnueabihf

echo "==================== deploy2: $(date) ===================="

# --- rebuild the block device nodes ---
rm -f /dev/mmcblk0 /dev/mmcblk0p1 /dev/mmcblk0p2 2>/dev/null
grep -E 'mmcblk' /proc/partitions | while read MAJ MIN BLKS NAME; do
    mknod "/dev/$NAME" b "$MAJ" "$MIN" 2>/dev/null && chmod 660 "/dev/$NAME"
done
ls -la /dev/mmcblk* 2>&1

# --- drop the stale mount and mount the real partition ---
umount /mnt/sd2/debian/proc 2>/dev/null
umount /mnt/sd2/debian/sys 2>/dev/null
umount /mnt/sd2/debian/dev/pts 2>/dev/null
umount /mnt/sd2/debian/dev/shm 2>/dev/null
umount /mnt/sd2 2>/dev/null
umount /mnt/sd 2>/dev/null
sleep 1
mkdir -p /mnt/sd2
for dev in /dev/mmcblk0p1 /dev/mmcblk0p2 /dev/mmcblk0; do
    [ -b "$dev" ] || continue
    if mount "$dev" /mnt/sd2 2>/dev/null; then
        echo "  mounted $dev"
        break
    fi
done
mount | grep mmc
df -h /mnt/sd2 | tail -1

# --- the chroot must still be there ---
if [ ! -d "$ROOT/usr/bin" ]; then
    echo "FATAL: the chroot is gone from the card - it needs to be redeployed"
    exit 1
fi
echo "  chroot present"

mkdir -p "$ROOT/proc" "$ROOT/sys" "$ROOT/dev/shm"
mount --bind /proc "$ROOT/proc"
mount --bind /sys  "$ROOT/sys"
C() { busybox chroot "$ROOT" /bin/sh -c "$1" 2>&1; }
C 'mount -t tmpfs -o size=32M tmpfs /dev/shm 2>/dev/null'

# --- restore a consistent buster 2.38.1 gdk-pixbuf stack ---
echo "--- clean out every gdk-pixbuf artefact ---"
rm -f "$ROOT$A"/libgdk_pixbuf*.so.0*
rm -f "$ROOT$A"/libgdk_pixbuf_xlib*.so.0*
rm -rf "$ROOT$LD/2.10.0/loaders" "$ROOT$LD/2.10.0/loaders.cache"
rm -f "$ROOT/usr/bin/gdk-pixbuf-query-loaders" "$ROOT/usr/bin/gdk-pixbuf-csource" "$ROOT/usr/bin/gdk-pixbuf-pixdata"

echo "--- install the buster (2.38.1) stack ---"
if [ -f /mnt/sd2/gdkbuster.tar ]; then
    mkdir -p /mnt/sd2/wgdkb && cd /mnt/sd2/wgdkb && tar xf /mnt/sd2/gdkbuster.tar 2>/dev/null
    for f in /mnt/sd2/wgdkb/*.tar; do
        cd "$ROOT" && tar xf "$f" 2>/dev/null && echo "  unpacked $(basename $f)"
    done
    rm -rf /mnt/sd2/wgdkb
else
    echo "  gdkbuster.tar not on the card"
fi

C "ls -la $A/libgdk_pixbuf-2.0.so.0* $A/libgdk_pixbuf_xlib-2.0.so.0*"
C "ls -la $LD/2.10.0/loaders/libpixbufloader-png.so"
C "ls -la /usr/bin/gdk-pixbuf-query-loaders"

echo "--- rebuild the linker cache ---"
C "/sbin/ldconfig 2>&1 | tail -2"

echo "--- generate the cache with the matching tool ---"
C "cd $LD && ./gdk-pixbuf-query-loaders > $LD/2.10.0/loaders.cache 2>/tmp/q.err"
C 'cat /tmp/q.err' 2>/dev/null | sed -n '1,6p'
C "head -12 $LD/2.10.0/loaders.cache"

echo "--- fill the extension lists ---"
cat > "$ROOT/tmp/mkcache.py" <<'PYEOF'
import re
LD='/usr/lib/arm-linux-gnueabihf/gdk-pixbuf-2.0'
EXT={'ani':['ani'],'bmp':['bmp','dib'],'gif':['gif'],'icns':['icns'],
     'ico':['ico','cur'],'jpeg':['jpeg','jpg','jpe'],'png':['png'],
     'pnm':['pnm','pbm','pgm','ppm'],'qtif':['qtif'],'tga':['tga','tpic'],
     'tiff':['tif','tiff'],'xbm':['xbm'],'xpm':['xpm'],'svg':['svg','svgz']}
path=LD+'/2.10.0/loaders.cache'
out=[];cur=None;first=True
for line in open(path,encoding='utf-8',errors='replace'):
    line=line.rstrip('\n')
    m=re.search(r'libpixbufloader-([a-z0-9]+)\.so',line)
    if m:
        cur,first=m.group(1),True; out.append(line); continue
    mm=re.match(r'^"([^"]*)"\s+""$',line)
    if mm and cur in EXT and first:
        out.append('"%s" "%s"'%(mm.group(1),' '.join(EXT[cur]))); first=False; continue
    out.append(line)
open(path,'w',encoding='utf-8').write('\n'.join(out)+'\n')
print('patched')
PYEOF
C "python3 /tmp/mkcache.py"
C "grep -A4 'libpixbufloader-png.so' $LD/2.10.0/loaders.cache"

echo "--- TEST: PNG decode ---"
C "export HOME=/root; cd /tmp; rm -f /tmp/ok.png; gdk-pixbuf-thumbnailer /usr/share/icons/gnome/48x48/places/folder.png /tmp/ok.png 2>&1 | sed -n '1,4p'; ls -la /tmp/ok.png 2>&1"

echo "--- rebuild icon caches + restart the desktop ---"
C 'gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>&1 | tail -1'
C 'gtk-update-icon-cache -f -t /usr/share/icons/gnome 2>&1 | tail -1'
C 'gtk-update-icon-cache -f -t /usr/share/icons/Adwaita 2>&1 | tail -1'
C 'for p in $(ls /proc | grep -E "^[0-9]+$"); do if [ -r /proc/$p/comm ] && grep -qE "xfdesktop|xfce4-panel" /proc/$p/comm 2>/dev/null; then kill -9 $p 2>/dev/null; fi; done'
sleep 2
C "export DISPLAY=:1; export HOME=/root; export USER=root; export SHELL=/bin/bash; \
export XDG_RUNTIME_DIR=/tmp/xdg; export XDG_CONFIG_HOME=/root/.config; \
export XDG_DATA_DIRS=/usr/local/share:/usr/share; export XDG_CONFIG_DIRS=/etc/xdg; \
xfdesktop --disable-wm-check > /dev/shm/xfdA.log 2>&1 &"
sleep 4
C "export DISPLAY=:1; export HOME=/root; export USER=root; export SHELL=/bin/bash; \
export XDG_RUNTIME_DIR=/tmp/xdg; export XDG_CONFIG_HOME=/root/.config; \
export XDG_DATA_DIRS=/usr/local/share:/usr/share; export XDG_CONFIG_DIRS=/etc/xdg; \
xfce4-panel > /dev/shm/panelA.log 2>&1 &"
sleep 10
C 'ps | grep -E "xfdesktop|xfce4-panel|mpv"'
echo "--- xfdesktop log ---"
C 'cat /dev/shm/xfdA.log' 2>/dev/null | tail -4
echo "==================== deploy2 done ===================="
