# perf-ultimate: lo que no cabe en el .json. Devuelve Backup / Test / Apply / Revert / Diff; las funciones que usa están en OptiEleven.ps1.
@{
           Backup = { @{ Prev = (Get-ActiveSchemeGuid); Created = $null } }
           Test   = { param($bk) [bool]($bk -and $bk.Custom.Created -and ((Get-ActiveSchemeGuid) -eq $bk.Custom.Created)) }
           Apply  = { param($bk)
               $out = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
               if (-not ("$out" -match '([0-9a-f]{8}-[0-9a-f-]{27})')) { throw "No se pudo crear el plan: $out" }
               $g = $Matches[1]; powercfg /setactive $g | Out-Null; $bk.Custom.Created = $g
               Sync-PowerTweaks }   # el plan nuevo nace con los valores de fábrica: se le copian los ajustes de energía aplicados
           Revert = { param($bk)
               $prev = '381b4222-f694-41f0-9685-ff5bb260df2e'
               if ($bk -and $bk.Custom.Prev) { $prev = $bk.Custom.Prev }
               powercfg /setactive $prev | Out-Null
               if ($bk -and $bk.Custom.Created) { powercfg /delete $bk.Custom.Created | Out-Null } }
       }
