#!/bin/sh
OUT=/tmp/cg2.log
exec > "$OUT" 2>&1

echo "########## 1. cgminer config ##########"
cat /config/cgminer.conf 2>&1

echo
echo "########## 2. API port listening? ##########"
netstat -lnt 2>/dev/null | grep -E '4028|4029' || echo "  (netstat unavailable or no 4028)"
echo "--- /proc/net/tcp for port 4028 (0FB2) ---"
grep -i ':0FB2' /proc/net/tcp 2>/dev/null

echo
echo "########## 3. query API using chroot python3 ##########"
ROOT=/mnt/sd2/debian
# mount sd if needed
grep -q "/dev/mmcblk0p1 /mnt/sd2" /proc/mounts || mount /dev/mmcblk0p1 /mnt/sd2 2>/dev/null
busybox chroot "$ROOT" /bin/sh -c 'python3 - <<"PYEOF"
import socket
for cmd in ("summary","pools","devs","stats"):
    try:
        s = socket.create_connection(("127.0.0.1", 4028), timeout=3)
        s.sendall(("{\"command\":\"%s\"}" % cmd).encode())
        data = b""
        while True:
            c = s.recv(65536)
            if not c: break
            data += c
            if b"\x00" in data: break
        print("=== %s ===" % cmd)
        print(data.decode("utf-8","replace").replace("\x00","")[:1500])
        s.close()
    except Exception as e:
        print("=== %s === ERROR %s" % (cmd, e))
PYEOF' 2>&1

echo
echo "########## 4. raw /dev/bm_* ioctl via strings on cgminer ##########"
echo "--- temperature-related strings in cgminer binary ---"
strings /usr/bin/cgminer 2>/dev/null | grep -iE 'temp|thermal|fan|pwm|degree|hot|overheat' | head -n 30

echo "########## END ##########"
