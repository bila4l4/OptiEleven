# Módulo "Espacio en disco": como WinDirStat. Árbol de carpetas desplegable con la proporción de cada una, porcentaje,
# tamaño, archivos y fecha, y a la derecha el reparto por extensión. El recorrido lo hace [GP.DiskScan] (C#, en
# OptiEleven.ps1) en segundo plano; aquí solo se pinta, y cada carpeta crea sus filas al desplegarla.

$script:DiskCache = @{}   # unidad -> resultado ya analizado
$DiskDepthColors = 'Accent', 'Cat-Interfaz', 'Cat-Juegos', 'Cat-Latencia', 'Cat-Privacidad', 'Cat-Rendimiento', 'Cat-Servicios', 'Cat-Apps'
$DiskCols = @('2*', '1*', '62', '78', '70', '78')
$DiskMaxKids = 150   # filas por carpeta al desplegar; el resto en una fila "y N más"

function Start-DiskScan([string]$Root, [double]$Expected) {
    if ($script:DiskCache.ContainsKey($Root)) { Show-DiskResult $Root; return }
    $script:DiskExpected = $Expected; $script:DiskRoot = $Root
    $script:DiskWork = Show-Working (T 'Analizando el disco') (T 'Empezando...') { [GP.DiskScan]::Cancel = $true }
    Start-Bg -Work { param($A) , ([GP.DiskScan]::Scan($A.Root)) } -ArgList @(@{ Root = $Root }) -Progress ([hashtable]::Synchronized(@{})) -OnTick {
        param($P)
        $cur = [GP.DiskScan]::Current; if ($cur.Length -gt 60) { $cur = '...' + $cur.Substring($cur.Length - 57) }
        $script:DiskWork.Detail.Text = (T "$('{0:N0}' -f [GP.DiskScan]::Files) archivos, $(Format-Size ([GP.DiskScan]::Bytes))") + "`n" + $cur
        if ($script:DiskExpected -gt 0) { Set-WorkingProgress $script:DiskWork ([GP.DiskScan]::Bytes / $script:DiskExpected) }
    } -Done {
        param($r)
        Close-Working $script:DiskWork
        if ([GP.DiskScan]::Cancel -or -not $r -or -not $r[0]) { Write-Log 'Análisis del disco cancelado.'; return }
        $script:DiskCache[$script:DiskRoot] = @{ Root = $r[0][0]; Ext = @($r[0][1]) }
        Write-Log "Disco analizado: $($script:DiskRoot), $(Format-Size $r[0][0].Size) en $('{0:N0}' -f $r[0][0].Files) archivos." 'OK'
        Show-DiskResult $script:DiskRoot
    }
}

