# Módulo "Espacio en disco": como WinDirStat. Qué carpetas ocupan más (con un clic se baja de nivel) y los archivos más grandes.
# El recorrido lo hace [GP.DiskScan] (C#, en OptiEleven.ps1) en segundo plano; aquí solo se pinta.

$script:DiskCache = @{}   # ruta -> resultado ya analizado, para volver atrás sin esperar otra vez

function Start-DiskScan([string]$Path, [double]$Expected) {
    if ($script:DiskCache.ContainsKey($Path)) { Show-DiskResult $Path; return }
    $script:DiskExpected = $Expected
    $script:DiskWork = Show-Working (T 'Analizando el disco') (T 'Empezando...') { [GP.DiskScan]::Cancel = $true }
    $script:DiskScanPath = $Path
    Start-Bg -Work { param($A) , ([GP.DiskScan]::Scan($A.Root, 30)) } -ArgList @(@{ Root = $Path }) -Progress ([hashtable]::Synchronized(@{})) -OnTick {
        param($P)
        $cur = [GP.DiskScan]::Current; if ($cur.Length -gt 60) { $cur = '...' + $cur.Substring($cur.Length - 57) }
        $script:DiskWork.Detail.Text = (T "$('{0:N0}' -f [GP.DiskScan]::Files) archivos, $(Format-Size ([GP.DiskScan]::Bytes))") + "`n" + $cur
        if ($script:DiskExpected -gt 0) { Set-WorkingProgress $script:DiskWork ([GP.DiskScan]::Bytes / $script:DiskExpected) }
    } -Done {
        param($r)
        Close-Working $script:DiskWork
        if ([GP.DiskScan]::Cancel -or -not $r -or -not $r[0]) { Write-Log 'Análisis del disco cancelado.'; return }
        $script:DiskCache[$script:DiskScanPath] = @{ Folders = @($r[0][0]); Files = @($r[0][1]); Total = [double][GP.DiskScan]::Bytes; Count = [GP.DiskScan]::Files }
        Write-Log "Disco analizado: $($script:DiskScanPath), $(Format-Size ([GP.DiskScan]::Bytes)) en $('{0:N0}' -f [GP.DiskScan]::Files) archivos." 'OK'
        Show-DiskResult $script:DiskScanPath
    }
}

function New-DiskRow([string]$Icon, [string]$Title, [string]$Sub, [double]$Size, [double]$Max, $Action, [string]$Color = 'Cat-Apps') {
    $BgP = [Windows.Controls.Border]::BackgroundProperty
    $row = [Windows.Controls.Border]::new(); $row.Style = $window.FindResource('RuleRow')
    $g = New-Cols @('54', '*', 'Auto', 'Auto')
    [void](Add-At $g (New-IconWell $Icon 40 $Color) 0)
    $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
    $t = New-Text $Title 14.5 'Ink' 'SemiBold'; $t.TextTrimming = 'CharacterEllipsis'; $t.TextWrapping = 'NoWrap'; [void]$sp.Children.Add($t)
    if ($Sub) { $s = New-Text $Sub 12.5 'Muted'; $s.TextTrimming = 'CharacterEllipsis'; $s.TextWrapping = 'NoWrap'; $s.Margin = '0,2,0,0'; [void]$sp.Children.Add($s) }
    $track = [Windows.Controls.Border]::new(); $track.Height = 4; $track.CornerRadius = 2; $track.Margin = '0,8,0,0'; $track.SetResourceReference($BgP, 'Paper3')
    $tg = New-Cols @('*', '*'); $f = if ($Max -gt 0) { [math]::Max([double]0.005, $Size / $Max) } else { [double]0 }
    $tg.ColumnDefinitions[0].Width = [Windows.GridLength]::new($f, 'Star'); $tg.ColumnDefinitions[1].Width = [Windows.GridLength]::new(1 - $f, 'Star')
    $bar = [Windows.Controls.Border]::new(); $bar.CornerRadius = 2; $bar.SetResourceReference($BgP, $Color); [void](Add-At $tg $bar 0)
    $track.Child = $tg; [void]$sp.Children.Add($track)
    [void](Add-At $g $sp 1)
    $pill = [Windows.Controls.Border]::new(); $pill.CornerRadius = 9; $pill.Padding = '10,3,10,4'; $pill.Margin = '16,0,0,0'; $pill.VerticalAlignment = 'Center'; $pill.MinWidth = 86
    $pill.SetResourceReference($BgP, 'Paper3')
    $sz = New-Mono (Format-Size $Size) 13 'Ink'; $sz.FontWeight = 'SemiBold'; $sz.HorizontalAlignment = 'Center'; $pill.Child = $sz
    [void](Add-At $g $pill 2)
    if ($Action) { $Action.Margin = '12,0,0,0'; $Action.VerticalAlignment = 'Center'; [void](Add-At $g $Action 3) }
    $row.Child = $g
    $row
}

