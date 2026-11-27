# app-edge: what doesn't fit in the .json. Returns Backup / Test / Apply / Revert / Diff; the functions it uses are in OptiEleven.ps1.
@{
           Test   = { param($bk) -not ((Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") -or (Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) }
           Apply  = { param($bk)
               $setup = Get-EdgeSetup
               if (-not $setup) { throw 'No encuentro el desinstalador de Edge (setup.exe).' }
               Set-RegValue 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1 'DWord'
               Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue
               $p = Start-Process $setup.FullName -ArgumentList '--uninstall --system-level --verbose-logging --force-uninstall' -Wait -PassThru
               if (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") { throw "Windows no ha dejado desinstalar Edge (código $($p.ExitCode)). Desde Configuración > Aplicaciones puedes intentarlo si estás en la UE." } }
           Revert = { param($bk) Remove-RegValue 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium'; Write-Log 'Edge se reinstala desde microsoft.com/edge o con "winget install Microsoft.Edge".' 'WARN' }
       }
