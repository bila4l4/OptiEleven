# perf-ultimate: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Backup = { @{ Prev = (Get-ActiveSchemeGuid); Created = $null } }
           Test   = { param($bk) [bool]($bk -and $bk.Custom.Created -and ((Get-ActiveSchemeGuid) -eq $bk.Custom.Created)) }
           Apply  = { param($bk)
               $out = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
               if (-not ("$out" -match '([0-9a-f]{8}-[0-9a-f-]{27})')) { throw "No se pudo crear el plan: $out" }
               $g = $Matches[1]; powercfg /setactive $g | Out-Null; $bk.Custom.Created = $g
               Sync-PowerTweaks }   # the new plan starts with factory values: the applied power tweaks are copied to it
           Revert = { param($bk)
               $prev = '381b4222-f694-41f0-9685-ff5bb260df2e'
               if ($bk -and $bk.Custom.Prev) { $prev = $bk.Custom.Prev }
               powercfg /setactive $prev | Out-Null
               if ($bk -and $bk.Custom.Created) { powercfg /delete $bk.Custom.Created | Out-Null } }
       }
