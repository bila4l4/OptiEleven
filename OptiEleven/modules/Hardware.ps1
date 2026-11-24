# Módulo "Equipo": ficha del hardware y del estado de Windows relevante para jugar

function Get-HardwareReport {
    $q = { param($c, $ns) try { if ($ns) { Get-CimInstance -Namespace $ns -ClassName $c -ErrorAction Stop } else { Get-CimInstance $c -ErrorAction Stop } } catch { $null } }
    $os = & $q Win32_OperatingSystem; $cs = & $q Win32_ComputerSystem; $bb = & $q Win32_BaseBoard; $bios = & $q Win32_BIOS
    $cpu = @(& $q Win32_Processor)[0]; $gpus = @(& $q Win32_VideoController); $mem = @(& $q Win32_PhysicalMemory)
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $memTypes = @{ 24 = 'DDR3'; 26 = 'DDR4'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }

    $sections = [ordered]@{}
    $sections['Sistema'] = [ordered]@{
        'Windows'      = "$($os.Caption -replace '^Microsoft ', '') $($cv.DisplayVersion), build $($cv.CurrentBuild).$($cv.UBR)"
        'Equipo'       = "$($cs.Manufacturer) $($cs.Model)".Trim()
        'Placa base'   = "$($bb.Manufacturer) $($bb.Product)".Trim()
        'BIOS / UEFI'  = "$($bios.SMBIOSBIOSVersion.Trim()), $(if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString('dd/MM/yyyy') })"
    }
    $sections['Procesador'] = [ordered]@{
        'Modelo'       = $cpu.Name.Trim()
        'Núcleos'      = "$($cpu.NumberOfCores) núcleos, $($cpu.NumberOfLogicalProcessors) hilos"
        'Frecuencia'   = '{0:N2} GHz base' -f ($cpu.MaxClockSpeed / 1000)
    }
    $g = [ordered]@{}
    foreach ($v in $gpus) {
        $date = if ($v.DriverDate) { $v.DriverDate.ToString('dd/MM/yyyy') } else { '' }
        $g[$v.Name] = "driver $($v.DriverVersion), $date"
    }
    $sections['Gráficos'] = $g
    $total = ($mem | Measure-Object Capacity -Sum).Sum
    $speeds = @($mem | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed } } | Select-Object -Unique)
    $type = @($mem | ForEach-Object { $memTypes[[int]$_.SMBIOSMemoryType] } | Where-Object { $_ } | Select-Object -Unique) -join '/'
    $sections['Memoria'] = [ordered]@{
        'Total'        = '{0:N0} GB {1}' -f ($total / 1GB), $type
        'Velocidad'    = "$($speeds -join ' / ') MT/s"
        'Módulos'      = (($mem | ForEach-Object { '{0:N0} GB' -f ($_.Capacity / 1GB) }) -join ' + ') + "  ($($mem.Count) módulo(s))"
    }
    $d = [ordered]@{}
    $n = 0
    # MSFT_PhysicalDisk por CIM directamente: Get-PhysicalDisk carga el módulo Storage y tarda varios segundos
    $media = @{ 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }; $bus = @{ 1 = 'SCSI'; 3 = 'ATA'; 7 = 'USB'; 8 = 'RAID'; 10 = 'SAS'; 11 = 'SATA'; 12 = 'SD'; 17 = 'NVMe' }
    foreach ($pd in @(& $q MSFT_PhysicalDisk 'root\Microsoft\Windows\Storage')) {
        $n++; $d["Disco $n"] = '{0}, {1:N0} GB, {2}, {3}' -f $pd.FriendlyName, ($pd.Size / 1GB), $(if ($media[[int]$pd.MediaType]) { $media[[int]$pd.MediaType] } else { '?' }), $(if ($bus[[int]$pd.BusType]) { $bus[[int]$pd.BusType] } else { '?' })
    }
    $c = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($c) { $d["Disco del sistema ($env:SystemDrive)"] = '{0:N0} GB libres de {1:N0} GB' -f ($c.Free / 1GB), (($c.Used + $c.Free) / 1GB) }
    $sections['Almacenamiento'] = $d

    $sb = try { if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction Stop).UEFISecureBootEnabled -eq 1) { 'activado' } else { 'desactivado' } } catch { 'no disponible' }
    # sin administrador Windows niega el TPM, pero tarda unos 5 s en decirlo: ni se pregunta
    $tpm = if ($script:IsAdmin) { & $q Win32_Tpm 'root\cimv2\Security\MicrosoftTpm' } else { $null }
    $tpmTxt = if ($tpm) { "versión $(($tpm.SpecVersion -split ',')[0]), $(if ($tpm.IsEnabled_InitialValue) { 'activado' } else { 'desactivado' })" } elseif (-not $script:IsAdmin) { 'abre el panel como admin para verlo' } else { 'no encontrado' }
    $dg = & $q Win32_DeviceGuard 'root\Microsoft\Windows\DeviceGuard'
    $vbs = switch ([int]$dg.VirtualizationBasedSecurityStatus) { 2 { 'activa (resta algo de rendimiento)' } 1 { 'configurada, no en marcha' } default { 'desactivada' } }
    $hags = try { if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction Stop).HwSchMode -eq 2) { 'activada' } else { 'desactivada' } } catch { 'por defecto de Windows' }
    $plan = if ((powercfg /getactivescheme) -match '\((.+)\)') { $Matches[1] } else { '?' }
    $sections['Seguridad y juego'] = [ordered]@{
        'Arranque seguro' = $sb
        'TPM'             = $tpmTxt
        'VBS'             = $vbs
        'GPU por hardware (HAGS)' = $hags
        'Plan de energía' = $plan
    }
    $sections
}

