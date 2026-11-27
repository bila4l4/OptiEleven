# app-phonelink: lo que no cabe en el .json. Devuelve Backup / Test / Apply / Revert / Diff; las funciones que usa están en OptiEleven.ps1.
@{
           Test   = { param($bk) -not (Get-DebloatPresent $PhoneApps) }
           Apply  = { param($bk) Stop-Process -Name PhoneExperienceHost -Force -ErrorAction SilentlyContinue; Remove-AppList $PhoneApps }
           Revert = { param($bk) Write-Log 'Enlace móvil no se reinstala solo: búscalo en Microsoft Store.' 'WARN' }
       }
