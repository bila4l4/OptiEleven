# perf-powermode: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Backup = { @{ Prev = (Get-OverlayGuid) } }
           Test   = { param($bk) (Get-OverlayGuid) -eq 'ded574b5-45a0-4f42-8737-46345c09c238' }
           Apply  = { param($bk) Set-OverlayGuid 'ded574b5-45a0-4f42-8737-46345c09c238' }
           Revert = { param($bk) $g = '00000000-0000-0000-0000-000000000000'; if ($bk -and $bk.Custom.Prev) { $g = $bk.Custom.Prev }; Set-OverlayGuid $g }
       }
