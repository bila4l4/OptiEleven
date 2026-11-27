# app-phonelink: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Test   = { param($bk) -not (Get-DebloatPresent $PhoneApps) }
           Apply  = { param($bk) Stop-Process -Name PhoneExperienceHost -Force -ErrorAction SilentlyContinue; Remove-AppList $PhoneApps }
           Revert = { param($bk) Write-Log 'Enlace móvil no se reinstala solo: búscalo en Microsoft Store.' 'WARN' }
       }
