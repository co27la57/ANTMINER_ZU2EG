#!/bin/sh
echo "=== busybox applets full list ==="
busybox 2>&1 | tr ',' '\n' | sed 's/^ *//' > /tmp/bb_applets.txt
wc -l /tmp/bb_applets.txt
echo "--- key applets present? ---"
for a in tar gzip find du sha256sum xxd hexdump od cpio bzip2 cat ls stat; do
  if grep -qx "$a" /tmp/bb_applets.txt; then echo "$a: YES"; else echo "$a: no"; fi
done
echo "=== dtc available? ==="
which dtc 2>/dev/null || echo "no dtc"
ls -la /usr/bin/dtc /usr/sbin/dtc /bin/dtc 2>/dev/null
echo "=== pinctrl node detail ==="
ls -la /proc/device-tree/amba/pinctrl@ff180000/ 2>/dev/null
echo "--- pinctrl subnodes ---"
find /proc/device-tree/amba/pinctrl@ff180000/ 2>/dev/null
echo "=== does running device-tree have pinctrl groups? search whole tree ==="
find /proc/device-tree/ -type d 2>/dev/null | grep -i -E 'pinctrl|mio|pinconf' 
echo "=== list ALL dirs in device-tree (top) ==="
find /proc/device-tree/ -maxdepth 2 -type d 2>/dev/null
echo "=== DONE ==="
