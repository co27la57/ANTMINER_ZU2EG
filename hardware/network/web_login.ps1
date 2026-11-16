$ErrorActionPreference = 'SilentlyContinue'
$target = 'http://172.25.81.151/'
$creds = @('root:root','root:admin','admin:root','admin:admin','root:antminer','root:bitmain','root:xilinx','root:')

foreach ($c in $creds) {
    $u = $c.Split(':')[0]; $p = $c.Split(':')[1]
    $out = curl.exe -s -o "$env:TEMP\antm.html" -w "%{http_code}" --digest -u "${u}:${p}" --max-time 15 $target 2>&1
    $code = ($out | Out-String).Trim()
    $body = ''
    if (Test-Path "$env:TEMP\antm.html") { $body = (Get-Content "$env:TEMP\antm.html" -Raw -ErrorAction SilentlyContinue) }
    $sig = ''
    if ($body -match '<title>([^<]*)</title>') { $sig = $Matches[1] }
    elseif ($body -match '401') { $sig = '401 Unauthorized' }
    Write-Output ("{0,-16} http={1,-5} title={2}" -f $c, $code, $sig)
    if ($code -eq '200') {
        Write-Output "  >>> LOGIN OK"
        Write-Output ("  body head: " + (($body -replace "`r?`n",' ').Substring(0, [Math]::Min(600, $body.Length))))
        break
    }
}
