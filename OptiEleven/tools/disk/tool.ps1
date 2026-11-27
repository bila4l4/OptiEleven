# "Disk space" module: like WinDirStat. Expandable folder tree with each folder's share, percentage,
# size, files and date, and on the right the breakdown by extension. The scan is done by [GP.DiskScan] (C#, in
# OptiEleven.ps1) in the background; this file only draws, and each folder creates its rows when expanded.

$script:DiskCache = @{}   # drive -> result already scanned
$DiskDepthColors = 'Accent', 'Cat-Interfaz', 'Cat-Juegos', 'Cat-Latencia', 'Cat-Privacidad', 'Cat-Rendimiento', 'Cat-Servicios', 'Cat-Apps'
$DiskCols = @('2*', '1*', '62', '78', '70', '78')
$DiskMaxKids = 150   # rows per folder when expanded; the rest in one "and N more" row

function Start-DiskScan([string]$Root, [double]$Expected) {
    if ($script:DiskCache.ContainsKey($Root)) { $script:DiskRoot = $Root; Show-DiskResult $Root; return }
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
    # a Grid (not a StackPanel) so a long name gets cut with "…" instead of running under the bar
    $name = New-Cols @("$($Depth * 12)", '16', '24', '*'); $name.Margin = '0,0,10,0'
    $canOpen = -not $Node.IsFile -and $Node.Kids -and $Node.Kids.Count -gt 0
    $chev = New-Text $(if ($canOpen) { '▸' } else { '' }) 13 'Muted'; $chev.VerticalAlignment = 'Center'; [void](Add-At $name $chev 1)
    $icon = if ($Node.IsRest) { 'files' } elseif ($Node.IsFile) { 'file-text' } else { 'folder-open' }
    $ic = New-Icon $icon 16 $(if ($Node.IsFile) { 'Muted' } else { 'Cat-Latencia' }); $ic.VerticalAlignment = 'Center'; [void](Add-At $name $ic 2)
    $label = if ($Node.IsRest) { T "y $('{0:N0}' -f $Node.Files) archivos más" } else { $Node.Name }
    $nt = New-Text $label 13.5 $(if ($Node.IsFile) { 'Ink2' } else { 'Ink' }) $(if ($Node.IsFile) { 'Normal' } else { 'Medium' }); $nt.TextWrapping = 'NoWrap'; $nt.TextTrimming = 'CharacterEllipsis'; $nt.VerticalAlignment = 'Center'
    if (-not $Node.IsRest) { $nt.ToolTip = Get-DiskPath $Node }
    [void](Add-At $name $nt 3)
    [void](Add-At $g $name 0)
    # share of the parent folder, in its level's color (like WinDirStat)
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
    $row.Add_MouseEnter({ param($s) if (@($script:DiskSel) -notcontains $s) { $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'GlassHi') } })
    $row.Add_MouseLeave({ param($s) if (@($script:DiskSel) -notcontains $s) { $s.Background = [Windows.Media.Brushes]::Transparent } })
    $row.Add_MouseLeftButtonUp({ param($s, $e) if (-not (Select-DiskRow $s)) { Switch-DiskRow $s } })   # with Ctrl/Shift it only selects, it doesn't expand
    # right click: the WinDirStat menu (filled when opened, so 150 menus aren't created at once)
    if (-not $Node.IsRest) { $row.ContextMenu = [Windows.Controls.ContextMenu]::new(); $row.Add_ContextMenuOpening({ param($s, $e) Fill-DiskMenu $s }) }
    $row.Add_MouseLeftButtonDown({   # double click: open in Explorer
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

function Get-DiskPath($Node) {
    if ($Node.IsFile) { "$($Node.Parent.Path.TrimEnd('\'))\$($Node.Name)" } else { $Node.Path }
}

# what is never deleted from here: the whole drive and the folders Windows depends on
function Test-DiskDeletable($Node) {
    if ($Node.IsRest -or -not $Node.Parent) { return $false }
    $p = (Get-DiskPath $Node).TrimEnd('\')
    $deny = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE, (Split-Path $env:USERPROFILE),
        "$env:SystemDrive\Recovery", "$env:SystemDrive\Boot", "$env:SystemDrive\System Volume Information", "$env:SystemDrive\`$Recycle.Bin") | Where-Object { $_ }
    if (@($deny | Where-Object { $p -eq $_.TrimEnd('\') }).Count -or $p -like "$env:windir\*") { return $false }
    $true
}

# the same actions in the right-click menu and in the bar above the tree
$DiskActions = @(@('open', 'Abrir', 'play-circle'), @('show', 'Mostrar en el Explorador', 'folder-open'), @('copy', 'Copiar ruta', 'copy'),
    @('term', 'Abrir terminal aquí', 'terminal-window'), @('props', 'Propiedades', 'list-dashes'), '-', @('rescan', 'Volver a analizar', 'arrows-clockwise'), '-',
    @('recycle', 'Mover a la papelera', 'trash-simple'), @('delete', 'Eliminar para siempre', 'warning-octagon'))

function Test-DiskAction($Nodes, [string]$Act) {
    $Nodes = @($Nodes)
    if (-not $Nodes.Count -or @($Nodes | Where-Object { $_.IsRest }).Count) { return $false }
    if ($Act -in 'open', 'show', 'term', 'props', 'rescan' -and $Nodes.Count -gt 1) { return $false }   # these, one at a time
    if ($Act -eq 'rescan') { return -not $Nodes[0].IsFile }
    if ($Act -in 'recycle', 'delete') { return -not @($Nodes | Where-Object { -not (Test-DiskDeletable $_) }).Count }
    $true
}

function Get-DiskSelNodes { @($script:DiskSel | ForEach-Object { $_.Tag.Node }) }

# highlights the selected rows (like WinDirStat) and enables the buttons that apply to them
function Set-DiskSelection($Rows) {
    $BgP = [Windows.Controls.Border]::BackgroundProperty
    $Rows = @($Rows | Where-Object { $_ -and $_.Tag.Node -and -not $_.Tag.Node.IsRest })
    foreach ($r in @($script:DiskSel)) { if ($Rows -notcontains $r) { $r.Background = [Windows.Media.Brushes]::Transparent } }
    $script:DiskSel = $Rows
    foreach ($r in $Rows) { $r.SetResourceReference($BgP, 'AccentSoft') }
    $nodes = Get-DiskSelNodes
    foreach ($b in $script:DiskTools) { $b.IsEnabled = Test-DiskAction $nodes $b.Tag }
    if ($script:DiskSelText) {
        $script:DiskSelText.Text = if ($nodes.Count -eq 1) { Get-DiskPath $nodes[0] }
            elseif ($nodes.Count) { (T "$($nodes.Count) elementos seleccionados") + "  ·  $(Format-Size ([double](($nodes | Measure-Object Size -Sum).Sum)))" }
            else { T 'Elige un archivo o carpeta del árbol. Con Ctrl o Mayús, varios.' }
    }
}

# click: just one; Ctrl+click: add or remove; Shift+click: everything in between
function Select-DiskRow($Row) {
    $mods = [Windows.Input.Keyboard]::Modifiers
    if ($mods -band [Windows.Input.ModifierKeys]::Control) {
        if (@($script:DiskSel) -contains $Row) { Set-DiskSelection @($script:DiskSel | Where-Object { $_ -ne $Row }) } else { Set-DiskSelection (@($script:DiskSel) + $Row) }
        $script:DiskAnchor = $Row; return $true
    }
    if (($mods -band [Windows.Input.ModifierKeys]::Shift) -and $script:DiskAnchor) {
        $list = $script:DiskRows.Children; $a = $list.IndexOf($script:DiskAnchor); $b = $list.IndexOf($Row)
        if ($a -ge 0) { Set-DiskSelection @($list | Select-Object -Skip ([math]::Min($a, $b)) -First ([math]::Abs($a - $b) + 1)); return $true }
    }
    Set-DiskSelection @($Row); $script:DiskAnchor = $Row; $false
}

function Fill-DiskMenu($Row) {
    if (@($script:DiskSel) -notcontains $Row) { Set-DiskSelection @($Row); $script:DiskAnchor = $Row }
    $nodes = Get-DiskSelNodes; $m = $Row.ContextMenu; $m.Items.Clear()
    foreach ($it in $DiskActions) {
        if ($it -eq '-') { if ($m.Items.Count -and $m.Items[$m.Items.Count - 1] -isnot [Windows.Controls.Separator]) { [void]$m.Items.Add([Windows.Controls.Separator]::new()) }; continue }
        if ($it[0] -eq 'rescan' -and $nodes[0].IsFile) { continue }
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = T $it[1]; $mi.Tag = $it[0]
        $mi.Icon = New-Icon $it[2] 15 $(if ($it[0] -eq 'delete') { 'Red' } else { 'Ink2' })
        if ($it[0] -eq 'delete') { $mi.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Red') }
        $mi.IsEnabled = Test-DiskAction $nodes $it[0]
        $mi.Add_Click({ param($s) Invoke-DiskAction (Get-DiskSelNodes) ([string]$s.Tag) })
        [void]$m.Items.Add($mi)
    }
}

function Invoke-DiskAction($Nodes, [string]$Act) {
    $Nodes = @($Nodes); if (-not (Test-DiskAction $Nodes $Act)) { return }
    $n = $Nodes[0]; $p = Get-DiskPath $n
    $dir = if ($n.IsFile) { $n.Parent.Path } else { $p }
    switch ($Act) {
        'open' { Start-Process -FilePath $p }
        'show' { if ($n.IsFile) { Start-Process explorer.exe -ArgumentList "/select,`"$p`"" } else { Start-Process explorer.exe -ArgumentList "`"$p`"" } }
        'copy' { [Windows.Clipboard]::SetText((@($Nodes | ForEach-Object { Get-DiskPath $_ }) -join "`r`n")) }
        'term' { Start-Process powershell.exe -WorkingDirectory $dir }
        'props' {
            $sh = New-Object -ComObject Shell.Application
            if ($n.IsFile) { $sh.Namespace($dir).ParseName($n.Name).InvokeVerb('properties') } else { $sh.Namespace($p).Self.InvokeVerb('properties') }
        }
        'rescan' { if (-not $n.Parent) { $script:DiskCache.Remove($script:DiskRoot); Start-DiskScan $script:DiskRoot 0 } else { Start-DiskJob $Nodes 'rescan' } }
        default {
            # if a folder and something inside it were both selected, the folder is enough
            $Nodes = @($Nodes | Where-Object { $x = $_.Parent; $inside = $false; while ($x) { if ($Nodes -contains $x) { $inside = $true }; $x = $x.Parent }; -not $inside })
            $size = [double](($Nodes | Measure-Object Size -Sum).Sum); $files = [double](($Nodes | Measure-Object Files -Sum).Sum)
            $list = @($Nodes | Select-Object -First 6 | ForEach-Object { Get-DiskPath $_ })
            if ($Nodes.Count -gt 6) { $list += T "y $($Nodes.Count - 6) más" }
            $what = "`n`n$($list -join "`n")`n`n$(Format-Size $size), " + (T "$('{0:N0}' -f $files) archivos")
            $msg = if ($Act -eq 'recycle') { (T '¿Mover a la papelera de reciclaje?') + $what } else { (T '¿Eliminar para siempre? No va a la papelera y no se puede deshacer.') + $what }
            if ([Windows.MessageBox]::Show($window, $msg, 'OptiEleven', 'OKCancel', 'Warning') -ne 'OK') { return }
            Start-DiskJob $Nodes $Act
        }
    }
}

# deletes (or re-measures) in the background; what is left on disk is measured again, so the tree adds up even if it fails halfway
function Start-DiskJob($Nodes, [string]$Act) {
    $script:DiskJobNodes = @($Nodes); $script:DiskJobAct = $Act
    $title = @{ recycle = 'Moviendo a la papelera'; delete = 'Eliminando'; rescan = 'Analizando la carpeta' }[$Act]
    $detail = if ($script:DiskJobNodes.Count -eq 1) { Get-DiskPath $script:DiskJobNodes[0] } else { T "$($script:DiskJobNodes.Count) elementos seleccionados" }
    $script:DiskWork = Show-Working (T $title) $detail
    $items = @($script:DiskJobNodes | ForEach-Object { @{ Path = (Get-DiskPath $_); File = [bool]$_.IsFile } })
    Start-Bg -Work {
        param($A)
        foreach ($it in $A.Items) {
            $err = ''
            try {
                if ($A.Act -eq 'recycle') {
                    Add-Type -AssemblyName Microsoft.VisualBasic
                    # AllDialogs: Windows warns if something doesn't fit in the recycle bin, instead of deleting it for good without asking
                    if ($it.File) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($it.Path, 'AllDialogs', 'SendToRecycleBin') }
                    else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.Path, 'AllDialogs', 'SendToRecycleBin') }
                } elseif ($A.Act -eq 'delete') { Remove-Item -LiteralPath $it.Path -Recurse -Force -ErrorAction Stop }
            } catch { $err = $_.Exception.Message }
            $left = Test-Path -LiteralPath $it.Path
            @{ Left = $left; Scan = $(if ($left -and -not $it.File) { , [GP.DiskScan]::Scan($it.Path) } else { $null }); Err = $err }
        }
    } -ArgList @(@{ Act = $Act; Items = $items }) -Done {
        param($r)
        Close-Working $script:DiskWork
        if (-not $r) { return }
        $open = [Collections.Generic.HashSet[object]]::new()
        foreach ($c in $script:DiskRows.Children) { if ($c.Tag.Open) { [void]$open.Add($c.Tag.Node) } }
        $sel = @(); $freed = [double]0; $stuck = 0; $chg = @()
        for ($i = 0; $i -lt $r.Count; $i++) {
            $res = $r[$i]; $old = $script:DiskJobNodes[$i]
            if ($res.Err) { Write-Log "Espacio en disco: $($res.Err)" 'WARN' }
            if ($res.Left -and $old.IsFile) { $stuck++; $sel += $old; continue }
            $new = $null
            if ($res.Left) { $new = $res.Scan[0]; $new.Name = $old.Name; $new.LastWrite = $old.LastWrite; $sel += $new; if ($open.Contains($old)) { [void]$open.Add($new) } }
            $after = if ($new) { Format-Size $new.Size } elseif ($script:DiskJobAct -eq 'recycle') { 'en la papelera' } else { 'eliminado' }
            if ($script:DiskJobAct -ne 'rescan') { $chg += [ordered]@{ what = (Get-DiskPath $old); before = (Format-Size $old.Size); after = $after } }
            $freed += Set-DiskNode $old $new
        }
        if ($freed -gt 0) { Write-Log "Espacio en disco: liberados $(Format-Size $freed)." 'OK' }
        if ($chg.Count) { Add-History 'disk' $script:DiskJobAct "Espacio en disco: liberados $(Format-Size $freed)." '' $true $chg }
        Update-DiskTree $open $sel
        if ($stuck) { [void][Windows.MessageBox]::Show($window, (T 'Algunos archivos no se han podido borrar. Puede que estén en uso.'), 'OptiEleven', 'OK', 'Warning') }
    }
}

# replaces one node with another (or removes it if $New is $null) and fixes the sizes and file counts of all parent folders
function Set-DiskNode($Old, $New) {
    $dS = $(if ($New) { $New.Size } else { 0 }) - $Old.Size; $dF = $(if ($New) { $New.Files } else { 0 }) - $Old.Files
    $par = $Old.Parent; $i = $par.Kids.IndexOf($Old)
    if ($New) { $New.Parent = $par; $par.Kids[$i] = $New } else { $par.Kids.RemoveAt($i) }
    $bySize = [Comparison[GP.DNode]] { param($x, $y) $y.Size.CompareTo($x.Size) }
    for ($up = $par; $up; $up = $up.Parent) { $up.Size += $dS; $up.Files += $dF; $up.Kids.Sort($bySize) }
    -$dS
}

# redraws the tree keeping the same folders expanded and whatever still exists selected
function Update-DiskTree($Open, $Sel) {
    $root = $script:DiskCache[$script:DiskRoot].Root; $list = $script:DiskRows
    $list.Children.Clear(); $script:DiskSel = @(); $script:DiskAnchor = $null
    [void]$list.Children.Add((New-DiskTreeRow $root 0 $root.Size))
    for ($i = 0; $i -lt $list.Children.Count; $i++) { $c = $list.Children[$i]; if ($c.Tag.Node -and $Open.Contains($c.Tag.Node)) { Switch-DiskRow $c } }
    $Sel = @($Sel)
    Set-DiskSelection @($list | Where-Object { $_.Tag.Node -and $Sel -contains $_.Tag.Node })
}

function Switch-DiskRow($Row) {
    $t = $Row.Tag; if (-not $t.CanOpen) { return }
    $list = $script:DiskRows; $idx = $list.Children.IndexOf($Row)
    if ($t.Open) {
        # collapse: remove everything under this row
        while ($idx + 1 -lt $list.Children.Count -and $list.Children[$idx + 1].Tag.Depth -gt $t.Depth) { $list.Children.RemoveAt($idx + 1) }
        $t.Open = $false; $t.Chev.Text = '▸'; return
    }
    $kids = $t.Node.Kids; $n = [math]::Min($kids.Count, $DiskMaxKids); $pos = $idx + 1
    for ($i = 0; $i -lt $n; $i++) { $list.Children.Insert($pos, (New-DiskTreeRow $kids[$i] ($t.Depth + 1) $t.Node.Size)); $pos++ }
    if ($kids.Count -gt $DiskMaxKids) {
        $more = New-Text (T "y $($kids.Count - $DiskMaxKids) elementos más pequeños") 12.5 'Muted'; $more.Margin = "$(($t.Depth + 1) * 12 + 46),4,0,4"
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
    # tree
    $card = [Windows.Controls.Border]::new(); $card.CornerRadius = 8; $card.Padding = '10,10,10,10'; $card.BorderThickness = 1; $card.Margin = '0,0,14,0'
    $card.SetResourceReference($BgP, 'Glass'); $card.SetResourceReference($BrP, 'GlassEdge')
    $cs = [Windows.Controls.StackPanel]::new()
    # action bar for the selection (same as the right click)
    $tools = [Windows.Controls.WrapPanel]::new(); $tools.Margin = '2,0,0,6'; $script:DiskTools = @()
    foreach ($it in $DiskActions) {
        if ($it -eq '-') { $sep = [Windows.Controls.Border]::new(); $sep.Width = 1; $sep.Height = 22; $sep.Margin = '2,0,8,6'; $sep.SetResourceReference($BgP, 'Rule'); [void]$tools.Children.Add($sep); continue }
        $b = New-Btn ''; $b.MinHeight = 32; $b.Padding = '10,0'; $b.FontSize = 12.5; $b.Margin = '0,0,6,6'; $b.Tag = $it[0]
        $bc = [Windows.Controls.StackPanel]::new(); $bc.Orientation = 'Horizontal'
        $bi = New-BtnIcon $it[2] 15; $bi.Margin = '0,0,7,0'
        $bl = [Windows.Controls.TextBlock]::new(); $bl.Text = T $it[1]; $bl.VerticalAlignment = 'Center'
        [void]$bc.Children.Add($bi); [void]$bc.Children.Add($bl); $b.Content = $bc
        if ($it[0] -eq 'delete') { $b.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Red') }
        $b.Add_Click({ param($s) Invoke-DiskAction (Get-DiskSelNodes) ([string]$s.Tag) })
        [void]$tools.Children.Add($b); $script:DiskTools += $b
    }
    [void]$cs.Children.Add($tools)
    $script:DiskSelText = New-Text '' 12 'Muted'; $script:DiskSelText.Margin = '6,0,0,10'; $script:DiskSelText.TextTrimming = 'CharacterEllipsis'
    [void]$cs.Children.Add($script:DiskSelText)
    $hdr = New-Cols $DiskCols; $hdr.Margin = '6,0,8,6'
    $heads = 'Nombre', 'Proporción', 'Porcentaje', 'Tamaño', 'Archivos', 'Modificado'
    for ($i = 0; $i -lt 6; $i++) { $h = New-Text $heads[$i] 12 'Muted' 'SemiBold'; if ($i -ge 2) { $h.TextAlignment = 'Right' }; [void](Add-At $hdr $h $i) }
    [void]$cs.Children.Add($hdr); [void]$cs.Children.Add((New-Ruled))
    $script:DiskRows = [Windows.Controls.StackPanel]::new()
    [void]$cs.Children.Add($script:DiskRows)
    $card.Child = $cs
    [void](Add-At $grid $card 0)
    # extensions
    $ec = [Windows.Controls.Border]::new(); $ec.CornerRadius = 8; $ec.Padding = '16,14'; $ec.BorderThickness = 1; $ec.VerticalAlignment = 'Top'
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
    # the root (the drive) already expanded
    $rootRow = New-DiskTreeRow $res.Root 0 $res.Root.Size
    [void]$script:DiskRows.Children.Add($rootRow)
    Switch-DiskRow $rootRow
    $script:DiskSel = @(); $script:DiskAnchor = $null; Set-DiskSelection @()
    Start-FadeIn $grid 0 8
}

function New-DiskPage {
    $BgP = [Windows.Controls.Border]::BackgroundProperty
    $root = [Windows.Controls.StackPanel]::new()
    $hint = New-Text 'Clic para desplegar, doble clic para abrir y clic derecho para borrar.' 13 'Ink2'
    if (-not $script:IsAdmin) { $hint.Text += ' ' + (T 'Sin administrador, algunas carpetas del sistema no se pueden medir.') }
    $hint.Margin = '0,0,0,14'
    [void]$root.Children.Add($hint)
    # one big button per drive, with how much is used
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
