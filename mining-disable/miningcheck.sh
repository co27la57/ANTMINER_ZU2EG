#!/bin/sh
OUT=/tmp/mining.log
exec > "$OUT" 2>&1

echo "########## 1. FULL PROCESS LIST (from /proc, most reliable) ##########"
printf "%-8s %-8s %-10s %s\n" "PID" "PPID" "RSS(kB)" "CMDLINE"
for d in /proc/[0-9]*; do
    p=${d##*/}
    [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    ppid=$(awk '/^PPid:/{print $2}' "$d/status" 2>/dev/null)
    rss=$(awk '/^VmRSS:/{print $2}' "$d/status" 2>/dev/null)
    printf "%-8s %-8s %-10s %s\n" "$p" "$ppid" "${rss:-0}" "$cmd"
done | sort -k3 -nr | head -n 60

echo
echo "########## 2. processes matching mining keywords ##########"
for d in /proc/[0-9]*; do
    p=${d##*/}
    [ -r "$d/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    exe=$(readlink "$d/exe" 2>/dev/null)
    case "$cmd $exe" in
        *cgminer*|*bmminer*|*miner*|*Miner*|*mining*|*asic*|*Antminer*|*antminer*|*stratum*|*pool*|*ethminer*|*bitmain*|*bm1794*)
            echo "  [$p] cmd=$cmd"
            echo "        exe=$exe"
            echo "        cwd=$(readlink $d/cwd 2>/dev/null)"
            echo "        status: $(grep -E '^(State|Threads|VmRSS):' $d/status 2>/dev/null | tr '\n' ' ')"
            ;;
    esac
done

echo
echo "########## 3. CPU time consumers (top 20 by utime+stime) ##########"
printf "%-8s %-12s %-10s %s\n" "PID" "TICKS" "STATE" "CMD"
for d in /proc/[0-9]*; do
    p=${d##*/}
    [ -r "$d/stat" ] || continue
    # fields: pid comm state ppid ... utime(14) stime(15)
    ticks=$(awk '{print $14+$15}' "$d/stat" 2>/dev/null)
    state=$(awk '{print $3}' "$d/stat" 2>/dev/null)
    cmd=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    [ -n "$cmd" ] && printf "%-8s %-12s %-10s %s\n" "$p" "$ticks" "$state" "$cmd"
done | sort -k2 -nr | head -n 20

echo
echo "########## 4. CPU load / idle ##########"
cat /proc/loadavg
echo "--- cpu stat (two samples 3s apart for usage) ---"
head -n 1 /proc/stat
sleep 3
head -n 1 /proc/stat

echo
echo "########## 5. TEMPERATURES ##########"
echo "--- /sys/class/thermal ---"
for t in /sys/class/thermal/thermal_zone*; do
    [ -r "$t/temp" ] || continue
    type=$(cat "$t/type" 2>/dev/null)
    temp=$(cat "$t/temp" 2>/dev/null)
    echo "  $(basename $t) type=$type temp=$temp (=$((temp/1000)) C)"
done
echo "--- hwmon ---"
for h in /sys/class/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    name=$(cat "$h/name" 2>/dev/null)
    echo "  $(basename $h) name=$name"
    for f in "$h"/temp*_input; do
        [ -r "$f" ] || continue
        v=$(cat "$f" 2>/dev/null)
        echo "      $(basename $f) = $((v/1000)) C"
    done
done

echo
echo "########## 6. ASIC / mining devices ##########"
ls -la /dev/ | grep -iE 'asic|bitmain|miner|bm|cgroup' | head -n 20
echo "--- /proc/interrupts (high IRQ = active hardware) ---"
head -n 20 /proc/interrupts

echo
echo "########## 7. network connections (pool?) ##########"
cat /proc/net/tcp 2>/dev/null | head -n 20

echo
echo "########## 8. autostart / init scripts mentioning miner ##########"
grep -rilE 'cgminer|bmminer|miner|stratum' /etc/init.d /etc/rc*.d /etc/cron* /etc/inittab /usr/bin /usr/sbin 2>/dev/null | head -n 30

echo "########## END ##########"
