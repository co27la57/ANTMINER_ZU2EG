#!/bin/sh
exec > /tmp/net_check.txt 2>&1

echo "############ 1. outbound HTTP via curl ############"
echo "--- example.com ---"
/usr/bin/curl -s -m 20 -o /dev/null -w "http=%{http_code} time=%{time_total}\n" http://example.com
echo "--- https deb.debian.org ---"
/usr/bin/curl -s -m 20 -o /dev/null -w "http=%{http_code}\n" https://deb.debian.org/debian/
echo "--- https mirrors.aliyun.com (china mirror) ---"
/usr/bin/curl -s -m 20 -o /dev/null -w "http=%{http_code}\n" https://mirrors.aliyun.com/debian/
echo "--- opkg feed for Angstrom? try known urls ---"
for u in http://downloads.angstrom-distribution.org/feeds/armv7ahf-vfp/ http://www.angstrom-distribution.org/feeds/ ; do
  printf "  %s -> " "$u"
  /usr/bin/curl -s -m 15 -o /dev/null -w "%{http_code}\n" "$u"
done
echo "--- can we reach our PC? (as http server test) ---"
/usr/bin/curl -s -m 10 -o /dev/null -w "http=%{http_code}\n" http://172.25.87.141/ 2>&1

echo "############ 2. SD card p2 partition info ############"
echo "--- p2 size ---"
ls -la /dev/mmcblk0p2
echo "--- try mount p2 ---"
mkdir -p /mnt/sd2
mount /dev/mmcblk0p2 /mnt/sd2 2>&1
echo "mount p2 rc=$?"
df -h /mnt/sd2 2>/dev/null
ls -la /mnt/sd2/ 2>/dev/null
umount /mnt/sd2 2>/dev/null

echo "############ 3. can we make ext4 on a loop file inside p1? ############"
echo "--- mkfs tools ---"
for t in mkfs.ext4 mkfs.vfat mke2fs losetup dd; do
  printf "  %-14s " "$t"
  if [ -e "/usr/sbin/$t" ]; then echo "/usr/sbin/$t"; 
  elif [ -e "/sbin/$t" ]; then echo "/sbin/$t";
  elif [ -e "/usr/bin/$t" ]; then echo "/usr/bin/$t";
  else echo "-"; fi
done
echo "--- busybox has mkfs? ---"
busybox --list 2>/dev/null | grep -i mkfs
echo "--- mke2fs on sd p1? (we will NOT do it, just check presence) ---"

echo "############ 4. opkg status: architecture + package list ############"
echo "--- status head ---"
sed -n '1,40p' /var/lib/opkg/status
echo "--- all package names ---"
grep '^Package:' /var/lib/opkg/status | sed 's/^Package: //'
echo "--- opkg config dirs ---"
ls -la /usr/lib/opkg /usr/share/opkg 2>/dev/null

echo "############ 5. libc / ABI info (for picking packages) ############"
ls -la /lib/ld* /lib/libc.so* 2>/dev/null
echo "--- libc version string ---"
strings /lib/libc.so.6 2>/dev/null | grep -i -E 'GNU C Library|GLIBC_2\.[0-9]+' | sort -u | head -10
echo "--- ldd version ---"
/usr/bin/ldd --version 2>&1 | head -2
echo "############ DONE ############"
