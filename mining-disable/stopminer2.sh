#!/bin/sh
OUT=/tmp/stopminer2.log
exec > "$OUT" 2>&1

echo "########## 1. find ALL mining-related processes with parent chain ##########"
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in
        *cgminer*|*monitorcg*|*SCREEN*)
            ppid=$(awk '/^PPid:/{print $2}' "$d/status" 2>/dev/null)
            pcmd=""
            [ -r /proc/$ppid/cmdline ] && pcmd=$(tr '\0' ' ' < /proc/$ppid/cmdline 2>/dev/null)
            echo "  PID=$p PPID=$ppid"
            echo "    cmd : $cmd"
            echo "    parent: $pcmd"
            ;;
    esac
done

echo
echo "########## 2. inittab / init config ##########"
cat /etc/inittab 2>/dev/null | grep -v '^#' | grep -v '^$'
echo "--- /etc/init.d/ mining scripts ---"
ls -la /etc/init.d/ | grep -iE 'cgmin|miner|monitor'
echo "--- /etc/rcS.d/ ---"
ls -la /etc/rcS.d/ | grep -iE 'cgmin|miner|monitor'

echo
echo "########## 3. kill ALL of them repeatedly (3 rounds) ##########"
for round in 1 2 3; do
    echo "--- round $round ---"
    for d in /proc/[0-9]*; do
        p=${d##*/}; [ -r "$d/cmdline" ] || continue
        cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
        case "$cmd" in
            *cgminer*|*monitorcg*|*SCREEN*cgminer*)
                echo "  kill -9 $p : $cmd"
                kill -9 "$p" 2>/dev/null
                ;;
        esac
    done
    sleep 3
done

echo
echo "########## 4. rename monitorcg itself (reversible) ##########"
if [ -f /sbin/monitorcg ]; then
    mv /sbin/monitorcg /sbin/monitorcg.disabled && echo "  /sbin/monitorcg -> .disabled"
fi
if [ -f /usr/bin/monitor-recobtn ]; then
    mv /usr/bin/monitor-recobtn /usr/bin/monitor-recobtn.disabled && echo "  monitor-recobtn -> .disabled"
fi

echo
echo "########## 5. disable remaining rc links ##########"
for f in /etc/rcS.d/*cgmin* /etc/rcS.d/*monitor* /etc/rcS.d/*miner*; do
    [ -e "$f" ] || continue
    case "$f" in *.disabled) continue;; esac
    mv "$f" "$f.disabled" 2>/dev/null && echo "  $f -> .disabled"
done

echo
echo "########## 6. FINAL verification (wait 25s to outlast watchdog timer) ##########"
sleep 25
found=0
for d in /proc/[0-9]*; do
    p=${d##*/}; [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    case "$cmd" in
        *cgminer*|*monitorcg*) echo "  STILL RUNNING [$p] $cmd"; found=1;;
    esac
done
[ "$found" = 0 ] && echo "  CLEAN - no mining processes after 25s"

echo "--- GPIO state ---"
for g in 403 404; do
    [ -d /sys/class/gpio/gpio$g ] && echo "  gpio$g = $(cat /sys/class/gpio/gpio$g/value 2>/dev/null)"
done

echo "--- CPU load ---"
cat /proc/loadavg
head -n 1 /proc/stat
sleep 3
head -n 1 /proc/stat

echo "########## END ##########"
