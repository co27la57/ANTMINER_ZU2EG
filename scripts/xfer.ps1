param(
  [Parameter(Mandatory=$true)][string]$LocalFile,
  [Parameter(Mandatory=$true)][string]$RemotePath,
  [string]$Target = '172.25.81.151',
  [string]$User = 'root',
  [string]$Pass = 'admin',
  [string]$HostKey = 'SHA256:fLyd0km1Y7wt1As5WZHCx0rnscvz/JMutaGCn6v9jQU',
  [string]$Mode = 'upload'
)

$ErrorActionPreference = 'Continue'
$plink = 'C:/Users/Administrator/WorkBuddy/2026-11-12-01-26-33/sshlib/plink.exe'

if ($Mode -eq 'download') {
    # remote -> local : plink stdout -> local file
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $plink
    $psi.Arguments = "-ssh -batch -no-antispoof -hostkey $HostKey -P 22 -l $User -pw $Pass $Target `"cat $RemotePath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(28591)
    $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding(28591)
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $fs = [System.IO.File]::Open($LocalFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    $buf = New-Object byte[] 262144
    $total = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (($n = $proc.StandardOutput.BaseStream.Read($buf, 0, $buf.Length)) -gt 0) {
        $fs.Write($buf, 0, $n); $total += $n
        if ($total % (20*1024*1024) -lt $buf.Length) { Write-Output ("  ... {0:N0} MB" -f ($total/1MB)) }
    }
    $fs.Close(); $sw.Stop()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    Write-Output ("downloaded {0:N1} MB in {1}s -> {2}" -f ($total/1MB), [int]$sw.Elapsed.TotalSeconds, $LocalFile)
    if ($err.Trim()) { Write-Output ("[stderr] " + $err.Trim()) }
}
else {
    # local -> remote : local file is the STDIN of the remote command
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $plink
    $psi.Arguments = "-ssh -batch -no-antispoof -hostkey $HostKey -P 22 -l $User -pw $Pass $Target `"cat > $RemotePath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::GetEncoding(28591)
    $psi.StandardErrorEncoding = [System.Text.Encoding]::GetEncoding(28591)
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $src = [System.IO.File]::OpenRead($LocalFile)
    $buf = New-Object byte[] 262144
    $total = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (($n = $src.Read($buf, 0, $buf.Length)) -gt 0) {
        $proc.StandardInput.BaseStream.Write($buf, 0, $n); $total += $n
        if ($total % (20*1024*1024) -lt $buf.Length) { Write-Output ("  ... {0:N0} MB" -f ($total/1MB)) }
    }
    $src.Close()
    $proc.StandardInput.Close()
    $sw.Stop()
    $err = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    Write-Output ("uploaded {0:N1} MB in {1}s -> {2} (exit={3})" -f ($total/1MB), [int]$sw.Elapsed.TotalSeconds, $RemotePath, $proc.ExitCode)
    if ($err.Trim()) { Write-Output ("[stderr] " + $err.Trim()) }
}
