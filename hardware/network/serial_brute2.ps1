$ErrorActionPreference = 'Continue'

$combos = @(
    @('root','root'),
    @('admin','admin'),
    @('root','admin'),
    @('admin','root'),
    @('root','bitmain'),
    @('root','Bitmain'),
    @('root','antminer'),
    @('root','antMiner'),
    @('root','AntMiner'),
    @('root','ant'),
    @('root','miner'),
    @('root','user'),
    @('root','xilinx'),
    @('root','123456'),
    @('root','1234'),
    @('root','123'),
    @('root','password'),
    @('root','pass'),
    @('root','changeme'),
    @('root','default'),
    @('root','toor'),
    @('root','angstrom'),
    @('root','Angstrom'),
    @('root','ubnt'),
    @('root','zlxx.'),
    @('root','master'),
    @('root','letmein'),
    @('root','abc123'),
    @('root','admin123'),
    @('root','qwerty'),
    @('root','111111'),
    @('root','000000'),
    @('root','888888'),
    @('root','666666'),
    @('root','54321'),
    @('root','88888888'),
    @('root','66666666'),
    @('root','11111111'),
    @('root','00000000'),
    @('root','12345678'),
    @('root','qwerty123'),
    @('root','abcd1234'),
    @('root','test123'),
    @('root','root123'),
    @('root','admin1'),
    @('root','password1'),
    @('root','1q2w3e4r'),
    @('admin','bitmain'),
    @('admin','antminer'),
    @('admin','123456'),
    @('admin','password'),
    @('admin','changeme'),
    @('admin','default'),
    @('miner','miner'),
    @('miner','bitmain'),
    @('user','password'),
    @('user','bitmain'),
    @('guest','guest'),
    @('operator','operator'),
    @('supervisor','supervisor'),
    @('support','support'),
    @('service','service'),
    @('tech','tech'),
    @('maintenance','maintenance'),
    @('root','1234567890'),
    @('root','antminer123'),
    @('root','bitmain2016'),
    @('root','bitmain2017'),
    @('root','bitmain2018'),
    @('root','angstrom2013'),
    @('root','ttyPS0'),
    @('root','oel')
)

Write-Output ("Trying " + $combos.Count + " combos")
$hit = $null
$i = 0
foreach ($c in $combos) {
    $i++
    $u = $c[0]; $p = $c[1]
    $out = powershell.exe -ExecutionPolicy Bypass -File 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/serial_login2.ps1' -User $u -Pass $p 2>&1 | Out-String
    $verdict = ''
    if ($out -match 'RESULT: (\w+)') { $verdict = $Matches[1] }
    Write-Output ("[" + $i + "/" + $combos.Count + "] " + $u + "/" + $p + " -> " + $verdict)
    if ($verdict -eq 'SUCCESS') {
        $hit = $u + "/" + $p
        $out | Out-File -FilePath 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/serial_login_hit.txt' -Encoding utf8
        Write-Output ("### FOUND: " + $hit)
        break
    }
    if ($verdict -eq 'NO_LOGIN_PROMPT') {
        Write-Output "    (no login prompt - maybe locked out or rebooting, continuing)"
    }
    Start-Sleep -Milliseconds 200
}
if (-not $hit) { Write-Output "### NO COMBO WORKED" }
