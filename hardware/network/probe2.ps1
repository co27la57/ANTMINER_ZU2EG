$ErrorActionPreference = 'Continue'
$plink = 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/sshlib/plink.exe'
$hk    = 'SHA256:fLyd0km1Y7wt1As5WZHCx0rnscvz/JMutaGCn6v9jQU'
$target = '172.25.81.151'
$errf  = "$env:TEMP\dump_err.txt"
$outf  = "$env:TEMP\dump_out.txt"

$remote = @'
echo "=== busybox applets check ==="
busybox | tr "," "\n" | grep -E "^(tar|gzip|find|du|sha256sum|xxd|hexdump|od|cpio)$"
echo "=== boot dir ==="
ls -la /boot/
echo "=== dtb files anywhere ==="
find / -xdev -name "*.dtb" 2>/dev/null
find / -xdev -name "*.dts" 2>/dev/null
echo "=== /boot content sizes ==="
ls -la /boot/* 2>/dev/null
echo "=== total size of key dirs (du) ==="
du -sh /bin /sbin /etc /lib /usr /var /www /home /media /boot /config 2>/dev/null
echo "=== /proc/device-tree/amba top (find) ==="
ls /proc/device-tree/amba/
echo "=== zynqmp specific nodes ==="
ls -d /proc/device-tree/*pinctrl* /proc/device-tree/*gpio* /proc/device-tree/*pin* 2>/dev/null
echo "=== firmware node ==="
ls -la /proc/device-tree/firmware/ 2>/dev/null
cat /proc/device-tree/firmware/@0/type 2>/dev/null | tr -d "\0"; echo
echo "=== nvmem_firmware ==="
ls -R /proc/device-tree/nvmem_firmware/ 2>/dev/null
echo "=== DONE ==="
'@

& $plink -ssh -batch -no-antispoof -hostkey $hk -P 22 -l root -pw admin $target $remote 1> $outf 2> $errf
Write-Output ("exit=" + $LASTEXITCODE)
Write-Output "--- STDOUT ---"
if (Test-Path $outf) { Get-Content $outf }
Write-Output "--- STDERR ---"
if (Test-Path $errf) { Get-Content $errf | Select-Object -First 20 }
