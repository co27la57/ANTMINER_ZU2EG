param(
  [int]$Baud = 115200,
  [int]$Seconds = 8,
  [string]$Send = "`r`n",
  [string]$Port = 'COM13'
)

$ErrorActionPreference = 'Stop'
$sp = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$sp.ReadTimeout = 300
$sp.Handshake = 'None'
$sp.DtrEnable = $false
$sp.RtsEnable = $false

try {
    $sp.Open()
    Write-Output "OPENED $Port @ $Baud 8N1"
    $sp.DiscardInBuffer()
    $sp.DiscardOutBuffer()

    if ($Send -ne '') {
        $sp.Write($Send)
        Write-Output ("SENT: " + ($Send -replace "`r", '\r' -replace "`n", '\n'))
    }

    $buf = New-Object System.Text.StringBuilder
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        try {
            $data = $sp.ReadExisting()
            if ($data.Length -gt 0) {
                [void]$buf.Append($data)
            }
        } catch {}
        Start-Sleep -Milliseconds 100
    }
    $out = $buf.ToString()
    Write-Output "----- RAW OUTPUT ($($out.Length) chars) -----"
    Write-Output $out
    Write-Output "----- END -----"
}
catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
}
finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
}
