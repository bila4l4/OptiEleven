# app-capabilities: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           # the files may stay there until a restart: the marker avoids running DISM again for nothing
           Test   = { param($bk) (Test-Path (Join-Path $script:Secure 'capabilities.done')) -or -not ($OldCapabilities | Where-Object { Test-Path $_.File }) }
           Apply  = { param($bk)
               $caps = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object State -eq 'Installed')
               foreach ($oc in $OldCapabilities) {
                   foreach ($c in $caps | Where-Object Name -like $oc.Cap) {
                       try { Remove-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null; Write-Log "  quitado: $($c.Name)" }
                       catch { Write-Log "  no se pudo quitar $($c.Name): $($_.Exception.Message)" 'WARN' }
                   }
               }
               Set-Content -LiteralPath (Join-Path $script:Secure 'capabilities.done') -Value (Get-Date).ToString('s') }
           Revert = { param($bk) Write-Log 'Los componentes se vuelven a añadir en Configuración > Sistema > Características opcionales.' 'WARN' }
       }
