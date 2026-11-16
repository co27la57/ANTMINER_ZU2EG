$ErrorActionPreference = 'SilentlyContinue'
$base = 'http://172.25.81.151'
$auth = 'root:root'

# Common Antminer CGI endpoints
$paths = @(
    '/cgi-bin/luci/;stok=/',
    '/cgi-bin/luci/;stok=',
    '/api/network',
    '/cgi-bin/status.cgi',
    '/cgi-bin/antscgi',
    '/cgi-bin/getinfo.cgi',
    '/cgi-bin/system.cgi',
    '/cgi-bin/antminer.cgi',
    '/cgi-bin/luci/admin/system/overview',
    '/cgi-bin/luci/admin/system/admin',
    '/cgi-bin/luci/admin/network/network',
    '/cgi-bin/luci/admin/status/overview',
    '/cgi-bin/luci/admin/firmware',
    '/api/status',
    '/api/system/info',
    '/cgi-bin/snmp'
)

Write-Output "=== probe endpoints ==="
foreach ($p in $paths) {
    $url = $base + $p
    $code = (curl.exe -s -o "$env:TEMP\ep.txt" -w "%{http_code}" --digest -u $auth --max-time 12 $url 2>&1 | Out-String).Trim()
    $len = 0
    if (Test-Path "$env:TEMP\ep.txt") { $len = (Get-Item "$env:TEMP\ep.txt").Length }
    Write-Output ("{0,-45} http={1,-5} len={2}" -f $p, $code, $len)
}
