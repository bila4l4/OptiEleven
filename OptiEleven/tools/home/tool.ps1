# Inicio: el estado del equipo primero (cifras reales) y luego sugerencias ordenadas por lo que más aporta, cada una con
# un solo botón. Todo lo que se calcula aquí es rápido; lo lento (el análisis de Limpieza) solo se usa si ya se hizo.

# Lo personal de Inicio (fijados y orden de los bloques) va en home.json, junto al resto de preferencias del panel
$script:HomePrefsFile = Join-Path $script:Root 'home.json'
$HomeBlockIds = @('pins', 'status', 'suggestions')
function Get-HomePrefs {
    $p = $null
    try { if (Test-Path -LiteralPath $script:HomePrefsFile) { $p = [IO.File]::ReadAllText($script:HomePrefsFile, [Text.Encoding]::UTF8) | ConvertFrom-Json } } catch {}
    $pins = @(if ($p -and $p.pins) { foreach ($x in @($p.pins)) { [string]$x } })
    $order = @(if ($p -and $p.order) { foreach ($x in @($p.order)) { [string]$x } })
    # bloques que falten (versiones nuevas) al final; los que ya no existan, fuera
    $order = @($order | Where-Object { $HomeBlockIds -contains $_ }) + @($HomeBlockIds | Where-Object { $order -notcontains $_ })
    @{ pins = $pins; order = $order }
}
function Save-HomePrefs($Prefs) {
    try { [IO.File]::WriteAllText($script:HomePrefsFile, (ConvertTo-Json @{ pins = @($Prefs.pins); order = @($Prefs.order) } -Depth 3), [Text.UTF8Encoding]::new($false)) }
    catch { Write-Log "No se pudo guardar la personalización de Inicio: $($_.Exception.Message)" 'WARN' }
}
# cada cosa fijable tiene una clave: el id de la página o "tweak:<id>"
function Get-PinKey($Hit) { if ($Hit.Tweak) { "tweak:$($Hit.Tweak)" } else { [string]$Hit.Key } }

# cabecera de un bloque, con subir y bajar para cambiar el orden
function New-HomeBlockHead([string]$Id, [string]$Title, $Extra) {
    $g = New-Cols @('*', 'Auto', 'Auto', 'Auto'); $g.Margin = '2,14,0,8'
    $t = New-Text $Title 14 'Ink' 'SemiBold'; $t.VerticalAlignment = 'Center'; [void](Add-At $g $t 0)
    if ($Extra) { $Extra.Margin = '0,0,8,0'; [void](Add-At $g $Extra 1) }
    $i = 2
    foreach ($m in @(@(-1, 0xE70E, 'Subir'), @(1, 0xE70D, 'Bajar'))) {
        $b = New-Btn ''; $b.Content = (New-Icon $m[1] 12 'Ink2'); $b.MinWidth = 30; $b.MinHeight = 28; $b.Padding = '0'; $b.Margin = '4,0,0,0'
        $b.ToolTip = T $m[2]; $b.Tag = @($Id, $m[0])
        [Windows.Automation.AutomationProperties]::SetName($b, (T $m[2]))
        $b.Add_Click({ param($s) Move-HomeBlock $s.Tag[0] ([int]$s.Tag[1]) })
        [void](Add-At $g $b $i); $i++
    }
    $g
}
function Move-HomeBlock([string]$Id, [int]$Delta) {
    $p = Get-HomePrefs; $o = [Collections.Generic.List[string]]::new([string[]]$p.order)
    $i = $o.IndexOf($Id); $j = $i + $Delta
    if ($i -lt 0 -or $j -lt 0 -or $j -ge $o.Count) { return }
    $o.RemoveAt($i); $o.Insert($j, $Id)
    $p.order = @($o); Save-HomePrefs $p
    Update-HomeOrder
}
function Update-HomeOrder {
    $r = $script:HomeRoot; if (-not $r) { return }
    $r.Children.Clear()
    [void]$r.Children.Add($script:HomeInfo)
    foreach ($id in (Get-HomePrefs).order) { [void]$r.Children.Add($script:HomeBlocks[$id]) }
}

