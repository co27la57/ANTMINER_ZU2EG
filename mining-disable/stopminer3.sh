#!/bin/sh
OUT=/tmp/stopminer3.log
exec > "$OUT" 2>&1

echo "########## 1. comment out the respawn line in inittab ##########"
cp -f /etc/inittab /etc/inittab.bak 2>/dev/null
sed -i 's|^dcdc:2345:respawn:/sbin/monitorcg|#dcdc:2345:respawn:/sbin/monitorcg  # DISABLED: mining watchdog|' /etc/inittab
grep -n 'monitorcg\|dcdc' /etc/inittab

echo
echo "########## 2. kill current respawn instances ##########"
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in *monitorcg*|*cgminer*)
        echo "  kill $p : $cmd"
        kill -9 "$p" 2>/dev/null
        ;;
    esac
done
sleep 2

echo
echo "########## 3. tell init to reload inittab ##########"
# BusyBox init reloads inittab on SIGHUP
kill -HUP 1 2>/dev/null && echo "  sent SIGHUP to init"
sleep 3
echo "--- inittab after reload ---"
grep -n 'monitorcg\|dcdc' /etc/inittab

echo
echo "########## 4. wait 30s, verify nothing respawns ##########"
sleep 30
found=0
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in
        *cgminer*|*monitorcg*) echo "  STILL RUNNING [$p] $cmd"; found=1;;
    esac
done
[ "$found" = 0 ] && echo "  CLEAN - no mining processes after 30s + init reload"

echo
echo "########## 5. final state ##########"
echo "--- GPIO ---"
for g in 403 404; do
    [ -d /sys/class/gpio/gpio$g ] && echo "  gpio$g = $(cat /sys/class/gpio/gpio$g/value 2>/dev/null)"
done
echo "--- load ---"
cat /proc/loadavg
echo "--- key processes still alive (desktop stack) ---"
ps | grep -E 'Xvfb|x11vnc|xfce4|dillo|mpv|dropbear' | grep -v grep | head -n 15

echo "########## END ##########"
