# perf-hibernate: lo que no cabe en el .json. Devuelve Backup / Test / Apply / Revert / Diff; las funciones que usa están en OptiEleven.ps1.
@{
           Test   = { param($bk) try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction Stop).HibernateEnabled -eq 0 } catch { $false } }
           Apply  = { param($bk) powercfg /hibernate off | Out-Null }
           Revert = { param($bk) powercfg /hibernate on | Out-Null }
       }
