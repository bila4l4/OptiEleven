# app-onedrive: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Test   = { param($bk) -not ((Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")) }
           Apply  = { param($bk)
               Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
               $out = & winget uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements --disable-interactivity 2>&1
               if ($LASTEXITCODE -ne 0) {
                   $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
                   if (-not $setup) { throw "winget no pudo desinstalarlo: $($out | Select-Object -Last 1)" }
                   Start-Process $setup -ArgumentList '/uninstall' -Wait
               } }
           Revert = { param($bk) Write-Log 'OneDrive no se reinstala solo: descárgalo de onedrive.com o con "winget install Microsoft.OneDrive".' 'WARN' }
       }
