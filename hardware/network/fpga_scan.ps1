$ErrorActionPreference = 'SilentlyContinue'

# ---- 1. Network config ----
$route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1
$idx   = $route.InterfaceIndex
$addr  = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $idx | Select-Object -First 1
$localIP = $addr.IPAddress
$prefix  = $addr.PrefixLength
$gw      = $route.NextHop

# Scan a /24 around the local IP (cap large subnets)
$scanPrefix = if ($prefix -lt 24) { 24 } else { $prefix }

$ipParts = $localIP.Split('.')
$ipInt   = [uint32]$ipParts[0]*16777216 + [uint32]$ipParts[1]*65536 + [uint32]$ipParts[2]*256 + [uint32]$ipParts[3]
$maskInt = ([uint32]::MaxValue) -shl (32 - $scanPrefix)
$netInt  = $ipInt -band $maskInt
$hostCount = [math]::Pow(2, (32 - $scanPrefix)) - 2

$targets = @()
for ($i = 1; $i -le $hostCount; $i++) {
    $cur = [uint32]($netInt + $i)
    $o3 = [math]::Floor($cur / 16777216); $rem = $cur % 16777216
    $o2 = [math]::Floor($rem / 65536);     $rem = $rem % 65536
    $o1 = [math]::Floor($rem / 256);       $o0 = $rem % 256
    $ip = "$o3.$o2.$o1.$o0"
    if ($ip -eq $localIP -or $ip -eq $gw) { continue }
    $targets += $ip
}

Write-Output ("Local IP : " + $localIP + " (original /" + $prefix + ")")
Write-Output ("Gateway  : " + $gw)
Write-Output ("Scanning : " + $targets.Count + " hosts in /" + $scanPrefix + " (172.25.87.0/24)")
Write-Output ("-" * 64)

# ---- 2. Parallel ping sweep ----
$pool = [runspacefactory]::CreateRunspacePool(1, 64); $pool.Open()
$jobs = @()
foreach ($t in $targets) {
    $ps = [powershell]::Create().AddScript({
        param($ip)
        $p = New-Object System.Net.NetworkInformation.Ping
        try { $r = $p.Send($ip, 400); if ($r.Status -eq 'Success') { return $ip } } catch {}
        return $null
    }).AddArgument($t)
    $ps.RunspacePool = $pool
    $jobs += [pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke() }
}
$pingAlive = @()
foreach ($j in $jobs) { $r = $j.Pipe.EndInvoke($j.Handle); if ($r) { $pingAlive += $r }; $j.Pipe.Dispose() }
$pool.Close()

# ---- 3. Port probe: 3121=Xilinx hw_server, 22=SSH(Zynq), 80/443=web ----
$ports = @(3121, 22, 80, 443)
$pool2 = [runspacefactory]::CreateRunspacePool(1, 64); $pool2.Open()
$pjobs = @()
foreach ($t in $targets) {
    $ps = [powershell]::Create().AddScript({
        param($ip, $ports)
        $open = @()
        foreach ($pt in $ports) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $iar = $tcp.BeginConnect($ip, $pt, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(300) -and $tcp.Connected) { $open += $pt }
            try { $tcp.Close() } catch {}
        }
        if ($open.Count -gt 0) { return ($ip + "|" + ($open -join ',')) }
        return $null
    }).AddArgument($t).AddArgument($ports)
    $ps.RunspacePool = $pool2
    $pjobs += [pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke() }
}
$portMap = @{}
foreach ($j in $pjobs) { $r = $j.Pipe.EndInvoke($j.Handle); if ($r) { $p=$r.Split('|'); $portMap[$p[0]] = $p[1].Split(',') }; $j.Pipe.Dispose() }
$pool2.Close()

# ---- 4. ARP table for MAC ----
$arp = @{}
Get-NetNeighbor -InterfaceIndex $idx -AddressFamily IPv4 | Where-Object { $_.LinkLayerAddress } | ForEach-Object { $arp[$_.IPAddress] = $_.LinkLayerAddress }