# ---------- fijados: herramientas, grupos o ajustes que tú eliges, arriba del todo si quieres
function Update-HomePins {
    $box = $script:HomePinBox; if (-not $box) { return }
    $box.Children.Clear()
    $p = Get-HomePrefs
    $index = @(try { Get-SearchIndex } catch { })
    $hits = @(foreach ($k in $p.pins) { $index | Where-Object { (Get-PinKey $_) -eq $k } | Select-Object -First 1 })
    if (-not $hits.Count) {
        $em = New-Text 'Fija aquí lo que más uses: una herramienta, un grupo de ajustes o un ajuste suelto.' 13 'Ink2'; $em.TextWrapping = 'Wrap'; $em.Margin = '2,0,0,4'
        [void]$box.Children.Add($em)
    }
    $wrap = [Windows.Controls.WrapPanel]::new(); $wrap.Margin = '0,0,-8,0'
    foreach ($h in $hits) {
        $tile = [Windows.Controls.Border]::new(); $tile.Style = $window.FindResource('RuleRow'); $tile.Width = 236; $tile.Margin = '0,0,8,8'; $tile.Cursor = 'Hand'; $tile.Tag = $h
        $g = New-Cols @('36', '*', 'Auto')
        [void](Add-At $g (New-IconWell $h.Icon 28) 0)
        $tx = [Windows.Controls.StackPanel]::new(); $tx.VerticalAlignment = 'Center'
        $n = New-Text $h.Name 13.5 'Ink'; $n.Text = $h.Name; $n.TextTrimming = 'CharacterEllipsis'; $n.TextWrapping = 'NoWrap'; [void]$tx.Children.Add($n)
        $sub = $h.Cat
        if ($h.Tweak) { $r = $script:Rows[$h.Tweak]; if ($r -and $r.Applied -eq $true) { $sub = T 'Aplicado' } elseif ($r -and $r.Applied -eq $false) { $sub = T 'No aplicado' } }
        if ($sub) { $c = New-Text $sub 11.5 'Ink2'; $c.Text = $sub; $c.TextTrimming = 'CharacterEllipsis'; $c.TextWrapping = 'NoWrap'; [void]$tx.Children.Add($c) }
        [void](Add-At $g $tx 1)
        $x = New-Btn ''; $x.Content = (New-Icon 0xE711 10 'Ink2'); $x.MinWidth = 26; $x.MinHeight = 26; $x.Padding = '0'; $x.Margin = '6,0,0,0'; $x.VerticalAlignment = 'Center'
        $x.ToolTip = T 'Quitar de Inicio'; [Windows.Automation.AutomationProperties]::SetName($x, (T 'Quitar de Inicio')); $x.Tag = (Get-PinKey $h)
        $x.Add_Click({ param($s, $e) $e.Handled = $true; Set-HomePin ([string]$s.Tag) $false })
        [void](Add-At $g $x 2)
        $tile.Child = $g
        $tile.Add_MouseLeftButtonUp({ param($s, $e) if (-not $e.Handled) { Open-SearchHit $s.Tag } })
        [void]$wrap.Children.Add($tile)
    }
    if ($hits.Count) { [void]$box.Children.Add($wrap) }
    $box.Children.Add($script:HomePicker) | Out-Null
}
function Set-HomePin([string]$Key, [bool]$On) {
    $p = Get-HomePrefs
    $p.pins = @($p.pins | Where-Object { $_ -ne $Key }); if ($On) { $p.pins += $Key }
    Save-HomePrefs $p
    Update-HomePins; Update-HomePicker
}
# buscador para fijar: lo mismo que encuentra Ctrl+K, con un botón Fijar
function Update-HomePicker {
    $pk = $script:HomePicker; if (-not $pk -or $pk.Visibility -ne 'Visible') { return }
    $list = $script:HomePickList; $list.Children.Clear()
    $q = $script:HomePickBox.Text.Trim().ToLower()
    $pinned = (Get-HomePrefs).pins
    $words = @($q -split '\s+' | Where-Object { $_ })
    $hits = @(@(try { Get-SearchIndex } catch { }) | Where-Object { $x = $_; $pinned -notcontains (Get-PinKey $x) -and -not @($words | Where-Object { $x.Text -notlike "*$_*" }).Count } | Select-Object -First 8)
    foreach ($h in $hits) {
        $g = New-Cols @('32', '*', 'Auto'); $g.Margin = '4,2,0,2'
        [void](Add-At $g (New-Icon $h.Icon 16 'Ink2') 0)
        $tx = [Windows.Controls.StackPanel]::new(); $tx.VerticalAlignment = 'Center'
        $n = New-Text $h.Name 13.5 'Ink'; $n.Text = $h.Name; [void]$tx.Children.Add($n)
        if ($h.Cat) { $c = New-Text $h.Cat 11.5 'Ink2'; $c.Text = $h.Cat; [void]$tx.Children.Add($c) }
        [void](Add-At $g $tx 1)
        $b = New-Btn 'Fijar'; $b.MinHeight = 28; $b.Padding = '12,0'; $b.Tag = (Get-PinKey $h); $b.Add_Click({ param($s) Set-HomePin ([string]$s.Tag) $true })
        [void](Add-At $g $b 2)
        [void]$list.Children.Add($g)
    }
    if (-not $hits.Count) { [void]$list.Children.Add((New-Text 'Sin resultados' 13 'Ink2')) }
}

