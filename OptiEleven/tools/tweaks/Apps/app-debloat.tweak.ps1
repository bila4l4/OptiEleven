# app-debloat: lo que no cabe en el .json. Devuelve Backup / Test / Apply / Revert / Diff; las funciones que usa están en OptiEleven.ps1.
@{
           Test   = { param($bk) -not (Get-DebloatPresent $DebloatApps) }
           Apply  = { param($bk) Remove-AppList $DebloatApps }
           Revert = { param($bk) Write-Log 'Las apps quitadas no se reinstalan solas: búscalas en Microsoft Store si quieres alguna.' 'WARN' }
       }