# known FPGA / dev-board vendor OUIs (best-effort)
$vendors = @{
    '00:26:32' = 'Digilent';
    '90:50:1b' = 'Digilent';
    '00:0a:35' = 'Xilinx';
    '00:07:ed' = 'Altera/Intel(possibly)';
    '00:11:43' = 'Terasic(possibly)';
}
function Vendor($mac) {
    if (-not $mac) { return '' }
    $m = $mac.ToLower()
    foreach ($k in $vendors.Keys) { if ($m.StartsWith($k)) { return $vendors[$k] } }
    return ''
}

# ---- 5. Candidate hosts = ping-alive UNION port-found ----
$candidates = @($pingAlive) + @($portMap.Keys) | Sort-Object -Unique

# reverse DNS for candidates (bounded timeout)
$pool3 = [runspacefactory]::CreateRunspacePool(1, 32); $pool3.Open()
$hjobs = @()
foreach ($c in $candidates) {
    $ps = [powershell]::Create().AddScript({
        param($ip)
        try {
            $ias = [System.Net.Dns]::BeginGetHostEntry($ip, $null, $null)
            if ($ias.AsyncWaitHandle.WaitOne(600)) {
                $h = [System.Net.Dns]::EndGetHostEntry($ias)
                if ($h.HostName -and $h.HostName -ne $ip) { return ($ip + "|" + $h.HostName) }
            }
        } catch {}
        return ($ip + "|")
    }).AddArgument($c)
    $ps.RunspacePool = $pool3
    $hjobs += [pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke() }
}
$hostMap = @{}
foreach ($j in $hjobs) { $r = $j.Pipe.EndInvoke($j.Handle); $p=$r.Split('|'); $hostMap[$p[0]] = $p[1]; $j.Pipe.Dispose() }
$pool3.Close()

# ---- 6. Report ----
Write-Output ("Ping-alive hosts : " + $pingAlive.Count)
Write-Output ("Hosts w/ FPGA-ish ports (3121/22/80/443): " + $portMap.Count)
Write-Output ("-" * 64)

if ($candidates.Count -eq 0) {
    Write-Output "No responding hosts found on this segment (ICMP/ports filtered or segment quiet)."
} else {
    Write-Output ("{0,-16} {1,-28} {2,-18} {3}" -f "IP", "HOSTNAME", "MAC", "PORTS / VENDOR")
    Write-Output ("-" * 64)
    foreach ($c in $candidates) {
        $mac = if ($arp.ContainsKey($c)) { $arp[$c] } else { '' }
        $ven = Vendor $mac
        $pt  = if ($portMap.ContainsKey($c)) { ($portMap[$c] -join '/') } else { '-' }
        $hn  = if ($hostMap.ContainsKey($c) -and $hostMap[$c]) { $hostMap[$c] } else { '-' }
        Write-Output ("{0,-16} {1,-28} {2,-18} {3} {4}" -f $c, $hn, $mac, $pt, $ven)
    }
}

# ---- 7. FPGA likelihood highlight ----
Write-Output ("-" * 64)
Write-Output "FPGA-likely hosts:"
$fpgaHit = $false
foreach ($c in $candidates) {
    $pt = if ($portMap.ContainsKey($c)) { $portMap[$c] } else { @() }
    $hn = if ($hostMap.ContainsKey($c)) { $hostMap[$c].ToLower() } else { '' }
    $ven = Vendor (if ($arp.ContainsKey($c)) { $arp[$c] } else { '' })
    $why = @()
    if ($pt -contains '3121') { $why += "Xilinx Vivado hw_server (port 3121)" }
    if ($pt -contains '22')   { $why += "SSH open (Zynq/embedded-Linux board candidate)" }
    if ($ven -match 'Digilent|Xilinx|Altera|Terasic') { $why += ("MAC vendor=" + $ven) }
    if ($hn -match 'zybo|zed|zynq|pynq|arty|de1|de10|fpga|avnet|terasic') { $why += ("hostname=" + $hn) }
    if ($why.Count -gt 0) {
        $fpgaHit = $true
        Write-Output ("  -> " + $c + "  [" + ($why -join "; ") + "]")
    }
}
if (-not $fpgaHit) {
    Write-Output "  None strongly matched. (port 3121 / SSH / known board vendor / board-like hostname all absent)"
}
Write-Output ("-" * 64)
Write-Output "Note: MAC vendor table is best-effort; absence of a vendor tag does NOT rule out an FPGA board."
