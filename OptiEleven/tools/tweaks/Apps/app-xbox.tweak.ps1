# app-xbox: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Test   = { param($bk) -not (Get-DebloatPresent $XboxApps) }
           Apply  = { param($bk) Remove-AppList $XboxApps }
           Revert = { param($bk) Write-Log 'Las apps de Xbox se reinstalan desde Microsoft Store (Xbox y Xbox Game Bar).' 'WARN' }
       }
