$ErrorActionPreference = 'SilentlyContinue'

# Collect all hosts we know exist on the L2 segment (ARP resolved => device present)
$arpHosts = @{}
Get-NetNeighbor -AddressFamily IPv4 | Where-Object {
    $_.IPAddress -match '^172\.25\.' -and $_.LinkLayerAddress -and
    $_.LinkLayerAddress -ne '00-00-00-00-00-00' -and $_.LinkLayerAddress -notmatch '^(FF-FF|01-00-5E)'
} | ForEach-Object { $arpHosts[$_.IPAddress] = (($_.LinkLayerAddress -replace '-',':').ToUpper() + "  [" + $_.State + "]") }

Write-Output ("ARP-known hosts: " + $arpHosts.Count)

# wide port fingerprint on every ARP-known host
$ports = @(22,23,80,443,1080,3121,3333,4444,5000,7547,8080,8443,9090,9999,10000,37215)

foreach ($ip in ($arpHosts.Keys | Sort-Object)) {
    $open = @()
    $banners = @()
    foreach ($pt in $ports) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($ip, $pt, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(700) -and $tcp.Connected) {
            $open += $pt
            # grab a short banner
            try {
                $tcp.ReceiveTimeout = 900
                $stream = $tcp.GetStream()
                if ($pt -eq 22) {
                    $buf = New-Object byte[] 128
                    $n = $stream.Read($buf, 0, 128)
                    if ($n -gt 0) { $banners += ("ssh=" + [System.Text.Encoding]::ASCII.GetString($buf,0,$n).Trim()) }
                } elseif ($pt -eq 80 -or $pt -eq 443) {
                    $req = "GET / HTTP/1.0`r`nHost: $ip`r`n`r`n"
                    $b = [System.Text.Encoding]::ASCII.GetBytes($req)
                    $stream.Write($b, 0, $b.Length)
                    $stream.Flush()
                    $buf = New-Object byte[] 300
                    $n = $stream.Read($buf, 0, 300)
                    if ($n -gt 0) {
                        $txt = [System.Text.Encoding]::ASCII.GetString($buf,0,$n) -replace "`r?`n",' '
                        if ($txt -match 'Server:\s*([^\r\n]+)') { $banners += ("srv=" + $Matches[1].Trim()) }
                        elseif ($txt -match '<title>([^<]+)</title>') { $banners += ("title=" + $Matches[1].Trim()) }
                    }
                } else {
                    $buf = New-Object byte[] 128
                    $n = $stream.Read($buf, 0, 128)
                    if ($n -gt 0) { $banners += ("p$pt=" + (([System.Text.Encoding]::ASCII.GetString($buf,0,$n)) -replace "`r?`n",' ').Trim()) }
                }
            } catch {}
        }
        try { $tcp.Close() } catch {}
    }

    # reverse dns
    $hn = ''
    try { $ias=[System.Net.Dns]::BeginGetHostEntry($ip,$null,$null); if($ias.AsyncWaitHandle.WaitOne(900)){ $hh=[System.Net.Dns]::EndGetHostEntry($ias); $hn=$hh.HostName } } catch {}

    Write-Output ("{0,-16} {1,-34} ports={2,-22} host={3}" -f $ip, $arpHosts[$ip], $(if($open.Count){($open -join '/')}else{'-'}), $hn)
    foreach ($b in $banners) { Write-Output ("      -> " + $b) }
}
