# Módulo "Limpieza": analiza y borra cachés y temporales (como el limpiador de Optimizer)

$CleanItems = @(
    @{ Id = 'temp-user'; Icon = 'folder-user'; On = $true; Name = 'Temporales de tu usuario'
       Desc = 'Lo que las apps dejan en %TEMP% y no borran.'
       Paths = { @($env:TEMP) } }
    @{ Id = 'temp-win'; Icon = 'folder-dashed'; On = $true; Admin = $true; Name = 'Temporales de Windows'
       Desc = 'La carpeta C:\Windows\Temp.'
       Paths = { @("$env:SystemRoot\Temp") } }
    @{ Id = 'wu'; Icon = 'download'; On = $true; Admin = $true; Name = 'Descargas de Windows Update'
       Desc = 'Instaladores de actualizaciones que ya están aplicadas.'
       Paths = { @("$env:SystemRoot\SoftwareDistribution\Download") }; Services = @('wuauserv', 'bits') }
    @{ Id = 'do'; Icon = 'share-network'; On = $true; Admin = $true; Name = 'Caché de Optimización de distribución'
       Desc = 'Copias de actualizaciones guardadas para compartir con otros equipos.'
       Paths = { @("$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache") }
       Clean = { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { Write-Log "Optimización de distribución: $($_.Exception.Message)" 'WARN' } } }
    @{ Id = 'dumps'; Icon = 'warning-octagon'; On = $true; Admin = $true; Name = 'Volcados e informes de errores'
       Desc = 'Informes de cuelgues de apps y de Windows que nadie va a leer.'
       Paths = { @("$env:LOCALAPPDATA\CrashDumps", "$env:SystemRoot\Minidump", "$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue") } }
    @{ Id = 'shader'; Icon = 'graphics-card'; On = $false; Name = 'Caché de sombreadores de la GPU'
       Desc = 'DirectX, AMD y NVIDIA. Límpiala tras cambiar de driver; la primera partida de cada juego irá a tirones mientras se rehace.'
       Paths = { @("$env:LOCALAPPDATA\D3DSCache", "$env:LOCALAPPDATA\AMD\DxCache", "$env:LOCALAPPDATA\AMD\DxcCache", "$env:LOCALAPPDATA\AMD\VkCache",
                   "$env:LOCALAPPDATA\AMD\GLCache", "$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache") } }
    @{ Id = 'thumbs'; Icon = 'images'; On = $false; Name = 'Miniaturas del Explorador'
       Desc = 'Vistas previas de imágenes y vídeos. Se vuelven a crear al abrir las carpetas.'
       Files = { @(Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | ForEach-Object FullName) } }
    @{ Id = 'recycle'; Icon = 'trash-simple'; On = $false; Name = 'Papelera de reciclaje'
       Desc = 'Se vacía entera. Lo que haya dentro no se podrá recuperar.'
       Size = { $s = 0; try { foreach ($i in (New-Object -ComObject Shell.Application).NameSpace(10).Items()) { $s += [double]$i.Size } } catch {}; $s }
       Clean = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } }
)

function Get-PathBytes([string]$Path) {
    try {   # carpetas de sistema pueden negar el acceso: cuentan como 0
        if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return 0 }
        $it = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $it.PSIsContainer) { return [double]$it.Length }
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($sum) { [double]$sum } else { 0 }
    }
    catch { 0 }
}

function Get-CleanBytes($Item) {
    if ($Item.Size) { return [double](& $Item.Size) }
    $total = 0
    if ($Item.Paths) { foreach ($p in & $Item.Paths) { $total += Get-PathBytes $p } }
    if ($Item.Files) { foreach ($p in & $Item.Files) { $total += Get-PathBytes $p } }
    $total
}

function Invoke-CleanItem($Item) {
    foreach ($svc in @($Item.Services)) { if ($svc) { Stop-Service $svc -Force -ErrorAction SilentlyContinue } }
    try {
        if ($Item.Clean) { & $Item.Clean; return }
        if ($Item.Paths) {
            foreach ($p in & $Item.Paths) {
                if (-not (Test-Path -LiteralPath $p)) { continue }
                $k = 0
                Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop } catch {}   # lo que está en uso se queda
                    if ((++$k % 25) -eq 0) { Update-Ui }
                }
                Update-Ui
            }
        }
        if ($Item.Files) { foreach ($p in & $Item.Files) { try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop } catch {} } }
    }
    finally { foreach ($svc in @($Item.Services)) { if ($svc) { Start-Service $svc -ErrorAction SilentlyContinue } } }
}

function Update-CleanTotal {
    $t = 0
    foreach ($r in $script:CleanRows.Values) { if ($r.Switch.IsChecked -and $null -ne $r.Bytes) { $t += $r.Bytes } }
    $script:CleanTotal.Text = Format-Size $t
}

