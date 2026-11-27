# lat-memcomp: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Test   = { param($bk) try { -not (Get-MMAgent -ErrorAction Stop).MemoryCompression } catch { $null } }
           Apply  = { param($bk) Disable-MMAgent -MemoryCompression -ErrorAction Stop }
           Revert = { param($bk) Enable-MMAgent -MemoryCompression -ErrorAction Stop }
       }
