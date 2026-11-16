param(
  [string]$OutFile = 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/board_dump/rootfs.tar',
  [string]$RemoteScript = '/tmp/stream_tar.sh',
  [string]$Target = '172.25.81.151',
  [string]$User = 'root',
  [string]$Pass = 'admin',
  [string]$HostKey = 'SHA256:fLyd0km1Y7wt1As5WZHCx0rnscvz/JMutaGCn6v9jQU'
)

$ErrorActionPreference = 'Continue'
$plink = 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/sshlib/plink.exe'
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $plink
$psi.Arguments = "-ssh -batch -no-antispoof -hostkey $HostKey -P 22 -l $User -pw $Pass $Target `"sh $RemoteScript`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
# set stdout as binary (no encoding translation)
$psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(28591)   # latin1: byte-preserving
$psi.StandardErrorEncoding  = [System.Text.Encoding]::GetEncoding(28591)

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$null = $proc.Start()

$outStream = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
$buf = New-Object byte[] 65536
$total = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while (($n = $proc.StandardOutput.BaseStream.Read($buf, 0, $buf.Length)) -gt 0) {
    $outStream.Write($buf, 0, $n)
    $total += $n
    if ($total % (10*1024*1024) -lt $buf.Length) {
        Write-Output ("  ... {0:N1} MB" -f ($total/1MB))
    }
}
$outStream.Close()
$sw.Stop()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

Write-Output ("exit=" + $proc.ExitCode + " elapsed=" + [int]$sw.Elapsed.TotalSeconds + "s")
Write-Output ("bytes written: " + $total + " (" + [math]::Round($total/1MB,2) + " MB)")
Write-Output ("file size    : " + (Get-Item $OutFile).Length)
if ($stderr.Trim()) { Write-Output ("[stderr] " + $stderr.Trim()) }
