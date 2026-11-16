$ErrorActionPreference = 'Continue'

$combos = @(
    @('root','root'),
    @('admin','admin'),
    @('root','admin'),
    @('admin','root'),
    @('root',''),
    @('root','bitmain'),
    @('root','antminer'),
    @('root','antMiner'),
    @('root','AntMiner'),
    @('root','123456'),
    @('root','1234'),
    @('root','xilinx'),
    @('root','password'),
    @('root','miner'),
    @('root','user'),
    @('user','user'),
    @('root','changeme'),
    @('root','default'),
    @('root','toor'),
    @('root','angstrom'),
    @('root','Angstrom'),
    @('root','AntMiner'),
    @('root','bitmain123'),
    @('root','1'),
    @('root','1111'),
    @('root','pass'),
    @('root','test'),
    @('root','ubnt'),
    @('root','zlxx.')
)

foreach ($c in $combos) {
    $u = $c[0]; $p = $c[1]
    Write-Output ("=========== TRY " + $u + " / '" + $p + "' ===========")
    $out = powershell.exe -ExecutionPolicy Bypass -File 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/serial_login.ps1' -User $u -Pass $p 2>&1 | Out-String
    # print only the verdict + short resp
    $lines = $out -split "`r?`n"
    foreach ($l in $lines) {
        if ($l -match '^(USER_RESP|PASS_RESP|RESULT|ERROR)') { Write-Output ("   " + $l.Trim()) }
    }
    if ($out -match 'RESULT: SUCCESS') {
        Write-Output ("### FOUND: " + $u + " / " + $p)
        $out | Out-File -FilePath 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/serial_login_hit.txt' -Encoding utf8
        break
    }
    Start-Sleep -Milliseconds 300
}
Write-Output "=========== BATCH DONE ==========="
