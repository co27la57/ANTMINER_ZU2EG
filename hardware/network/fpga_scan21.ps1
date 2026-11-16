$ErrorActionPreference = 'SilentlyContinue'

$route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
$idx   = $route.InterfaceIndex
$addr  = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $idx | Select-Object -First 1
$localIP = $addr.IPAddress
$prefix  = $addr.PrefixLength

$parts = $localIP.Split('.')
$ipInt = [uint32]$parts[0]*16777216 + [uint32]$parts[1]*65536 + [uint32]$parts[2]*256 + [uint32]$parts[3]
$mask  = ([uint32]::MaxValue) -shl (32 - $prefix)
$net   = $ipInt -band $mask
$count = [math]::Pow(2, (32 - $prefix)) - 2

$targets = @()
for ($i = 1; $i -le $count; $i++) {
    $c = [uint32]($net + $i)
    $a = [math]::Floor($c / 16777216); $rem = $c % 16777216
    $b = [math]::Floor($rem / 65536);   $rem = $rem % 65536
    $d = [math]::Floor($rem / 256);     $e = $rem % 256
    $ip = "$a.$b.$d.$e"
    if ($ip -eq $localIP) { continue }
    $targets += $ip
}
Write-Output ("Scanning " + $targets.Count + " hosts in /" + $prefix + " (from " + $localIP + ")")

# parallel ping + probe 3121
$pool = [runspacefactory]::CreateRunspacePool(1, 96); $pool.Open()
$jobs = @()
foreach ($t in $targets) {
    $ps = [powershell]::Create().AddScript({
        param($ip)
        $alive = $false
        $p = New-Object System.Net.NetworkInformation.Ping
        try { $r = $p.Send($ip, 500); if ($r.Status -eq 'Success') { $alive = $true } } catch {}
        $p3121 = $false
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($ip, 3121, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(350) -and $tcp.Connected) { $p3121 = $true }
        try { $tcp.Close() } catch {}
        if ($alive -or $p3121) { return ($ip + "|" + $alive + "|" + $p3121) }
        return $null
    }).AddArgument($t)
    $ps.RunspacePool = $pool
    $jobs += [pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke() }
}
$hits = @()
foreach ($j in $jobs) { $r = $j.Pipe.EndInvoke($j.Handle); if ($r) { $hits += $r }; $j.Pipe.Dispose() }
$pool.Close()

# ARP real MAC map
$arp = @{}
Get-NetNeighbor -AddressFamily IPv4 | Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' -and $_.LinkLayerAddress -notmatch '^(FF-FF|01-00-5E)' } | ForEach-Object { $arp[$_.IPAddress] = ($_.LinkLayerAddress -replace '-', ':').ToUpper() }

Write-Output "--- HITS (ping alive OR port 3121 open) ---"
if ($hits.Count -eq 0) { Write-Output "  (none)" }
foreach ($h in $hits) {
    $p = $h.Split('|'); $ip = $p[0]; $alive = $p[1]; $hw = $p[2]
    $mac = if ($arp.ContainsKey($ip)) { $arp[$ip] } else { '-' }
    $x = if ($mac -match '^00:0A:35') { '  <== XILINX OUI' } else { '' }
    Write-Output ("{0,-16} ping={1,-6} p3121={2,-6} mac={3,-20}{4}" -f $ip, $alive, $hw, $mac, $x)
}

Write-Output "--- All ARP real-MAC entries in 172.25.* ---"
Get-NetNeighbor -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^172\.25\.' -and $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' -and $_.LinkLayerAddress -notmatch '^(FF-FF|01-00-5E)' } | Sort-Object IPAddress -Unique | ForEach-Object {
    $mac = ($_.LinkLayerAddress -replace '-', ':').ToUpper()
    $x = if ($mac -match '^00:0A:35') { '  <== XILINX OUI' } else { '' }
    Write-Output ("{0,-16} {1,-20} {2}{3}" -f $_.IPAddress, $mac, $_.State, $x)
}
