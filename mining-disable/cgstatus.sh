#!/bin/sh
OUT=/tmp/cgstatus.log
exec > "$OUT" 2>&1

echo "########## 1. cgminer API - summary (port 4028) ##########"
echo "--- stats via local API ---"
if command -v cgminer-api >/dev/null 2>&1; then
    cgminer-api summary 2>&1 | head -c 2000
    echo
fi
echo "--- raw socket query via python ---"
python - <<'PYEOF' 2>/dev/null || echo "  (no python on host root)"
import socket
s = socket.socket(); s.settimeout(3)
try:
    s.connect(('127.0.0.1', 4028))
    for cmd in ('summary','pools','devs'):
        s.sendall(('{"command":"%s"}' % cmd).encode())
        data = b''
        while True:
            chunk = s.recv(65536)
            if not chunk: break
            data += chunk
            if b'\x00' in data: break
        print("  [%s] %s" % (cmd, data.decode('utf-8','replace')[:900]))
except Exception as e:
    print("  API error:", e)
finally:
    s.close()
PYEOF

echo
echo "########## 2. cgminer config (pool / freq) ##########"
cat /config/cgminer.conf 2>/dev/null | head -c 2000
echo

echo
echo "########## 3. bitmain hardware status tools ##########"
ls -la /usr/bin/ | grep -iE 'fan|temp|pwm|led|speed|voltage|bgminer|bmminer' | head -n 20
echo "--- /config ---"
ls -la /config/ 2>/dev/null | head -n 30

echo
echo "########## 4. temperature via i2c / sysfs ##########"
echo "--- i2c devices ---"
ls -la /sys/bus/i2c/devices/ 2>/dev/null | head -n 20
echo "--- all temp files anywhere under /sys ---"
find /sys -name 'temp*' -o -name '*temp*input*' 2>/dev/null | head -n 30
echo "--- try lm-sensors style ---"
cat /sys/devices/platform/*.温度 2>/dev/null
find /sys/devices -maxdepth 3 -name 'temp*' 2>/dev/null | head -n 20

echo
echo "########## 5. fan / pwm state ##########"
for f in /sys/class/pwm/pwmchip*/pwm*/duty_cycle /sys/devices/platform/*/pwm*; do
    [ -r "$f" ] && echo "  $f = $(cat $f 2>/dev/null)"
done
echo "--- bm_pwm device ---"
ls -la /dev/bm_pwm /dev/bm_speed /dev/bm_led 2>/dev/null

echo
echo "########## 6. syslog mining messages (last 20) ##########"
grep -iE 'cgminer|miner|temp|fan|ASIC|hash' /var/log/messages 2>/dev/null | tail -n 25

echo "########## END ##########"
