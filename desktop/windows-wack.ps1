# This probe records the actual SDK/environment result; it never implies Store certification.
param([Parameter(Mandatory=$true)][string]$Arch)
$ErrorActionPreference = 'Stop'
$out = Join-Path (Get-Location) 'dist/evidence'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$report = [ordered]@{ architecture=$Arch; os=[Environment]::OSVersion.VersionString; certification='not-certified'; status='unavailable'; reason=''; exitCode=$null }
$kit = 'C:/Program Files (x86)/Windows Kits/10/App Certification Kit/appcert.exe'
try {
  if (!(Test-Path $kit)) { $report.reason='Windows App Certification Kit is not installed on this runner image.' }
  elseif ((Get-Process -Id $PID).SessionId -eq 0) { $report.reason='Runner is in Session 0; Microsoft requires an active user session for WACK.' }
  else {
    $package = Get-ChildItem "dist/store/$Arch/Synca*.msix" | Select-Object -First 1
    if (!$package) { throw 'No MSIX available for WACK' }
    $reset = Start-Process -FilePath $kit -ArgumentList @('reset') -PassThru -RedirectStandardOutput (Join-Path $out 'wack-reset.log') -RedirectStandardError (Join-Path $out 'wack-reset.stderr.log')
    if (!$reset.WaitForExit(30000)) { $reset.Kill(); throw 'WACK reset did not complete in 30 seconds; an interactive certification session is required.' }
    $xml = Join-Path $out 'wack-report.xml'
    $process = Start-Process -FilePath $kit -ArgumentList @('test','-appxpackagepath',('"'+$package.FullName+'"'),'-reportoutputpath',('"'+$xml+'"')) -PassThru -RedirectStandardOutput (Join-Path $out 'wack.stdout.log') -RedirectStandardError (Join-Path $out 'wack.stderr.log')
    if (!$process.WaitForExit(180000)) { $process.Kill(); $report.status='timeout'; $report.reason='WACK did not finish within three minutes on this CI runner; interactive validation remains required.' }
    else { $process.Refresh(); $report.status='attempted'; $report.exitCode=$process.ExitCode; $report.reason='CI package uses test identity and is unsigned. Inspect XML/logs; this is not a formal Store certification result.' }
  }
} catch { $report.status='error'; $report.reason=$_.Exception.Message }
$report | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $out 'wack-status.json')
$report | ConvertTo-Json
exit 0
