# app-capabilities: lo que no cabe en el .json. Devuelve Backup / Test / Apply / Revert / Diff; las funciones que usa están en OptiEleven.ps1.
@{
           # los archivos pueden seguir ahí hasta reiniciar: la marca evita que se vuelva a lanzar DISM para nada
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
