$ErrorActionPreference = 'SilentlyContinue'

$route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
$addr  = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex | Select-Object -First 1
$localIP = $addr.IPAddress; $prefix = $addr.PrefixLength

$parts = $localIP.Split('.')
$ipInt = [uint32]$parts[0]*16777216 + [uint32]$parts[1]*65536 + [uint32]$parts[2]*256 + [uint32]$parts[3]
$net   = $ipInt -band (([uint32]::MaxValue) -shl (32 - $prefix))
$count = [math]::Pow(2, (32 - $prefix)) - 2

$targets = @()
for ($i = 1; $i -le $count; $i++) {
    $c = [uint32]($net + $i)
    $a = [math]::Floor($c/16777216); $rem = $c % 16777216
    $b = [math]::Floor($rem/65536);   $rem = $rem % 65536
    $d = [math]::Floor($rem/256);     $e = $rem % 256
    $ip = "$a.$b.$d.$e"
    if ($ip -ne $localIP) { $targets += $ip }
}
Write-Output ("Direct port sweep over " + $targets.Count + " hosts")

# Ports that matter: 3121=Xilinx hw_server, 22=SSH, 80/443=web, 7547=TR-069(CWMP),
# 3333/9090=miner mgmt API, 23=telnet, 37215=Huawei TR-069
$ports = @(3121, 22, 23, 80, 443, 7547, 3333, 9090, 8080)

$pool = [runspacefactory]::CreateRunspacePool(1, 128); $pool.Open()
$jobs = @()
foreach ($t in $targets) {
    $ps = [powershell]::Create().AddScript({
        param($ip, $ports)
        $open = @()
        foreach ($pt in $ports) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($ip, $pt, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(500) -and $tcp.Connected) { $open += $pt }
            try { $tcp.Close() } catch {}
        }
        if ($open.Count -gt 0) { return ($ip + "|" + ($open -join '/')) }
        return $null
    }).AddArgument($t).AddArgument($ports)
    $ps.RunspacePool = $pool
    $jobs += [pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke() }
}
$hits = @()
foreach ($j in $jobs) { $r = $j.Pipe.EndInvoke($j.Handle); if ($r) { $hits += $r }; $j.Pipe.Dispose() }
$pool.Close()

# ARP map
$arp = @{}
Get-NetNeighbor -AddressFamily IPv4 | Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' -and $_.LinkLayerAddress -notmatch '^(FF-FF|01-00-5E)' } | ForEach-Object { $arp[$_.IPAddress] = (($_.LinkLayerAddress -replace '-',':').ToUpper()) }

Write-Output "--- hosts with ANY open port ---"
if ($hits.Count -eq 0) { Write-Output "  (none)" }
foreach ($h in $hits) {
    $p = $h.Split('|'); $ip = $p[0]; $pt = $p[1]
    $mac = if ($arp.ContainsKey($ip)) { $arp[$ip] } else { '-' }
    $x = ''
    if ($mac -match '^00:0A:35') { $x = '  <== XILINX OUI' }
    elseif ($mac -match '^00:26:32|^90:50:1B') { $x = '  <== DIGILENT OUI' }
    elseif ($mac -match '^00:11:43|^00:09:B0') { $x = '  <== possible FPGA vendor' }
    Write-Output ("{0,-16} ports={1,-28} mac={2,-20}{3}" -f $ip, $pt, $mac, $x)
}
