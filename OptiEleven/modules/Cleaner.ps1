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
    @{ Id = 'browsers'; Icon = 'globe'; On = $false; Name = 'Caché de los navegadores'
       Desc = 'Chrome, Edge, Brave, Opera y Firefox. No toca contraseñas, historial ni sesiones; las webs cargan algo más lentas la primera vez.'
       Paths = { $l = $env:LOCALAPPDATA
                 @(foreach ($b in "$l\Google\Chrome\User Data", "$l\Microsoft\Edge\User Data", "$l\BraveSoftware\Brave-Browser\User Data") {
                     foreach ($c in 'Cache\Cache_Data', 'Code Cache', 'GPUCache') { Resolve-Path "$b\*\$c" -ErrorAction SilentlyContinue | ForEach-Object Path } })
                 foreach ($o in "$env:APPDATA\Opera Software\Opera Stable", "$env:APPDATA\Opera Software\Opera GX Stable") { foreach ($c in 'Cache\Cache_Data', 'Code Cache', 'GPUCache') { "$o\$c" } }
                 @(Resolve-Path "$l\Mozilla\Firefox\Profiles\*\cache2" -ErrorAction SilentlyContinue | ForEach-Object Path) } }
    @{ Id = 'appcache'; Icon = 'chat-circle-dots'; On = $false; Name = 'Caché de Discord y Steam'
       Desc = 'Imágenes y webs que Discord y el navegador interno de Steam guardan. Se vuelven a descargar al usarlos.'
       Paths = { foreach ($c in 'Cache\Cache_Data', 'Code Cache', 'GPUCache') { "$env:APPDATA\discord\$c" }
                 "$env:LOCALAPPDATA\Steam\htmlcache"; "${env:ProgramFiles(x86)}\Steam\appcache\httpcache" } }
    @{ Id = 'winlogs'; Icon = 'file-text'; On = $true; Admin = $true; Name = 'Registros de Windows'
       Desc = 'Logs de instalaciones y reparaciones (CBS, DISM). Solo sirven para diagnosticar fallos antiguos.'
       Paths = { @("$env:SystemRoot\Logs\CBS", "$env:SystemRoot\Logs\DISM", "$env:SystemRoot\Logs\WindowsUpdate") } }
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
    $t = 0; $n = 0; $max = 1
    foreach ($r in $script:CleanRows.Values) {
        if ($null -ne $r.Bytes -and $r.Bytes -gt $max) { $max = $r.Bytes }
        if ($r.Switch.IsChecked) { $n++; if ($null -ne $r.Bytes) { $t += $r.Bytes } }
    }
    $script:CleanTotal.Text = Format-Size $t
    $script:CleanCount.Text = T $(if ($script:CleanScanning) { "Analizando... $n de $($script:CleanRows.Count) marcados" } else { "$n de $($script:CleanRows.Count) marcados" })
    $script:CleanBtn.Content.Children[1].Text = T $(if ($t -gt 0) { "Limpiar $(Format-Size $t)" } else { 'Limpiar ahora' })
    $script:CleanBtn.IsEnabled = ($n -gt 0) -and -not $script:Busy
    # barra de cada fila: su tamaño frente al más grande
    foreach ($r in $script:CleanRows.Values) {
        $f = if ($null -ne $r.Bytes -and $r.Bytes -gt 0) { [math]::Max(0.01, $r.Bytes / $max) } else { 0 }
        $r.BarCols[0].Width = [Windows.GridLength]::new($f, 'Star'); $r.BarCols[1].Width = [Windows.GridLength]::new(1 - $f, 'Star')
        $r.Bar.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($r.Switch.IsChecked) { 'Cat-Interfaz' } else { 'RuleStrong' }))
    }
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
        param($A, $P)
        foreach ($j in $A.Jobs) {
            $total = 0
            foreach ($path in $j[1]) {
                try {
                    if (-not (Test-Path -LiteralPath $path)) { continue }
                    $it = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                    if (-not $it.PSIsContainer) { $total += [double]$it.Length; continue }
                    $sum = (Get-ChildItem -LiteralPath $path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                    if ($sum) { $total += [double]$sum }
                } catch {}
            }
            $P[$j[0]] = $total
        }
    } -ArgList @(@{ Jobs = $jobs }) -Progress $progress -OnTick {
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
    $BgP = [Windows.Controls.Border]::BackgroundProperty; $BrP = [Windows.Controls.Border]::BorderBrushProperty

    # cabecera grande, como Boost FPS: cuánto se libera y los botones
    $hero = [Windows.Controls.Border]::new(); $hero.CornerRadius = 14; $hero.Padding = '24,20'; $hero.Margin = '0,0,0,14'; $hero.BorderThickness = 1
    $hero.SetResourceReference($BgP, 'Glass'); $hero.SetResourceReference($BrP, 'GlassEdge')
    $hg = New-Cols @('Auto', '*', 'Auto')
    $hw = [Windows.Controls.Border]::new(); $hw.Width = 64; $hw.Height = 64; $hw.CornerRadius = 14; $hw.VerticalAlignment = 'Center'; $hw.SetResourceReference($BgP, 'Cat-Interfaz')
    $hi = New-Icon 'broom' 34 'AccentInk'; $hi.HorizontalAlignment = 'Center'; $hw.Child = $hi
    [void](Add-At $hg $hw 0)
    $ht = [Windows.Controls.StackPanel]::new(); $ht.Margin = '18,0,18,0'; $ht.VerticalAlignment = 'Center'
    $tl = New-Text 'Se puede liberar' 13.5 'Ink2' 'SemiBold'
    $script:CleanTotal = New-Mono '...' 38 'Ink'; $script:CleanTotal.FontWeight = 'Bold'; $script:CleanTotal.Margin = '0,0,0,0'
    $script:CleanCount = New-Text '' 13 'Muted'
    foreach ($x in $tl, $script:CleanTotal, $script:CleanCount) { [void]$ht.Children.Add($x) }
    [void](Add-At $hg $ht 1)
    $btns = [Windows.Controls.StackPanel]::new(); $btns.Orientation = 'Horizontal'; $btns.VerticalAlignment = 'Center'
    $bAll = New-Btn 'Marcar todo'; $bAll.MinHeight = 46; $bAll.Margin = '0,0,8,0'
    $bScan = New-Btn 'Analizar'; $bScan.MinHeight = 46; $bScan.Margin = '0,0,8,0'
    $script:CleanBtn = New-Btn '' -Primary; $script:CleanBtn.MinHeight = 52; $script:CleanBtn.FontSize = 16; $script:CleanBtn.Padding = '26,0'
    $bc = [Windows.Controls.StackPanel]::new(); $bc.Orientation = 'Horizontal'
    $bi = New-BtnIcon 'broom' 20; $bi.Margin = '0,0,10,0'
    $bl = [Windows.Controls.TextBlock]::new(); $bl.Text = T 'Limpiar ahora'; $bl.VerticalAlignment = 'Center'
    [void]$bc.Children.Add($bi); [void]$bc.Children.Add($bl); $script:CleanBtn.Content = $bc
    if (-not $script:IsAdmin) { $script:CleanBtn.ToolTip = (T 'Sin administrador solo se limpia lo de tu usuario') }
    foreach ($x in $bAll, $bScan, $script:CleanBtn) { [void]$btns.Children.Add($x) }
    [void](Add-At $hg $btns 2)
    $hero.Child = $hg
    [void]$root.Children.Add($hero)
    $script:CleanResult = New-Text '' 13.5 'Cat-Juegos' 'SemiBold'; $script:CleanResult.Margin = '4,0,0,10'; $script:CleanResult.Visibility = 'Collapsed'
    [void]$root.Children.Add($script:CleanResult)

    foreach ($it in $CleanItems) {
        $card = [Windows.Controls.Border]::new()
        $card.Style = $window.FindResource('RuleRow'); $card.Cursor = 'Hand'; $card.Tag = $it.Id
        $g = New-Cols @('54', '*', 'Auto', 'Auto')
        [void](Add-At $g (New-IconWell $it.Icon 40) 0)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
        [void]$sp.Children.Add((New-Text $it.Name 14.5 'Ink' 'SemiBold'))
        $ds = New-Text $it.Desc 13 'Muted'; $ds.Margin = '0,2,0,0'; $ds.MaxWidth = 680; $ds.HorizontalAlignment = 'Left'
        [void]$sp.Children.Add($ds)
        # barra del tamaño relativo
        $track = [Windows.Controls.Border]::new(); $track.Height = 4; $track.CornerRadius = 2; $track.Margin = '0,8,0,0'; $track.HorizontalAlignment = 'Stretch'; $track.SetResourceReference($BgP, 'Paper3')
        $tg = [Windows.Controls.Grid]::new(); $c0 = [Windows.Controls.ColumnDefinition]::new(); $c1 = [Windows.Controls.ColumnDefinition]::new()
        $c0.Width = [Windows.GridLength]::new(0, 'Star'); $c1.Width = [Windows.GridLength]::new(1, 'Star'); $tg.ColumnDefinitions.Add($c0); $tg.ColumnDefinitions.Add($c1)
        $bar = [Windows.Controls.Border]::new(); $bar.CornerRadius = 2; [void](Add-At $tg $bar 0)
        $track.Child = $tg
        [void]$sp.Children.Add($track)
        [void](Add-At $g $sp 1)
        $szB = [Windows.Controls.Border]::new(); $szB.CornerRadius = 9; $szB.Padding = '10,3,10,4'; $szB.Margin = '18,0,0,0'; $szB.VerticalAlignment = 'Center'; $szB.MinWidth = 82
        $szB.SetResourceReference($BgP, 'Paper3')
        $sz = New-Mono '' 13 'Ink'; $sz.FontWeight = 'SemiBold'; $sz.HorizontalAlignment = 'Center'; $szB.Child = $sz
        [void](Add-At $g $szB 2)
        $sw = New-Switch; $sw.Margin = '16,0,0,0'; $sw.IsChecked = $it.On
        [Windows.Automation.AutomationProperties]::SetName($sw, (T $it.Name))
        if ($it.Admin -and -not $script:IsAdmin) { $sw.IsChecked = $false; $sw.IsEnabled = $false }
        $sw.Add_Click({ Update-CleanTotal })
        [void](Add-At $g $sw 3)
        $card.Child = $g
        $card.Add_MouseLeftButtonUp({ param($src, $e) $r = $script:CleanRows[$src.Tag]; if ($r.Switch.IsEnabled) { $r.Switch.IsChecked = -not $r.Switch.IsChecked; Update-CleanTotal } })
        [void]$root.Children.Add($card)
        $script:CleanRows[$it.Id] = @{ Item = $it; Switch = $sw; SizeTb = $sz; Bytes = $null; Bar = $bar; BarCols = @($c0, $c1) }
    }

    $bAll.Add_Click({
        $on = @($script:CleanRows.Values | Where-Object { $_.Switch.IsEnabled -and -not $_.Switch.IsChecked }).Count -gt 0
        foreach ($r in $script:CleanRows.Values) { if ($r.Switch.IsEnabled) { $r.Switch.IsChecked = $on } }
        Update-CleanTotal
    })
    $bScan.Add_Click({ $script:CleanResult.Visibility = 'Collapsed'; Invoke-CleanScan })
    $script:CleanBtn.Add_Click({
        $sel = @($script:CleanRows.Values | Where-Object { $_.Switch.IsChecked })
        if (-not $sel) { return }
        $msg = "Se va a limpiar:`n`n" + (($sel | ForEach-Object { '  - ' + $_.Item.Name }) -join "`n")
        if ($sel | Where-Object { $_.Item.Id -eq 'recycle' }) { $msg += "`n`nLa papelera se vacía para siempre." }
        if ($sel | Where-Object { $_.Item.Id -eq 'browsers' }) { $msg += "`n`nCierra los navegadores antes para limpiar más." }
        if ([Windows.MessageBox]::Show($window, (T $msg), 'OptiEleven', 'OKCancel', 'Question') -ne 'OK') { return }
        Set-Busy $true
        $freed = 0
        try {
            foreach ($r in $sel) {
                Write-Log "Limpiando: $($r.Item.Name)"
                $r.SizeTb.Text = (T '...'); Update-Ui
                $before = if ($null -ne $r.Bytes) { $r.Bytes } else { Get-CleanBytes $r.Item }
                Invoke-CleanItem $r.Item
                $r.Bytes = Get-CleanBytes $r.Item; $r.SizeTb.Text = Format-Size $r.Bytes
                $freed += [math]::Max([double]0, [double]($before - $r.Bytes))
                Update-CleanTotal; Update-Ui
            }
            Write-Log "Limpieza terminada: $(Format-Size $freed) liberados (lo que estaba en uso se queda)." 'OK'
            $script:CleanResult.Text = (T "Liberados $(Format-Size $freed). Lo que estaba en uso se queda y se borrará otro día.")
            $script:CleanResult.Visibility = 'Visible'
        }
        finally { Set-Busy $false; Update-CleanTotal }
    })
    Update-CleanTotal
    $script:CleanFirstScan = $true
    $root
}