function New-HomePage {
    $root = [Windows.Controls.StackPanel]::new(); $script:HomeRoot = $root
    $script:HomeBlocks = @{}
    # fijados
    $pins = [Windows.Controls.StackPanel]::new()
    $add = New-Btn 'Añadir'; $add.MinHeight = 28; $add.Padding = '12,0'
    $add.Add_Click({
        $pk = $script:HomePicker
        $pk.Visibility = if ($pk.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }
        if ($pk.Visibility -eq 'Visible') { $script:HomePickBox.Text = ''; Update-HomePicker; [void]$script:HomePickBox.Focus() }
    })
    [void]$pins.Children.Add((New-HomeBlockHead 'pins' (T 'Fijados') $add))
    $script:HomePinBox = [Windows.Controls.StackPanel]::new(); [void]$pins.Children.Add($script:HomePinBox)
    $pk = [Windows.Controls.Border]::new(); $pk.Style = $window.FindResource('Tile'); $pk.Padding = '12'; $pk.Margin = '0,0,0,8'; $pk.Visibility = 'Collapsed'
    $pks = [Windows.Controls.StackPanel]::new()
    $script:HomePickBox = [Windows.Controls.TextBox]::new(); $script:HomePickBox.Margin = '0,0,0,8'; $script:HomePickBox.Padding = '8,6'
    [Windows.Automation.AutomationProperties]::SetName($script:HomePickBox, (T 'Buscar'))
    $script:HomePickBox.Add_TextChanged({ Update-HomePicker })
    [void]$pks.Children.Add($script:HomePickBox)
    $script:HomePickList = [Windows.Controls.StackPanel]::new(); [void]$pks.Children.Add($script:HomePickList)
    $pk.Child = $pks; $script:HomePicker = $pk
    $script:HomeBlocks['pins'] = $pins
    # estado del equipo
    $status = [Windows.Controls.StackPanel]::new()
    [void]$status.Children.Add((New-HomeBlockHead 'status' (T 'Tu equipo') $null))
    # tira de estado: cuatro cifras separadas por filetes, en una sola tarjeta
    $strip = [Windows.Controls.Border]::new(); $strip.Style = $window.FindResource('Tile'); $strip.Padding = '0'; $strip.Margin = '0,0,0,4'
    $g = New-Cols @('*', '*', '*', '*')
    $script:HomeCells = @{}
    $cells = @(@('Tweaks', 'Ajustes aplicados'), @('Disk', 'Libres en C:'), @('Startup', 'Apps al iniciar'), @('Last', 'Último cambio'))
    for ($i = 0; $i -lt $cells.Count; $i++) {
        $c = [Windows.Controls.Border]::new(); $c.Padding = '18,14,18,14'
        if ($i -gt 0) { $c.BorderThickness = '1,0,0,0'; $c.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Rule') }
        $sp = [Windows.Controls.StackPanel]::new()
        $v = New-Text '...' 20 'Ink' 'SemiBold'; $v.FontFamily = $window.FindResource('Display'); $v.TextWrapping = 'NoWrap'; $v.TextTrimming = 'CharacterEllipsis'
        $l = New-Text $cells[$i][1] 12 'Ink2'
        [void]$sp.Children.Add($v); [void]$sp.Children.Add($l)
        $c.Child = $sp; [void](Add-At $g $c $i)
        $script:HomeCells[$cells[$i][0]] = $v
    }
    $strip.Child = $g
    [void]$status.Children.Add($strip)
    $script:HomeBlocks['status'] = $status
    # sugerencias
    $sug = [Windows.Controls.StackPanel]::new()
    [void]$sug.Children.Add((New-HomeBlockHead 'suggestions' (T 'Sugerencias') $null))
    $script:HomeSug = [Windows.Controls.StackPanel]::new(); [void]$sug.Children.Add($script:HomeSug)
    $script:HomeBlocks['suggestions'] = $sug
    # avisos (admin, punto de restauración) siempre arriba, fuera del orden
    $script:HomeInfo = [Windows.Controls.StackPanel]::new()
    Update-HomeOrder
    $root
}

# la cifra de ajustes cambia al aplicar o al terminar la comprobación; el núcleo la llama en cada cambio
function Update-HomeStats {
    if (-not $script:HomeCells -or -not $script:Rows) { return }
    $known = @($script:Rows.Values | Where-Object { $null -ne $_.Applied }).Count
    $applied = @($script:Rows.Values | Where-Object { $_.Applied -eq $true }).Count
    $script:HomeCells.Tweaks.Text = if ($known) { "$applied / $($script:Rows.Count)" } else { '...' }
}

function Format-Ago([datetime]$When) {
    $d = (Get-Date) - $When
    if ($d.TotalMinutes -lt 1) { T 'Ahora' } elseif ($d.TotalHours -lt 1) { T "Hace $([int]$d.TotalMinutes) min" }
    elseif ($d.TotalDays -lt 1) { T "Hace $([int]$d.TotalHours) h" } else { T "Hace $([int]$d.TotalDays) d" }
}

function New-Suggestion([string]$Icon, [string]$Title, [string]$Sub, [string]$Button, [scriptblock]$Action, [switch]$Primary) {
    $row = [Windows.Controls.Border]::new(); $row.Style = $window.FindResource('RuleRow')
    $g = New-Cols @('40', '*', 'Auto')
    [void](Add-At $g (New-IconWell $Icon 28) 0)
    $tx = [Windows.Controls.StackPanel]::new(); $tx.VerticalAlignment = 'Center'
    [void]$tx.Children.Add((New-Text $Title 14 'Ink'))
    if ($Sub) { [void]$tx.Children.Add((New-Text $Sub 12 'Ink2')) }
    [void](Add-At $g $tx 1)
    $b = if ($Primary) { New-Btn $Button -Primary } else { New-Btn $Button }
    $b.Margin = '16,0,0,0'; $b.MinWidth = 96; $b.Tag = $Action; $b.Add_Click({ param($s) & $s.Tag })
    [void](Add-At $g $b 2)
    $row.Child = $g
    $row
}

# "onShow" del tool.json: se recalcula cada vez que se abre Inicio
function Update-HomeView {
    if (-not $script:HomeCells) { return }
    # una línea con Windows y los permisos
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $os = if ($cv) { ([string]$cv.ProductName -replace 'Windows 10', $(if ([int]$cv.CurrentBuild -ge 22000) { 'Windows 11' } else { 'Windows 10' })) + " $($cv.DisplayVersion)" } else { 'Windows 11' }
    # saludo según la hora, con tu usuario de Windows y el nombre del equipo
    $hour = (Get-Date).Hour
    $hi = if ($hour -lt 12) { T 'Buenos días' } elseif ($hour -lt 20) { T 'Buenas tardes' } else { T 'Buenas noches' }
    $ui.PageTitle.Text = "$hi, $env:USERNAME"
    $ui.PageDesc.Text = "$env:COMPUTERNAME  ·  $os  ·  " + (T $(if ($script:IsAdmin) { 'Administrador' } else { 'Sin permisos de administrador' }))
    $ui.PageDesc.Visibility = 'Visible'
    Update-HomeStats
    try { $c = [IO.DriveInfo]::new($env:SystemDrive.TrimEnd(':')); $script:HomeCells.Disk.Text = Format-Size $c.AvailableFreeSpace } catch { $script:HomeCells.Disk.Text = '--' }
    $startup = @(try { Get-StartupEntries | Where-Object Enabled } catch { })
    $script:HomeCells.Startup.Text = "$($startup.Count)"
    $last = @(Get-History) | Sort-Object { [string]$_.time } -Descending | Select-Object -First 1
    $script:HomeCells.Last.Text = if ($last) { try { Format-Ago ([datetime]::Parse([string]$last.time)) } catch { '--' } } else { T 'Ninguno' }

    $script:HomeInfo.Children.Clear()
    if (-not $script:IsAdmin) {
        [void]$script:HomeInfo.Children.Add((New-InfoBar 'lock-simple' 'Ves el estado de todo, pero para aplicar cambios hace falta abrir el panel como administrador.' 'warn' 'Reiniciar como admin' { Restart-AsAdmin }))
    }

    # sugerencias, de más a menos importante; solo las que tocan en este equipo
    $script:HomeSug.Children.Clear()
    $ready = $script:StatusReady -or @($script:Rows.Values | Where-Object { $null -ne $_.Applied }).Count -gt 0   # la comprobación ya ha rellenado el estado
    $outside = @($script:Rows.Values | Where-Object { $_.Applied -eq $false -and (Get-Backup $_.Tweak.Id) })
    if ($ready -and $outside.Count) {
        [void]$script:HomeSug.Children.Add((New-Suggestion 'warning' (T "Windows ha deshecho $($outside.Count) ajustes") (($outside | Select-Object -First 3 | ForEach-Object { $_.Tweak.Name }) -join ', ') 'Revisar' { Select-NavKey 'all' } -Primary))
    }
    $rec = @($script:Rows.Values | Where-Object { $_.Applied -eq $false -and $_.Tweak.Presets -contains 'R' })
    if ($ready -and $rec.Count) {
        [void]$script:HomeSug.Children.Add((New-Suggestion 'shield-check' (T "$($rec.Count) ajustes recomendados sin aplicar") (T 'Seguros para casi todos los equipos. Se marcan en la hoja y los revisas antes de aplicar.') 'Revisar' { Select-Preset 'R' 'Recomendado' }))
    }
    $clean = 0; if ($script:CleanRows) { foreach ($r in $script:CleanRows.Values) { if ($null -ne $r.Bytes) { $clean += $r.Bytes } } }
    if ($clean -ge 200MB) { [void]$script:HomeSug.Children.Add((New-Suggestion 'broom' (T "Liberar $(Format-Size $clean)") (T 'Temporales, cachés y restos de actualizaciones.') 'Abrir' { Select-NavKey 'cleanup' })) }
    elseif (-not $script:CleanRows) { [void]$script:HomeSug.Children.Add((New-Suggestion 'broom' (T 'Mira cuánto espacio puedes liberar') (T 'Temporales, cachés y restos de actualizaciones.') 'Analizar' { Select-NavKey 'cleanup' })) }
    if ($startup.Count -ge 6) {
        [void]$script:HomeSug.Children.Add((New-Suggestion 'sign-in' (T "$($startup.Count) apps se abren al iniciar Windows") (($startup | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ') 'Revisar' { Select-NavKey 'startup' }))
    }
    [void]$script:HomeSug.Children.Add((New-Suggestion 'lightning' (T 'Antes de jugar') (T 'Sesión de juego cierra lo que sobra y lo devuelve al terminar.') 'Abrir' { Select-NavKey 'booster' }))
    if (-not $ready) { $w = New-Text 'Comprobando el estado de los ajustes...' 12 'Ink2'; $w.Margin = '2,6,0,0'; [void]$script:HomeSug.Children.Add($w) }
    Update-HomePins
}
