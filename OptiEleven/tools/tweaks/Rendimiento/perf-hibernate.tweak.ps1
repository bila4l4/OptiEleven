# perf-hibernate: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Test   = { param($bk) try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction Stop).HibernateEnabled -eq 0 } catch { $false } }
           Apply  = { param($bk) powercfg /hibernate off | Out-Null }
           Revert = { param($bk) powercfg /hibernate on | Out-Null }
       }
