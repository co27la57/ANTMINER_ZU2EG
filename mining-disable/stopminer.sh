#!/bin/sh
OUT=/tmp/stopminer.log
exec > "$OUT" 2>&1

echo "########## 1. BEFORE: mining processes ##########"
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in *cgminer*|*monitorcg*|*SCREEN*) echo "  [$p] $cmd";; esac
done

echo
echo "########## 2. stop the watchdog FIRST (or it will restart cgminer in 20s) ##########"
# monitorcg is the watchdog that restarts cgminer. Kill it first.
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in
        */sbin/monitorcg*|*monitorcg*)
            echo "  killing watchdog $p: $cmd"
            kill -9 "$p" 2>/dev/null
            ;;
    esac
done

echo
echo "########## 3. stop cgminer and its screen ##########"
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in
        *cgminer*|*SCREEN*cgminer*)
            echo "  killing $p: $cmd"
            kill -9 "$p" 2>/dev/null
            ;;
    esac
done
sleep 3

echo
echo "########## 4. AFTER: verify no mining processes ##########"
left=0
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in *cgminer*|*monitorcg*) echo "  STILL RUNNING [$p] $cmd"; left=1;; esac
done
[ "$left" = 0 ] && echo "  CLEAN - no mining processes left"

echo
echo "########## 5. disable autostart (rename, reversible) ##########"
for f in /etc/rcS.d/S70cgminer.sh /etc/init.d/cgminer.sh; do
    if [ -e "$f" ]; then
        mv "$f" "$f.disabled" 2>/dev/null && echo "  renamed $f -> $f.disabled"
    fi
done
ls -la /etc/rcS.d/ | grep -i cgminer
ls -la /etc/init.d/ | grep -i cgminer

echo
echo "########## 6. power down the ASIC (GPIO403/404) ##########"
echo "--- current GPIO state ---"
for g in 403 404 408 411; do
    if [ -d /sys/class/gpio/gpio$g ]; then
        echo "  gpio$g direction=$(cat /sys/class/gpio/gpio$g/direction 2>/dev/null) value=$(cat /sys/class/gpio/gpio$g/value 2>/dev/null)"
    fi
done
echo "--- turning off ASIC power (gpio404) and reset (gpio403) ---"
[ -d /sys/class/gpio/gpio404 ] && echo 0 > /sys/class/gpio/gpio404/value 2>/dev/null && echo "  gpio404 -> 0"
[ -d /sys/class/gpio/gpio403 ] && echo 0 > /sys/class/gpio/gpio403/value 2>/dev/null && echo "  gpio403 -> 0"
sleep 2
echo "--- GPIO state after ---"
for g in 403 404; do
    [ -d /sys/class/gpio/gpio$g ] && echo "  gpio$g value=$(cat /sys/class/gpio/gpio$g/value 2>/dev/null)"
done

echo
echo "########## 7. CPU idle after stop (3s sample) ##########"
head -n 1 /proc/stat
sleep 3
head -n 1 /proc/stat
cat /proc/loadavg

echo "########## END ##########"
