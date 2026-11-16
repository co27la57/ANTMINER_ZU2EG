#!/bin/sh
# =====================================================================
# Deploy the Debian armhf chroot + xfce4 desktop onto the Antminer E7.
#
# Handles every problem we hit during development:
#   - device node major/minor changes after the SD card is re-plugged
#   - NEVER bind-mount /dev into the chroot (it strips the host's devtmpfs)
#   - /etc/xdg and friends must exist
#   - gdk-pixbuf loaders.cache must be written by hand
#   - dbus needs messagebus/dbus users + a 32-hex machine-id
#   - BusyBox has no `head -N`, no `timeout`, no `od -A`
# =====================================================================
OUT=/mnt/sd2/deploy.log
exec > "$OUT" 2>&1

ROOT=/mnt/sd2/debian
DISP=:1
GEOM=1280x800x24
LD=/usr/lib/arm-linux-gnueabihf/gdk-pixbuf-2.0/2.10.0

echo "==================== deploy: $(date) ===================="

# ---------------------------------------------------------------- 1. card
echo "--- [1] fix the mmc device nodes and mount the card ---"
rm -f /dev/mmcblk0 /dev/mmcblk0p1 /dev/mmcblk0p2 2>/dev/null
grep -E 'mmcblk' /proc/partitions | while read MAJ MIN BLKS NAME; do
    mknod "/dev/$NAME" b "$MAJ" "$MIN" 2>/dev/null && chmod 660 "/dev/$NAME"
done
ls -la /dev/mmcblk* 2>&1

umount /mnt/sd2/debian/proc 2>/dev/null
umount /mnt/sd2/debian/sys 2>/dev/null
umount /mnt/sd2/debian/dev/pts 2>/dev/null
umount /mnt/sd2/debian/dev/shm 2>/dev/null
umount /mnt/sd2 2>/dev/null
umount /mnt/sd 2>/dev/null
sleep 1

mkdir -p /mnt/sd2
CARD=""
for dev in /dev/mmcblk0p1 /dev/mmcblk0p2 /dev/mmcblk0; do
    [ -b "$dev" ] || continue
    mount "$dev" /mnt/sd2 2>/dev/null
    # verify the mount really took effect for THIS device
    # /proc/mounts format: <device> <mountpoint> <fstype> ...
    if grep -q "^$dev /mnt/sd2 " /proc/mounts 2>/dev/null; then
        CARD="$dev"
        break
    fi
done
if [ -z "$CARD" ]; then
    echo "FATAL: cannot mount the SD card"
    cat /proc/mounts | grep mmc
    exit 1
fi
echo "  mounted $CARD"
df -h /mnt/sd2
if ! touch /mnt/sd2/.wt 2>/dev/null; then
    echo "FATAL: card is read-only"
    exit 1
fi
rm -f /mnt/sd2/.wt

