# "Repair" module: the usual repairs (from WinUtil, Optimizer and the forums), each in its own console

$RepairDefs = @(
    @{ Icon = 'first-aid-kit'; Name = 'Reparar archivos de Windows'; Admin = $true; Time = '15 a 30 min'
       Desc = 'DISM repara la imagen del sistema y después SFC sustituye los archivos dañados. La reparación más útil cuando algo falla sin motivo.'
       Run = @('DISM /Online /Cleanup-Image /RestoreHealth', 'sfc /scannow') }
    @{ Icon = 'hard-drive'; Name = 'Comprobar el disco'; Admin = $true; Time = '1 a 5 min'
       Desc = 'Busca errores en el sistema de archivos de C: sin reiniciar. Si encuentra algo, te dirá cómo arreglarlo.'
       Run = @("chkdsk $env:SystemDrive /scan") }
    @{ Icon = 'wifi-x'; Name = 'Restablecer la red'; Admin = $true; Time = '1 min'; Confirm = 'Se reinician Winsock y TCP/IP. Hará falta reiniciar el equipo y puede que tengas que volver a conectarte al Wi-Fi.'
       Desc = 'Para cuando hay conexión pero nada carga, o el ping se ha vuelto loco tras instalar una VPN o un antivirus.'
       Run = @('netsh winsock reset', 'netsh int ip reset', 'ipconfig /flushdns', "Write-Host 'Reinicia el equipo para terminar.' -ForegroundColor Yellow") }
    @{ Icon = 'arrows-counter-clockwise'; Name = 'Restablecer Windows Update'; Admin = $true; Time = '1 min'; Confirm = 'Se paran los servicios de actualización y se renombran sus carpetas de caché. Windows las vuelve a crear.'
       Desc = 'Para actualizaciones que fallan una y otra vez o se quedan atascadas en un porcentaje.'
       Run = @('Stop-Service wuauserv, bits, cryptsvc, msiserver -Force -ErrorAction SilentlyContinue',
               "Remove-Item `"$env:SystemRoot\SoftwareDistribution.old`", `"$env:SystemRoot\System32\catroot2.old`" -Recurse -Force -ErrorAction SilentlyContinue",
               "Rename-Item `"$env:SystemRoot\SoftwareDistribution`" SoftwareDistribution.old -ErrorAction SilentlyContinue",
               "Rename-Item `"$env:SystemRoot\System32\catroot2`" catroot2.old -ErrorAction SilentlyContinue",
               'Start-Service wuauserv, bits, cryptsvc, msiserver -ErrorAction SilentlyContinue',
               "Write-Host 'Listo. Vuelve a buscar actualizaciones.' -ForegroundColor Green") }
    @{ Icon = 'package'; Name = 'Limpiar componentes antiguos'; Admin = $true; Time = '5 a 15 min'
       Desc = 'Borra versiones viejas de componentes que dejan las actualizaciones (WinSxS). Suele liberar varios GB.'
       Run = @('DISM /Online /Cleanup-Image /StartComponentCleanup') }
    @{ Icon = 'storefront'; Name = 'Reparar la Microsoft Store'; Admin = $false; Time = 'segundos'
       Desc = 'Vacía la caché de la Store. Para descargas que no empiezan o juegos de Game Pass que no se instalan.'
       Run = @('wsreset.exe') }
    @{ Icon = 'image'; Name = 'Reconstruir la caché de iconos'; Admin = $false; Time = 'segundos'
       Desc = 'Para iconos en blanco o equivocados en el escritorio y la barra de tareas. El Explorador se reinicia.'
       # Windows restarts Explorer on its own (AutoRestartShell). It isn't started by hand from this console,
       # which may be running as administrator: that would be a whole desktop with administrator rights.
       Run = @('Stop-Process -Name explorer -Force',
               "Remove-Item `"$env:LOCALAPPDATA\IconCache.db`", `"$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db`" -Force -ErrorAction SilentlyContinue",
               'for ($i = 0; $i -lt 40 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 250 }',
               'if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { runas /trustlevel:0x20000 explorer.exe }') }
    @{ Icon = 'battery-warning'; Name = 'Informe de la batería'; Admin = $false; Time = 'segundos'
       Desc = 'Capacidad original frente a la actual y el historial de uso. Para saber si la batería del portátil está gastada.'
       # opened through Explorer so the browser doesn't inherit administrator rights
       Run = @("powercfg /batteryreport /output `"$env:TEMP\bateria.html`"", "explorer.exe `"$env:TEMP\bateria.html`"") }
)

function Start-ConsoleTask([string]$Title, [string[]]$Commands) {
    Add-History 'repair' 'run' "Reparación: $Title"
    $lines = @("`$Host.UI.RawUI.WindowTitle = 'OptiEleven - $Title'", "Write-Host '$Title' -ForegroundColor Cyan", "Write-Host ''") +
             ($Commands | ForEach-Object { "Write-Host '> $($_ -replace "'", "''")' -ForegroundColor DarkGray"; $_ }) +
             @("Write-Host ''", "Write-Host 'Terminado. Pulsa Intro para cerrar.' -ForegroundColor Green", 'Read-Host | Out-Null')
    # the commands are encoded in the call itself: there is no .ps1 on disk that another program could change
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($lines -join "`n")))
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc"
}

function New-RepairPage {
    $root = [Windows.Controls.StackPanel]::new()
    [void]$root.Children.Add((New-Ruled))
    for ($i = 0; $i -lt $RepairDefs.Count; $i++) {
        $d = $RepairDefs[$i]
        $act = [Windows.Controls.StackPanel]::new(); $act.Orientation = 'Horizontal'
        $tm = New-Text $d.Time 13 'Muted'; $tm.VerticalAlignment = 'Center'; $tm.Margin = '0,0,16,0'; $tm.TextWrapping = 'NoWrap'
        $b = New-Btn 'Ejecutar'; $b.Tag = $i
        if ($d.Admin -and -not $script:IsAdmin) { $b.IsEnabled = $false; $b.ToolTip = (T 'Necesita permisos de administrador') }
        $b.Add_Click({
            param($src, $e)
            $def = $RepairDefs[[int]$src.Tag]
            if ($def.Confirm -and [Windows.MessageBox]::Show($window, (T $def.Confirm), (T $def.Name), 'OKCancel', 'Question') -ne 'OK') { return }
            Write-Log "Reparar: $($def.Name)"
            Start-ConsoleTask $def.Name $def.Run
        })
        [void]$act.Children.Add($tm); [void]$act.Children.Add($b)
        [void]$root.Children.Add((New-ActionRow $d.Icon $d.Name $d.Desc $act))
    }
    $root
}
