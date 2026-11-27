# lat-memcomp: lo que no cabe en el .json. Devuelve Backup / Test / Apply / Revert / Diff; las funciones que usa están en OptiEleven.ps1.
@{
           Test   = { param($bk) try { -not (Get-MMAgent -ErrorAction Stop).MemoryCompression } catch { $null } }
           Apply  = { param($bk) Disable-MMAgent -MemoryCompression -ErrorAction Stop }
           Revert = { param($bk) Enable-MMAgent -MemoryCompression -ErrorAction Stop }
       }