# ------------------------------------------------------------- 2. unpack
echo "--- [2] unpack the package bundles ---"
rm -rf "$ROOT" /mnt/sd2/w
mkdir -p "$ROOT" /mnt/sd2/w
BUNDLES="lean.tar all_tars.tar delta.tar delta2.tar delta3.tar delta4.tar delta5.tar delta6.tar"
for b in $BUNDLES; do
    src="/mnt/sd2/$b"
    [ -f "$src" ] || { echo "  skip $b"; continue; }
    w=/mnt/sd2/w
    rm -rf "$w"; mkdir -p "$w"
    cd "$w" && tar xf "$src" 2>/dev/null
    cnt=0
    for f in "$w"/*.tar; do
        [ -e "$f" ] || continue
        cd "$ROOT" && tar xf "$f" 2>/dev/null && cnt=$((cnt+1))
    done
    echo "  $b -> $cnt packages"
    rm -rf "$w"
done
rm -rf /mnt/sd2/w
du -sh "$ROOT"

# ------------------------------------------------------------ 3. bind fs
echo "--- [3] bind /proc and /sys (NOT /dev) ---"
mkdir -p "$ROOT/proc" "$ROOT/sys"
mount --bind /proc "$ROOT/proc" && echo "  proc ok"
mount --bind /sys  "$ROOT/sys"  && echo "  sys  ok"

C() { busybox chroot "$ROOT" /bin/sh -c "$1" 2>&1; }

echo "--- [4] shell check ---"
C 'echo SHELL_OK; ls -la /bin/sh'

# ------------------------------------------------- 5. devices and /etc
echo "--- [5] device nodes + /etc + machine-id ---"
mkdir -p "$ROOT/dev/pts" "$ROOT/dev/shm" "$ROOT/run/dbus" "$ROOT/var/lib/dbus" \
         "$ROOT/var/run/dbus" "$ROOT/etc/xdg" "$ROOT/etc/xdg/gtk-2.0" \
         "$ROOT/etc/xdg/xfce4" "$ROOT/etc/xdg/autostart" "$ROOT/etc/xdg/menus" \
         "$ROOT/etc/xdg/applications" "$ROOT/etc/dbus-1" "$ROOT/etc/dbus-1/system.d" \
         "$ROOT/root" "$ROOT/home/antminer" "$ROOT/root/.config/gtk-2.0" \
         "$ROOT/root/.config/xfce4/xfconf/xfce-perchannel-xml" \
         "$ROOT/root/.config/xfce4/xfce-perchannel-desktop" \
         "$ROOT/root/.cache" "$ROOT/root/.local/share" "$ROOT/var/log" "$ROOT/tmp"

for spec in "null c 1 3" "zero c 1 5" "full c 1 7" "random c 1 8" "urandom c 1 9" \
            "tty c 5 0" "console c 5 1" "ptmx c 5 2" "ttyS0 c 4 64" "ttyS1 c 4 65"; do
    NAME=$(echo "$spec" | cut -d' ' -f1)
    TYPE=$(echo "$spec" | cut -d' ' -f2)
    MAJ=$(echo "$spec" | cut -d' ' -f3)
    MIN=$(echo "$spec" | cut -d' ' -f4)
    [ -e "$ROOT/dev/$NAME" ] || mknod "$ROOT/dev/$NAME" "$TYPE" "$MAJ" "$MIN" 2>/dev/null
    chmod 666 "$ROOT/dev/$NAME" 2>/dev/null
done

cat > "$ROOT/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
messagebus:x:100:101::/nonexistent:/usr/sbin/nologin
dbus:x:101:102::/nonexistent:/usr/sbin/nologin
nobody:x:65534:65534:nobody:/nonexistent:/bin/false
antminer:x:1000:1000:antminer:/home/antminer:/bin/sh
EOF
cat > "$ROOT/etc/group" <<'EOF'
root:x:0:
messagebus:x:101:
dbus:x:102:
nogroup:x:65534:
antminer:x:1000:
EOF
cat > "$ROOT/etc/shadow" <<'EOF'
root::19000:0:99999:7:::
antminer::19000:0:99999:7:::
EOF
cat > "$ROOT/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 antminer
EOF
printf 'antminer\n' > "$ROOT/etc/hostname"
chmod 700 "$ROOT/root"

MID=$(C 'od -An -tx1 -N16 /dev/urandom | tr -d " \n"' | tr -d '\r\n')
[ -z "$MID" ] && MID="0123456789abcdef0123456789abcdef"
printf '%s' "$MID" > "$ROOT/etc/machine-id"
printf '%s' "$MID" > "$ROOT/var/lib/dbus/machine-id"
echo "  machine-id = $MID"

# --------------------------------------------- 6. gdk-pixbuf loaders
echo "--- [6] gdk-pixbuf loaders.cache (hand written) ---"
mkdir -p "$ROOT$LD/loaders"
{
echo "\"$LD/loaders/libpixbufloader-ani.so\""; echo '"ani" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-bmp.so\""; echo '"bmp" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-gif.so\""; echo '"gif" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-icns.so\""; echo '"icns" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-ico.so\""; echo '"ico" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-jpeg.so\""; echo '"jpeg" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-png.so\""; echo '"png" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-pnm.so\""; echo '"pnm" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-qtif.so\""; echo '"qtif" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-svg.so\""; echo '"svg" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-tga.so\""; echo '"tga" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-tiff.so\""; echo '"tiff" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-xbm.so\""; echo '"xbm" 5 "wibble" 100'
echo "\"$LD/loaders/libpixbufloader-xpm.so\""; echo '"xpm" 5 "wibble" 100'
} > "$ROOT$LD/loaders.cache"
echo "  loaders.cache = $(ls -la $ROOT$LD/loaders.cache | awk '{print $5}') bytes"

cat > "$ROOT/etc/xdg/gtk-2.0/settings.ini" <<'EOF'
[Settings]
gtk-icon-theme-name=Adwaita
gtk-theme-name=Adwaita
gtk-font-name=Sans 10
gtk-menu-images=true
EOF
cp "$ROOT/etc/xdg/gtk-2.0/settings.ini" "$ROOT/root/.config/gtk-2.0/settings.ini"

# ------------------------------------------------------- 7. caches/dbus
echo "--- [7] dbus + icon/font/mime caches ---"
C 'mount -t devpts devpts /dev/pts 2>/dev/null'
C 'mount -t tmpfs -o size=48M tmpfs /dev/shm 2>/dev/null'
C 'dbus-daemon --system --fork 2>/dev/null'
sleep 2
C 'ls /var/run/dbus/'
C 'update-mime-database /usr/share/mime >/dev/null 2>&1'
C 'gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>&1 | tail -1'
C 'gtk-update-icon-cache -f -t /usr/share/icons/Adwaita 2>&1 | tail -1'
C 'gtk-update-icon-cache -f -t /usr/share/icons/default 2>&1 | tail -1'
echo "  hicolor cache: $(ls -la $ROOT/usr/share/icons/hicolor/icon-theme.cache 2>/dev/null | awk '{print $5}')"
C 'fc-cache -f >/dev/null 2>&1; echo "  fc-cache done"'

# ------------------------------------------------------ 8. start desktop
echo "--- [8] start Xvfb + x11vnc + xfce4 ---"
sh /mnt/sd2/start_desktop.sh

echo "==================== deploy done: $(date) ===================="
