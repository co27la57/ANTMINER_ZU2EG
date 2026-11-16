#!/bin/sh
OUT=/tmp/cg3.log
exec > "$OUT" 2>&1

echo "########## 1. monitorcg script (what it does) ##########"
cat /sbin/monitorcg 2>/dev/null | head -n 80

echo
echo "########## 2. cgminer.sh startup script ##########"
cat /etc/init.d/cgminer.sh 2>/dev/null | head -n 100

echo
echo "########## 3. /tmp/fanstatus and miner logs ##########"
ls -la /tmp/*fan* /tmp/*miner* /var/log/*miner* 2>/dev/null
echo "--- fanstatus ---"
cat /tmp/fanstatus 2>/dev/null | tail -n 30
echo "--- messages last 40 lines ---"
tail -n 40 /var/log/messages 2>/dev/null

echo
echo "########## 4. process state detail for cgminer (1903) ##########"
for p in 1902 1903 1918; do
    echo "--- pid $p ---"
    cat /proc/$p/status 2>/dev/null | grep -E '^(Name|State|Threads|VmRSS|voluntary_ctxt_switches|nonvoluntary_ctxt_switches)'
    echo "wchan: $(cat /proc/$p/wchan 2>/dev/null)"
    echo "fd:"
    ls -la /proc/$p/fd/ 2>/dev/null | head -n 15
done

echo
echo "########## 5. network to pool 192.168.100.102:8028 ##########"
echo "--- route ---"
cat /proc/net/route 2>/dev/null
echo "--- any established connection to :8028 (1F5C) ---"
grep -i ':1F5C' /proc/net/tcp 2>/dev/null || echo "  none"

echo "########## END ##########"
