param(
  [Parameter(Mandatory=$true)][string]$LocalFile,
  [Parameter(Mandatory=$true)][string]$RemotePath,
  [string]$Target = '172.25.81.151',
  [string]$User = 'root',
  [string]$Pass = 'admin',
  [string]$HostKey = 'SHA256:fLyd0km1Y7wt1As5WZHCx0rnscvz/JMutaGCn6v9jQU'
)

$ErrorActionPreference = 'Continue'
$base = 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/sshlib'
$pscp = "$base/pscp.exe"
$plink = "$base/plink.exe"

$errf = "$env:TEMP\up_err.txt"; $outf = "$env:TEMP\up_out.txt"

& $pscp -batch -scp -hostkey $HostKey -P 22 -pw $Pass -l $User $LocalFile "${Target}:$RemotePath" 1> $outf 2> $errf
Write-Output ("pscp exit=" + $LASTEXITCODE)
if (Test-Path $errf) { $e = Get-Content $errf -Raw; if ($null -ne $e -and $e.Trim()) { Write-Output ("[pscp stderr] " + $e.Trim()) } }
if (Test-Path $outf) { $o = Get-Content $outf -Raw; if ($null -ne $o -and $o.Trim()) { Write-Output ("[pscp stdout] " + $o.Trim()) } }
if ($LASTEXITCODE -ne 0) { exit 1 }

# run it
$runf = "$env:TEMP\run_out.txt"; $runerr = "$env:TEMP\run_err.txt"
& $plink -ssh -batch -no-antispoof -hostkey $HostKey -P 22 -l $User -pw $Pass $Target "sh $RemotePath" 1> $runf 2> $runerr
Write-Output ("plink exit=" + $LASTEXITCODE)
Write-Output "--- REMOTE OUTPUT ---"
if (Test-Path $runf) { Get-Content $runf }
if (Test-Path $runerr) { $re = Get-Content $runerr -Raw; if ($null -ne $re -and $re.Trim()) { Write-Output ("[stderr] " + $re.Trim()) } }