function New-DiskTreeRow($Node, [int]$Depth, [double]$ParentSize) {
    $BgP = [Windows.Controls.Border]::BackgroundProperty
    $row = [Windows.Controls.Border]::new(); $row.Padding = '6,4,8,4'; $row.CornerRadius = 6; $row.Background = [Windows.Media.Brushes]::Transparent; $row.Cursor = 'Hand'
    $g = New-Cols $DiskCols
    $name = [Windows.Controls.StackPanel]::new(); $name.Orientation = 'Horizontal'
    $sp = [Windows.Controls.Border]::new(); $sp.Width = $Depth * 12; [void]$name.Children.Add($sp)
    $canOpen = -not $Node.IsFile -and $Node.Kids -and $Node.Kids.Count -gt 0
    $chev = New-Text $(if ($canOpen) { '▸' } else { '' }) 13 'Muted'; $chev.Width = 16; $chev.VerticalAlignment = 'Center'; [void]$name.Children.Add($chev)
    $icon = if ($Node.IsRest) { 'files' } elseif ($Node.IsFile) { 'file-text' } else { 'folder-open' }
    $ic = New-Icon $icon 16 $(if ($Node.IsFile) { 'Muted' } else { 'Cat-Latencia' }); $ic.Margin = '0,0,8,0'; [void]$name.Children.Add($ic)
    $label = if ($Node.IsRest) { T "y $('{0:N0}' -f $Node.Files) archivos más" } else { $Node.Name }
    $nt = New-Text $label 13.5 $(if ($Node.IsFile) { 'Ink2' } else { 'Ink' }) $(if ($Node.IsFile) { 'Normal' } else { 'Medium' }); $nt.TextWrapping = 'NoWrap'; $nt.TextTrimming = 'CharacterEllipsis'; $nt.VerticalAlignment = 'Center'
    [void]$name.Children.Add($nt)
    [void](Add-At $g $name 0)
    # proporción frente a la carpeta de arriba, con el color de su nivel (como WinDirStat)
    $f = if ($ParentSize -gt 0) { [math]::Min([double]1, $Node.Size / $ParentSize) } else { [double]1 }
    $track = [Windows.Controls.Border]::new(); $track.Height = 12; $track.CornerRadius = 3; $track.Margin = '0,0,12,0'; $track.VerticalAlignment = 'Center'; $track.SetResourceReference($BgP, 'Paper3')
    $tg = New-Cols @('*', '*'); $tg.ColumnDefinitions[0].Width = [Windows.GridLength]::new($f, 'Star'); $tg.ColumnDefinitions[1].Width = [Windows.GridLength]::new(1 - $f, 'Star')
    $bar = [Windows.Controls.Border]::new(); $bar.CornerRadius = 3; $bar.SetResourceReference($BgP, $DiskDepthColors[$Depth % $DiskDepthColors.Count]); [void](Add-At $tg $bar 0)
    $track.Child = $tg
    [void](Add-At $g $track 1)
    $cells = @(('{0:N1} %' -f (100 * $f)), (Format-Size $Node.Size), ('{0:N0}' -f $Node.Files), $(if ($Node.LastWrite -gt 0) { [DateTime]::FromFileTime($Node.LastWrite).ToString('dd/MM/yy') } else { '' }))
    for ($i = 0; $i -lt 4; $i++) { $c = New-Mono $cells[$i] 12.5 $(if ($i -eq 1) { 'Ink' } else { 'Ink2' }); $c.TextAlignment = 'Right'; $c.VerticalAlignment = 'Center'; [void](Add-At $g $c ($i + 2)) }
    $row.Child = $g
    $row.Tag = @{ Node = $Node; Depth = $Depth; Open = $false; Chev = $chev; CanOpen = $canOpen }
    $row.Add_MouseEnter({ param($s) $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'GlassHi') })
    $row.Add_MouseLeave({ param($s) $s.Background = [Windows.Media.Brushes]::Transparent })
    $row.Add_MouseLeftButtonUp({ param($s, $e) Switch-DiskRow $s })
    $row.Add_MouseLeftButtonDown({   # doble clic: abrir en el Explorador
        param($s, $e)
        if ($e.ClickCount -eq 2) {
            $n = $s.Tag.Node
            if ($n.IsFile -and -not $n.IsRest) { Start-Process explorer.exe -ArgumentList "/select,`"$($n.Parent.Path.TrimEnd('\'))\$($n.Name)`"" }
            elseif (-not $n.IsFile) { Start-Process explorer.exe -ArgumentList "`"$($n.Path)`"" }
            $e.Handled = $true
        }
    })
    $row
}

function Switch-DiskRow($Row) {
    $t = $Row.Tag; if (-not $t.CanOpen) { return }
    $list = $script:DiskRows; $idx = $list.Children.IndexOf($Row)
    if ($t.Open) {
        # plegar: quitar todo lo que cuelga de esta fila
        while ($idx + 1 -lt $list.Children.Count -and $list.Children[$idx + 1].Tag.Depth -gt $t.Depth) { $list.Children.RemoveAt($idx + 1) }
        $t.Open = $false; $t.Chev.Text = '▸'; return
    }
    $kids = $t.Node.Kids; $n = [math]::Min($kids.Count, $DiskMaxKids); $pos = $idx + 1
    for ($i = 0; $i -lt $n; $i++) { $list.Children.Insert($pos, (New-DiskTreeRow $kids[$i] ($t.Depth + 1) $t.Node.Size)); $pos++ }
    if ($kids.Count -gt $DiskMaxKids) {
        $more = New-Text (T "y $($kids.Count - $DiskMaxKids) elementos más pequeños") 12.5 'Muted'; $more.Margin = "$(($t.Depth + 1) * 18 + 40),4,0,4"
        $mb = [Windows.Controls.Border]::new(); $mb.Child = $more; $mb.Tag = @{ Depth = $t.Depth + 1; CanOpen = $false }
        $list.Children.Insert($pos, $mb)
    }
    $t.Open = $true; $t.Chev.Text = '▾'
}

function Show-DiskResult([string]$Root) {
    $res = $script:DiskCache[$Root]; $body = $script:DiskBody
    $body.Children.Clear()
    $BgP = [Windows.Controls.Border]::BackgroundProperty; $BrP = [Windows.Controls.Border]::BorderBrushProperty
    $grid = New-Cols @('*', '250')
    # árbol
    $card = [Windows.Controls.Border]::new(); $card.CornerRadius = 14; $card.Padding = '10,10,10,10'; $card.BorderThickness = 1; $card.Margin = '0,0,14,0'
    $card.SetResourceReference($BgP, 'Glass'); $card.SetResourceReference($BrP, 'GlassEdge')
    $cs = [Windows.Controls.StackPanel]::new()
    $hdr = New-Cols $DiskCols; $hdr.Margin = '6,0,8,6'
    $heads = 'Nombre', 'Proporción', 'Porcentaje', 'Tamaño', 'Archivos', 'Modificado'
    for ($i = 0; $i -lt 6; $i++) { $h = New-Text $heads[$i] 12 'Muted' 'SemiBold'; if ($i -ge 2) { $h.TextAlignment = 'Right' }; [void](Add-At $hdr $h $i) }
    [void]$cs.Children.Add($hdr); [void]$cs.Children.Add((New-Ruled))
    $script:DiskRows = [Windows.Controls.StackPanel]::new()
    [void]$cs.Children.Add($script:DiskRows)
    $card.Child = $cs
    [void](Add-At $grid $card 0)
    # extensiones
    $ec = [Windows.Controls.Border]::new(); $ec.CornerRadius = 14; $ec.Padding = '16,14'; $ec.BorderThickness = 1; $ec.VerticalAlignment = 'Top'
    $ec.SetResourceReference($BgP, 'Glass'); $ec.SetResourceReference($BrP, 'GlassEdge')
    $es = [Windows.Controls.StackPanel]::new()
    $et = New-Text 'Extensiones' 15 'Ink' 'SemiBold'; $et.Margin = '0,0,0,10'; [void]$es.Children.Add($et)
    $total = [double]$res.Root.Size; $i = 0
    foreach ($x in @($res.Ext | Select-Object -First 30)) {
        $r = New-Cols @('16', '*', 'Auto'); $r.Margin = '0,3,0,3'
        $sw = [Windows.Controls.Border]::new(); $sw.Width = 10; $sw.Height = 10; $sw.CornerRadius = 3; $sw.VerticalAlignment = 'Center'
        $sw.SetResourceReference($BgP, $DiskDepthColors[$i % $DiskDepthColors.Count]); [void](Add-At $r $sw 0)
        $nm = New-Text $(if ($x.Ext) { $x.Ext } else { T '(sin extensión)' }) 13 'Ink' 'Medium'; $nm.TextTrimming = 'CharacterEllipsis'; $nm.TextWrapping = 'NoWrap'
        $nm.ToolTip = (T "$('{0:N0}' -f $x.Count) archivos"); [void](Add-At $r $nm 1)
        $sz = New-Mono "$(Format-Size $x.Size)  $('{0,5:N1}' -f (100 * $x.Size / [math]::Max([double]1, $total)))%" 12 'Ink2'; $sz.VerticalAlignment = 'Center'; [void](Add-At $r $sz 2)
        [void]$es.Children.Add($r); $i++
    }
    $ec.Child = $es
    [void](Add-At $grid $ec 1)
    [void]$body.Children.Add($grid)
    # la raíz (la unidad) ya desplegada
    $rootRow = New-DiskTreeRow $res.Root 0 $res.Root.Size
    [void]$script:DiskRows.Children.Add($rootRow)
    Switch-DiskRow $rootRow
    Start-FadeIn $grid 0 8
}

function New-DiskPage {
    $BgP = [Windows.Controls.Border]::BackgroundProperty
    $root = [Windows.Controls.StackPanel]::new()
    $hint = New-Text 'Elige un disco. Pulsa una carpeta para desplegarla y doble clic para abrirla en el Explorador.' 14 'Muted'
    if (-not $script:IsAdmin) { $hint.Text += ' ' + (T 'Sin administrador, algunas carpetas del sistema no se pueden medir.') }
    $hint.Margin = '0,0,0,14'
    [void]$root.Children.Add($hint)
    # un botón grande por disco, con lo que tiene ocupado
    $grid = [Windows.Controls.Primitives.UniformGrid]::new(); $grid.Columns = 3; $grid.Margin = '0,0,-12,4'
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
    if ($script:DiskRoot -and $script:DiskCache.ContainsKey($script:DiskRoot)) { Show-DiskResult $script:DiskRoot }
    $root
}
