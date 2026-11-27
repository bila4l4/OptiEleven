# Inicio: el estado del equipo primero (cifras reales) y luego sugerencias ordenadas por lo que más aporta, cada una con
# un solo botón. Todo lo que se calcula aquí es rápido; lo lento (el análisis de Limpieza) solo se usa si ya se hizo.

function New-HomePage {
    $root = [Windows.Controls.StackPanel]::new()
    # tira de estado: cuatro cifras separadas por filetes, en una sola tarjeta
    $strip = [Windows.Controls.Border]::new(); $strip.Style = $window.FindResource('Tile'); $strip.Padding = '0'; $strip.Margin = '0,0,0,12'
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
    [void]$root.Children.Add($strip)
    $script:HomeInfo = [Windows.Controls.StackPanel]::new(); [void]$root.Children.Add($script:HomeInfo)
    $st = New-Text 'Sugerencias' 14 'Ink' 'SemiBold'; $st.Margin = '2,14,0,8'; [void]$root.Children.Add($st)
    $script:HomeSug = [Windows.Controls.StackPanel]::new(); [void]$root.Children.Add($script:HomeSug)
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
}
