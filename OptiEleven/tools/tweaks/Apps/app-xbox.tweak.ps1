# app-xbox: lo que no cabe en el .json. Devuelve Backup / Test / Apply / Revert / Diff; las funciones que usa están en OptiEleven.ps1.
@{
           Test   = { param($bk) -not (Get-DebloatPresent $XboxApps) }
           Apply  = { param($bk) Remove-AppList $XboxApps }
           Revert = { param($bk) Write-Log 'Las apps de Xbox se reinstalan desde Microsoft Store (Xbox y Xbox Game Bar).' 'WARN' }
       }