function New-HardwarePage {
    $root = [Windows.Controls.StackPanel]::new()
    $bar = New-Cols @('*', 'Auto'); $bar.Margin = '0,0,0,4'
    $t = New-Text 'Para pedir ayuda en un foro, o comprobar que la RAM va a su velocidad y el driver de la GPU está al día.' 14 'Muted'
    $t.VerticalAlignment = 'Center'; $t.Margin = '0,0,16,0'
    [void](Add-At $bar $t 0)
    $bCopy = New-Btn 'Copiar informe' -Primary
    [void](Add-At $bar $bCopy 1)
    [void]$root.Children.Add($bar)

    $bCopy.IsEnabled = $false
    $bCopy.Add_Click({ [Windows.Clipboard]::SetText($script:HwText); Write-Log 'Informe del equipo copiado al portapapeles.' 'OK' })
    $script:HwBody = [Windows.Controls.StackPanel]::new()
    [void]$script:HwBody.Children.Add((New-Text 'Leyendo el equipo...' 14 'Muted'))
    [void]$root.Children.Add($script:HwBody)
    $script:HwCopy = $bCopy
    # las consultas de WMI tardan uno o dos segundos: en segundo plano, y la ficha se pinta al llegar
    $work = [scriptblock]::Create("param(`$isAdmin)`n`$script:IsAdmin = `$isAdmin`nfunction Get-HardwareReport {`n${function:Get-HardwareReport}`n}`nGet-HardwareReport")
    Start-Bg $work @($script:IsAdmin) { param($r) Show-HardwareReport $r[0] }
    $root
}

function Show-HardwareReport($report) {
    $script:HwBody.Children.Clear()
    if (-not $report) { [void]$script:HwBody.Children.Add((New-Text 'No se pudo leer el equipo.' 14 'Red')); return }
    $script:HwText = ($report.Keys | ForEach-Object {
        $s = $_; "[$s]"; foreach ($k in $report[$s].Keys) { "  ${k}: $($report[$s][$k])" }; ''
    }) -join "`r`n"
    $script:HwCopy.IsEnabled = $true

    $secIcons = @{ 'Sistema' = 'windows-logo'; 'Procesador' = 'cpu'; 'Gráficos' = 'graphics-card'; 'Memoria' = 'memory'; 'Almacenamiento' = 'hard-drives'; 'Seguridad y juego' = 'shield-check' }
    $grid = New-Cols @('*', '*')   # dos columnas; cada par de secciones en su propia fila de altura automática
    $i = 0
    foreach ($sec in $report.Keys) {
        $col = [Windows.Controls.StackPanel]::new()
        $col.Margin = if ($i % 2 -eq 0) { '0,0,20,8' } else { '20,0,0,8' }
        if ($i % 2 -eq 0) { $rd = [Windows.Controls.RowDefinition]::new(); $rd.Height = [Windows.GridLength]::Auto; $grid.RowDefinitions.Add($rd) }
        [Windows.Controls.Grid]::SetRow($col, [math]::Floor($i / 2)); [Windows.Controls.Grid]::SetColumn($col, $i % 2); $i++
        $hh = New-Cols @('30', '*'); $hh.Margin = '0,22,0,10'
        $hi = New-Icon $secIcons[$sec] 21 'Ink2'; [void](Add-At $hh $hi 0)
        $ht = New-Text $sec 19 'Ink' 'SemiBold'; $ht.FontFamily = $window.FindResource('Display'); [void](Add-At $hh $ht 1)
        [void]$col.Children.Add($hh)
        [void]$col.Children.Add((New-Ruled))
        foreach ($k in $report[$sec].Keys) {
            $rowB = [Windows.Controls.Border]::new(); $rowB.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Rule'); $rowB.BorderThickness = '0,0,0,1'; $rowB.Padding = '0,9'
            $row = New-Cols @('150', '*')
            [void](Add-At $row (New-Text $k 13.5 'Muted') 0)
            [void](Add-At $row (New-Text ([string]$report[$sec][$k]) 14 'Ink' 'Medium') 1)
            $rowB.Child = $row
            [void]$col.Children.Add($rowB)
        }
        [void]$grid.Children.Add($col)
    }
    [void]$script:HwBody.Children.Add($grid)
    Start-FadeIn $grid
}