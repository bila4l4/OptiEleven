# app-debloat: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Test   = { param($bk) -not (Get-DebloatPresent $DebloatApps) }
           Apply  = { param($bk) Remove-AppList $DebloatApps }
           Revert = { param($bk) Write-Log 'Las apps quitadas no se reinstalan solas: búscalas en Microsoft Store si quieres alguna.' 'WARN' }
       }