function Show-DiskResult([string]$Path) {
    $res = $script:DiskCache[$Path]; $body = $script:DiskBody
    $body.Children.Clear()
    $script:DiskPath = $Path
    # dónde estamos y volver arriba
    $nav = New-Cols @('Auto', '*'); $nav.Margin = '0,6,0,12'
    $parent = Split-Path $Path -Parent
    $up = New-Btn 'Subir'; $up.IsEnabled = [bool]$parent; $up.Margin = '0,0,12,0'; $up.Tag = $parent
    $up.Add_Click({ param($src) Start-DiskScan ([string]$src.Tag) 0 })
    [void](Add-At $nav $up 0)
    $pt = New-Text "$Path  ($(Format-Size $res.Total), $('{0:N0}' -f $res.Count) archivos)" 15 'Ink' 'SemiBold'; $pt.VerticalAlignment = 'Center'; $pt.TextTrimming = 'CharacterEllipsis'; $pt.TextWrapping = 'NoWrap'
    [void](Add-At $nav $pt 1)
    [void]$body.Children.Add($nav)

    [void]$body.Children.Add((New-Section 'Lo que más ocupa'))
    $max = if ($res.Folders) { [double]$res.Folders[0].Size } else { 0 }
    foreach ($it in @($res.Folders | Select-Object -First 25)) {
        if ($it.Size -le 0) { continue }
        $pct = if ($res.Total -gt 0) { '{0:N1} %' -f (100 * $it.Size / $res.Total) } else { '' }
        if ($it.Dir) {
            $open = New-Btn 'Abrir'; $open.Tag = @($it.Path, [double]$it.Size)
            $open.Add_Click({ param($src) Start-DiskScan ([string]$src.Tag[0]) ([double]$src.Tag[1]) })
            [void]$body.Children.Add((New-DiskRow 'folder-open' $it.Name (T "$pct, $('{0:N0}' -f $it.Count) archivos") $it.Size $max $open))
        }
        else { [void]$body.Children.Add((New-DiskRow 'files' (T 'Archivos sueltos en esta carpeta') (T "$pct, $('{0:N0}' -f $it.Count) archivos") $it.Size $max $null 'Cat-Tools')) }
    }

    [void]$body.Children.Add((New-Section 'Archivos más grandes'))
    $fmax = if ($res.Files) { [double]$res.Files[0].Size } else { 0 }
    foreach ($fi in $res.Files) {
        $show = New-Btn 'Mostrar'; $show.Tag = $fi.Path; $show.ToolTip = (T 'Abre la carpeta en el Explorador con el archivo seleccionado')
        $show.Add_Click({ param($src) Start-Process explorer.exe -ArgumentList "/select,`"$($src.Tag)`"" })
        [void]$body.Children.Add((New-DiskRow 'file-text' $fi.Name (Split-Path $fi.Path -Parent) $fi.Size $fmax $show 'Cat-Rendimiento'))
    }
    Start-Stagger @($body.Children) 12
}

function New-DiskPage {
    $BgP = [Windows.Controls.Border]::BackgroundProperty; $BrP = [Windows.Controls.Border]::BorderBrushProperty
    $root = [Windows.Controls.StackPanel]::new()
    $hint = New-Text 'Elige un disco para ver qué carpetas y archivos ocupan más. Con un clic en una carpeta bajas a ver qué hay dentro.' 14 'Muted'
    if (-not $script:IsAdmin) { $hint.Text += ' ' + (T 'Sin administrador, algunas carpetas del sistema no se pueden medir.') }
    $hint.Margin = '0,0,0,14'
    [void]$root.Children.Add($hint)
    # un botón grande por disco, con lo que tiene ocupado
    $grid = [Windows.Controls.Primitives.UniformGrid]::new(); $grid.Columns = 3; $grid.Margin = '0,0,-12,0'
    foreach ($dr in [IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady }) {
        $used = [double]($dr.TotalSize - $dr.TotalFreeSpace)
        $card = [Windows.Controls.Border]::new(); $card.Style = $window.FindResource('Row'); $card.Margin = '0,0,12,12'; $card.Padding = '18,16'; $card.Cursor = 'Hand'
        $card.Tag = @($dr.RootDirectory.FullName, $used)
        $cs = [Windows.Controls.StackPanel]::new()
        $hd = New-Cols @('Auto', '*')
        [void](Add-At $hd (New-IconWell 'hard-drives' 40 'Cat-Apps') 0)
        $ht = [Windows.Controls.StackPanel]::new(); $ht.Margin = '12,0,0,0'; $ht.VerticalAlignment = 'Center'
        $label = if ($dr.VolumeLabel) { "$($dr.Name.TrimEnd('\'))  $($dr.VolumeLabel)" } else { $dr.Name.TrimEnd('\') }
        [void]$ht.Children.Add((New-Text $label 16 'Ink' 'SemiBold'))
        [void]$ht.Children.Add((New-Text (T "$(Format-Size $dr.TotalFreeSpace) libres de $(Format-Size $dr.TotalSize)") 12.5 'Muted'))
        [void](Add-At $hd $ht 1)
        [void]$cs.Children.Add($hd)
        $track = [Windows.Controls.Border]::new(); $track.Height = 6; $track.CornerRadius = 3; $track.Margin = '0,14,0,0'; $track.SetResourceReference($BgP, 'Paper3')
        $tg = New-Cols @('*', '*'); $f = if ($dr.TotalSize) { $used / $dr.TotalSize } else { 0 }
        $tg.ColumnDefinitions[0].Width = [Windows.GridLength]::new($f, 'Star'); $tg.ColumnDefinitions[1].Width = [Windows.GridLength]::new(1 - $f, 'Star')
        $bar = [Windows.Controls.Border]::new(); $bar.CornerRadius = 3; $bar.SetResourceReference($BgP, $(if ($f -gt 0.9) { 'Red' } else { 'AccentGrad' })); [void](Add-At $tg $bar 0)
        $track.Child = $tg; [void]$cs.Children.Add($track)
        $go = New-Text 'Analizar  →' 13 'AccentEdge' 'SemiBold'; $go.Margin = '0,10,0,0'; [void]$cs.Children.Add($go)
        $card.Child = $cs
        $card.Add_MouseLeftButtonUp({ param($src, $e) Start-DiskScan ([string]$src.Tag[0]) ([double]$src.Tag[1]) })
        [void]$grid.Children.Add($card)
    }
    [void]$root.Children.Add($grid)
    $script:DiskBody = [Windows.Controls.StackPanel]::new()
    [void]$root.Children.Add($script:DiskBody)
    if ($script:DiskPath -and $script:DiskCache.ContainsKey($script:DiskPath)) { Show-DiskResult $script:DiskPath }
    $root
}
