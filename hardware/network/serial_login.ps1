param(
  [string]$User = 'root',
  [string]$Pass = 'root',
  [int]$Baud = 115200,
  [int]$WaitSec = 6
)

$ErrorActionPreference = 'Stop'
$sp = New-Object System.IO.Ports.SerialPort 'COM13', $Baud, 'None', 8, 'One'
$sp.ReadTimeout = 300
$sp.Handshake = 'None'
$sp.DtrEnable = $false
$sp.RtsEnable = $false

function Read-For([int]$sec) {
    $b = New-Object System.Text.StringBuilder
    $end = (Get-Date).AddSeconds($sec)
    while ((Get-Date) -lt $end) {
        try { $d = $sp.ReadExisting(); if ($d.Length -gt 0) { [void]$b.Append($d) } } catch {}
        Start-Sleep -Milliseconds 80
    }
    return ($b.ToString() -replace "`r", '' -replace "`n", ' | ')
}

try {
    $sp.Open()
    $sp.DiscardInBuffer()
    $null = Read-For 1

    $sp.Write("$User`r")
    $r1 = Read-For 3

    $sp.Write("$Pass`r")
    $r2 = Read-For $WaitSec

    # marker split so the echoed command text does NOT contain the literal token
    $sp.Write("echo __LOGIN""_OK__`r")
    $r3 = Read-For 4

    Write-Output ("USER_RESP: " + $r1)
    Write-Output ("PASS_RESP: " + $r2)
    Write-Output ("MARK_RESP: " + $r3)

    $fail = ($r2 -match 'Login incorrect') -or ($r2 -match 'Login incorrect') -or ($r3 -match 'Login incorrect')
    $ok   = ($r3 -match '__LOGIN_OK__') -and -not $fail

    if ($ok) { Write-Output "RESULT: SUCCESS" }
    else {
        if ($fail) { Write-Output "RESULT: FAILED (login incorrect)" }
        else { Write-Output "RESULT: FAILED (no marker)" }
    }
}
catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
}
finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
}
