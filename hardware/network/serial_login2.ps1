param(
  [string]$User = 'root',
  [string]$Pass = 'root',
  [int]$Baud = 115200,
  [int]$TotalTimeout = 90
)

$ErrorActionPreference = 'Stop'
$sp = New-Object System.IO.Ports.SerialPort 'COM13', $Baud, 'None', 8, 'One'
$sp.ReadTimeout = 300
$sp.Handshake = 'None'
$sp.DtrEnable = $false
$sp.RtsEnable = $false

$script:buf = ''
function Pump([int]$ms) {
    try { $d = $sp.ReadExisting(); if ($d.Length -gt 0) { $script:buf += $d } } catch {}
    Start-Sleep -Milliseconds $ms
}
function Read-For([int]$sec) {
    $end = (Get-Date).AddSeconds($sec)
    while ((Get-Date) -lt $end) { Pump 80 }
    $out = $script:buf; $script:buf = ''
    return ($out -replace "`r", '')
}
# wait until one of the patterns shows up (or timeout)
function Wait-For([string]$pattern, [int]$timeoutSec) {
    $end = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $end) {
        Pump 100
        if ($script:buf -match $pattern) { return $true }
    }
    return $false
}

try {
    $sp.Open()
    $sp.DiscardInBuffer(); $sp.DiscardOutBuffer()
    $script:buf = ''

    # 1) wait for the login prompt
    if (-not (Wait-For 'login:' 45)) {
        Write-Output "NO_LOGIN_PROMPT"
        Write-Output ("BUF: " + ($script:buf -replace "`n",' | '))
        return
    }
    $null = Read-For 1

    # 2) send username
    $sp.Write("$User`r")
    $gotPwd = Wait-For 'Password:' 20
    if (-not $gotPwd) {
        Write-Output "NO_PASSWORD_PROMPT"
        Write-Output ("BUF: " + ($script:buf -replace "`n",' | '))
        return
    }
    $null = Read-For 1

    # 3) send password
    $sp.Write("$Pass`r")
    $r2 = Read-For 8

    # 4) marker probe (split so echoed text never contains the literal token)
    $sp.Write("echo __LOGIN""_OK__`r")
    $r3 = Read-For 5

    Write-Output ("PASS_RESP: " + ($r2 -replace "`n",' | '))
    Write-Output ("MARK_RESP: " + ($r3 -replace "`n",' | '))

    $fail = ($r2 -match 'Login incorrect') -or ($r3 -match 'Login incorrect') -or ($r2 -match 'Maximum number of tries')
    $ok   = ($r3 -match '__LOGIN_OK__') -and -not $fail
    if ($ok) { Write-Output "RESULT: SUCCESS" }
    elseif ($fail) { Write-Output "RESULT: FAILED" }
    else { Write-Output "RESULT: UNKNOWN" }
}
catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
}
finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
}
