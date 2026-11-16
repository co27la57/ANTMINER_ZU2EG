#!/bin/sh
OUT=/tmp/verifyboot.log
exec > "$OUT" 2>&1

echo "########## 1. all possible mining autostart entries ##########"
echo "--- inittab ---"
grep -inE 'cgmin|miner|dcdc' /etc/inittab || echo "  none"
echo "--- /etc/rcS.d ---"
ls /etc/rcS.d/ | grep -iE 'cgmin|miner' || echo "  none active"
echo "--- /etc/rc?.d ---"
for d in /etc/rc?.d; do ls "$d" 2>/dev/null | grep -iE 'cgmin|miner' && echo "  in $d"; done
echo "--- crontab ---"
crontab -l 2>/dev/null | grep -iE 'cgmin|miner' || echo "  none"

echo
echo "########## 2. disabled files (recovery is easy) ##########"
ls -la /etc/inittab.bak /etc/rcS.d/*.disabled /etc/init.d/*.disabled /sbin/monitorcg.disabled 2>/dev/null

echo
echo "########## 3. GPIO state (ASIC power off) ##########"
for g in 403 404 408 411; do
    [ -d /sys/class/gpio/gpio$g ] && echo "  gpio$g = $(cat /sys/class/gpio/gpio$g/value 2>/dev/null)"
done

echo
echo "########## 4. current mining processes ##########"
n=0
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in *cgminer*|*monitorcg*) echo "  FOUND [$p] $cmd"; n=1;; esac
done
[ "$n" = 0 ] && echo "  none"

echo "########## END ##########"