function Invoke-CleanScan {
    # medir carpetas de varios GB bloqueaba la ventana: el recuento va en segundo plano y cada tamaño aparece al llegar
    if ($script:CleanScanning) { return }
    $script:CleanScanning = $true
    $jobs = @()
    foreach ($r in $script:CleanRows.Values) {
        if ($r.Item.Admin -and -not $script:IsAdmin) { $r.Bytes = $null; $r.SizeTb.Text = (T 'admin'); continue }
        if ($r.Item.Size) { $r.Bytes = Get-CleanBytes $r.Item; $r.SizeTb.Text = Format-Size $r.Bytes; continue }
        $r.SizeTb.Text = (T '...')
        $paths = @(); if ($r.Item.Paths) { $paths += @(& $r.Item.Paths) }; if ($r.Item.Files) { $paths += @(& $r.Item.Files) }
        $jobs += , @($r.Item.Id, $paths)
    }
    Update-CleanTotal
    $progress = [hashtable]::Synchronized(@{})
    Start-Bg -Work {
        param($jobs, $P)
        foreach ($j in $jobs) {
            $total = 0
            foreach ($p in $j[1]) {
                try {
                    if (-not (Test-Path -LiteralPath $p)) { continue }
                    $it = Get-Item -LiteralPath $p -Force -ErrorAction Stop
                    if (-not $it.PSIsContainer) { $total += [double]$it.Length; continue }
                    $sum = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                    if ($sum) { $total += [double]$sum }
                } catch {}
            }
            $P[$j[0]] = $total
        }
    } -ArgList @(, $jobs) -Progress $progress -OnTick {
        param($P)
        foreach ($id in @($P.Keys)) {
            $r = $script:CleanRows[$id]
            if ($r -and $r.SizeTb.Text -ne (Format-Size $P[$id])) { $r.Bytes = $P[$id]; $r.SizeTb.Text = Format-Size $r.Bytes; Update-CleanTotal }
        }
    } -Done { $script:CleanScanning = $false; Update-CleanTotal }
}
function New-CleanerPage {
    $root = [Windows.Controls.StackPanel]::new()
    $script:CleanRows = [ordered]@{}

    $head = New-Cols @('*', 'Auto'); $head.Margin = '0,0,0,18'
    $hs = [Windows.Controls.StackPanel]::new()
    [void]$hs.Children.Add((New-Text 'Se puede liberar con lo marcado' 14 'Muted'))
    $script:CleanTotal = New-Mono '...' 40 'Ink'; $script:CleanTotal.Margin = '0,2,0,0'
    [void]$hs.Children.Add($script:CleanTotal)
    [void](Add-At $head $hs 0)
    $btns = [Windows.Controls.StackPanel]::new(); $btns.Orientation = 'Horizontal'; $btns.VerticalAlignment = 'Bottom'
    $bScan = New-Btn 'Analizar de nuevo'; $bScan.Margin = '0,0,8,0'
    $bClean = New-Btn 'Limpiar lo marcado' -Primary
    if (-not $script:IsAdmin) { $bClean.ToolTip = (T 'Sin administrador solo se limpia lo de tu usuario') }
    [void]$btns.Children.Add($bScan); [void]$btns.Children.Add($bClean)
    [void](Add-At $head $btns 1)
    [void]$root.Children.Add($head)
    [void]$root.Children.Add((New-Ruled))

    foreach ($it in $CleanItems) {
        $card = [Windows.Controls.Border]::new()
        $card.Style = $window.FindResource('RuleRow'); $card.Cursor = 'Hand'; $card.Tag = $it.Id
        $g = New-Cols @('52', '*', 'Auto', 'Auto')
        [void](Add-At $g (New-IconWell $it.Icon) 0)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
        [void]$sp.Children.Add((New-Text $it.Name 15 'Ink' 'Medium'))
        $ds = New-Text $it.Desc 14 'Muted'; $ds.Margin = '0,2,0,0'; $ds.MaxWidth = 640; $ds.HorizontalAlignment = 'Left'
        [void]$sp.Children.Add($ds)
        [void](Add-At $g $sp 1)
        $sz = New-Mono '' 14 'Ink'; $sz.VerticalAlignment = 'Center'; $sz.Margin = '20,0,0,0'; $sz.MinWidth = 84; $sz.TextAlignment = 'Right'
        [void](Add-At $g $sz 2)
        $sw = New-Switch; $sw.Margin = '20,0,0,0'; $sw.IsChecked = $it.On
        [Windows.Automation.AutomationProperties]::SetName($sw, $it.Name)
        if ($it.Admin -and -not $script:IsAdmin) { $sw.IsChecked = $false; $sw.IsEnabled = $false }
        $sw.Add_Click({ Update-CleanTotal })
        [void](Add-At $g $sw 3)
        $card.Child = $g
        $card.Add_MouseLeftButtonUp({ param($src, $e) $r = $script:CleanRows[$src.Tag]; if ($r.Switch.IsEnabled) { $r.Switch.IsChecked = -not $r.Switch.IsChecked; Update-CleanTotal } })
        [void]$root.Children.Add($card)
        $script:CleanRows[$it.Id] = @{ Item = $it; Switch = $sw; SizeTb = $sz; Bytes = $null }
    }

    $bScan.Add_Click({ Invoke-CleanScan })
    $bClean.Add_Click({
        $sel = @($script:CleanRows.Values | Where-Object { $_.Switch.IsChecked })
        if (-not $sel) { return }
        $msg = "Se va a limpiar:`n`n" + (($sel | ForEach-Object { '  - ' + $_.Item.Name }) -join "`n")
        if ($sel | Where-Object { $_.Item.Id -eq 'recycle' }) { $msg += "`n`nLa papelera se vacía para siempre." }
        if ([Windows.MessageBox]::Show($window, (T $msg), 'OptiEleven', 'OKCancel', 'Question') -ne 'OK') { return }
        Set-Busy $true
        $freed = 0
        try {
            foreach ($r in $sel) {
                Write-Log "Limpiando: $($r.Item.Name)"
                $before = if ($null -ne $r.Bytes) { $r.Bytes } else { Get-CleanBytes $r.Item }
                Invoke-CleanItem $r.Item
                $r.Bytes = Get-CleanBytes $r.Item; $r.SizeTb.Text = Format-Size $r.Bytes
                $freed += [math]::Max(0, $before - $r.Bytes)
                Update-CleanTotal; Update-Ui
            }
            Write-Log "Limpieza terminada: $(Format-Size $freed) liberados (lo que estaba en uso se queda)." 'OK'
        }
        finally { Set-Busy $false }
    })
    $script:CleanFirstScan = $true
    $root
}