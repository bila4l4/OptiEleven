# Módulo "Inicio": la bienvenida. Presenta el panel y lleva a cada apartado.

$HomeFeatures = @(
    @{ Key = 'all';      Icon = 'sliders-horizontal'; Color = 'Accent';              Title = 'Tweaks';        Desc = '60 ajustes de privacidad, servicios, rendimiento y latencia, todos reversibles.' }
    @{ Key = 'booster';  Icon = 'rocket-launch';      Color = 'Cat-Rendimiento';     Title = 'Game Booster';  Desc = 'Boost FPS de un clic: libera RAM, cierra lo que sobra y limpia antes de jugar.' }
    @{ Key = 'install';   Icon = 'download-simple';    Color = 'Cat-Actualizaciones'; Title = 'Instalar apps'; Desc = 'Más de 100 apps con su logo y un instalador único, como Ninite.' }
    @{ Key = 'cleanup';  Icon = 'broom';              Color = 'Cat-Interfaz';        Title = 'Limpieza';      Desc = 'Temporales, cachés y restos de actualizaciones. Ves cuánto ocupa antes de borrar.' }
    @{ Key = 'network';    Icon = 'wifi-high';          Color = 'Cat-Privacidad';      Title = 'Red';           Desc = 'Test de velocidad, latencia y DNS más rápidos con un clic.' }
    @{ Key = 'repair'; Icon = 'wrench';             Color = 'Cat-Latencia';        Title = 'Reparar';       Desc = 'DISM, SFC, red, Windows Update y Store: las reparaciones de siempre.' }
)

function New-HomePage {
    $BgP = [Windows.Controls.Border]::BackgroundProperty; $BrP = [Windows.Controls.Border]::BorderBrushProperty
    $root = [Windows.Controls.StackPanel]::new()

    # presentación
    $hero = [Windows.Controls.Border]::new(); $hero.CornerRadius = 18; $hero.Padding = '32,30,32,30'; $hero.Margin = '0,0,0,16'; $hero.BorderThickness = 1
    $hero.SetResourceReference($BgP, 'Glass'); $hero.SetResourceReference($BrP, 'GlassEdge')
    $hg = New-Cols @('Auto', '*')
    $logoFile = Join-Path $script:AppDir 'assets\logo-tile-512.png'
    if (Test-Path $logoFile) {
        $bi = [Windows.Media.Imaging.BitmapImage]::new(); $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.UriSource = [Uri]$logoFile; $bi.DecodePixelWidth = 192; $bi.EndInit(); $bi.Freeze()
        $img = [Windows.Controls.Image]::new(); $img.Source = $bi; $img.Width = 84; $img.Height = 84; $img.VerticalAlignment = 'Top'; $img.Margin = '0,4,26,0'
        $img.Effect = [Windows.Media.Effects.DropShadowEffect]::new(); $img.Effect.Color = [Windows.Media.Color]::FromRgb(124, 92, 255); $img.Effect.BlurRadius = 30; $img.Effect.ShadowDepth = 0; $img.Effect.Opacity = 0.55
        [void](Add-At $hg $img 0)
    }
    $hs = [Windows.Controls.StackPanel]::new()
    $badge = [Windows.Controls.Border]::new(); $badge.CornerRadius = 11; $badge.Padding = '10,3,10,4'; $badge.HorizontalAlignment = 'Left'; $badge.Margin = '0,0,0,10'
    $badge.SetResourceReference($BgP, 'AccentSoft')
    $bt = New-Text 'Panel de optimización para Windows 11' 12 'AccentEdge' 'SemiBold'; $badge.Child = $bt
    [void]$hs.Children.Add($badge)
    $h1 = New-Text 'Tu PC, listo para jugar.' 34 'Ink' 'Bold'; $h1.FontFamily = $window.FindResource('Display')
    [void]$hs.Children.Add($h1)
    $p = New-Text 'OptiEleven quita la telemetría y los procesos que sobran, prepara el equipo antes de cada partida e instala tus apps de una vez. Todo lo que cambia se puede deshacer con un clic.' 15.5 'Ink2'
    $p.Margin = '0,10,0,0'; $p.MaxWidth = 640; $p.HorizontalAlignment = 'Left'
    [void]$hs.Children.Add($p)
    $btns = [Windows.Controls.WrapPanel]::new(); $btns.Margin = '0,22,0,0'
    $b1 = New-Btn '' -Primary; $b1.MinHeight = 48; $b1.FontSize = 15; $b1.Padding = '24,0'; $b1.Margin = '0,0,10,0'
    $c1 = [Windows.Controls.StackPanel]::new(); $c1.Orientation = 'Horizontal'
    $i1 = New-BtnIcon 'shield-check' 19; $i1.Margin = '0,0,9,0'; [void]$c1.Children.Add($i1)
    $l1 = [Windows.Controls.TextBlock]::new(); $l1.Text = T 'Empezar con Recomendado'; $l1.VerticalAlignment = 'Center'; [void]$c1.Children.Add($l1)
    $b1.Content = $c1
    $b1.ToolTip = (T 'Marca los tweaks seguros en la hoja de cambios. Nada se aplica hasta que pulses Aplicar cambios.')
    $b1.Add_Click({ Select-NavKey 'all'; Select-Preset 'R' 'Recomendado' })
    $b2 = New-Btn 'Boost FPS'; $b2.MinHeight = 48; $b2.FontSize = 15; $b2.Padding = '22,0'; $b2.Margin = '0,0,10,0'
    $b2.Add_Click({ Select-NavKey 'booster' })
    $b3 = New-Btn 'Ver todos los tweaks'; $b3.MinHeight = 48; $b3.FontSize = 15; $b3.Padding = '22,0'
    $b3.Add_Click({ Select-NavKey 'all' })
    foreach ($b in $b1, $b2, $b3) { [void]$btns.Children.Add($b) }
    [void]$hs.Children.Add($btns)
    [void](Add-At $hg $hs 1)
    $hero.Child = $hg
    [void]$root.Children.Add($hero)

    # estado del equipo
    $stats = New-Cols @('*', '*', '*', '*'); $stats.Margin = '0,0,0,8'
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $osName = if ($cv) { "$($cv.DisplayVersion), build $($cv.CurrentBuild)" } else { 'Windows 11' }
    $cells = @(
        @('Tweaks aplicados', 'check', 'Cat-Juegos', '...', 'HomeTweaks'),
        @('RAM en uso', 'memory', 'Cat-Latencia', '...', 'HomeRam'),
        @('Windows', 'windows-logo', 'Cat-Privacidad', $osName, $null),
        @('Permisos', 'shield-check', 'Cat-Apps', $(if ($script:IsAdmin) { 'Administrador' } else { 'Solo lectura' }), $null))
    for ($i = 0; $i -lt $cells.Count; $i++) {
        $c = $cells[$i]
        $cell = [Windows.Controls.Border]::new(); $cell.CornerRadius = 14; $cell.Padding = '16,14'; $cell.Margin = $(if ($i -lt 3) { '0,0,10,0' } else { '0' }); $cell.BorderThickness = 1
        $cell.SetResourceReference($BgP, 'Glass'); $cell.SetResourceReference($BrP, 'GlassEdge')
        $cs = [Windows.Controls.StackPanel]::new()
        $hd = [Windows.Controls.StackPanel]::new(); $hd.Orientation = 'Horizontal'
        $ic = New-Icon $c[1] 16 $c[2]; $ic.Margin = '0,0,8,0'; [void]$hd.Children.Add($ic)
        [void]$hd.Children.Add((New-Text $c[0] 12.5 'Muted' 'Medium'))
        [void]$cs.Children.Add($hd)
        $v = New-Text $c[3] 17 'Ink' 'SemiBold'; $v.Margin = '0,6,0,0'; $v.TextTrimming = 'CharacterEllipsis'; $v.TextWrapping = 'NoWrap'
        [void]$cs.Children.Add($v)
        $cell.Child = $cs
        [void](Add-At $stats $cell $i)
        if ($c[4]) { Set-Variable -Scope Script -Name $c[4] -Value $v }
    }
    [void]$root.Children.Add($stats)
    Update-HomeStats

    # qué hay dentro
    [void]$root.Children.Add((New-Section 'Qué puedes hacer'))
    $grid = [Windows.Controls.Primitives.UniformGrid]::new(); $grid.Columns = 3; $grid.Margin = '0,0,-12,0'
    foreach ($ft in $HomeFeatures) {
        $card = [Windows.Controls.Border]::new(); $card.Style = $window.FindResource('Row'); $card.Margin = '0,0,12,12'; $card.Padding = '18,16'; $card.Cursor = 'Hand'; $card.Tag = $ft.Key
        $cs = [Windows.Controls.StackPanel]::new()
        $iw = New-IconWell $ft.Icon 44 $ft.Color; $iw.HorizontalAlignment = 'Left'; [void]$cs.Children.Add($iw)
        $t = New-Text $ft.Title 16 'Ink' 'SemiBold'; $t.Margin = '0,14,0,0'; [void]$cs.Children.Add($t)
        $d = New-Text $ft.Desc 13 'Muted'; $d.Margin = '0,4,0,0'; [void]$cs.Children.Add($d)
        $go = [Windows.Controls.StackPanel]::new(); $go.Orientation = 'Horizontal'; $go.Margin = '0,12,0,0'
        $op = New-Text 'Abrir' 13 'AccentEdge' 'SemiBold'; $op.Text = $op.Text + '  →'; [void]$go.Children.Add($op)
        [void]$cs.Children.Add($go)
        $card.Child = $cs
        $card.Add_MouseLeftButtonUp({ param($src, $e) Select-NavKey ([string]$src.Tag) })
        [void]$grid.Children.Add($card)
    }
    [void]$root.Children.Add($grid)

    $foot = [Windows.Controls.StackPanel]::new(); $foot.Orientation = 'Horizontal'; $foot.Margin = '2,8,0,0'
    $fi = New-Icon 'arrow-counter-clockwise' 15 'Cat-Juegos'; $fi.Margin = '0,0,8,0'; [void]$foot.Children.Add($fi)
    [void]$foot.Children.Add((New-Text 'Todo es reversible: antes de cambiar algo, OptiEleven guarda cómo estaba.' 13 'Muted'))
    [void]$root.Children.Add($foot)
    $root
}

function Update-HomeStats {
    if ($script:HomeTweaks -and $script:Rows) {
        $applied = @($script:Rows.Values | Where-Object { $_.Applied }).Count
        $known = @($script:Rows.Values | Where-Object { $null -ne $_.Applied }).Count
        $script:HomeTweaks.Text = if ($known) { T "$applied de $($script:Rows.Count)" } else { '...' }
    }
    if ($script:HomeRam -and $script:Telemetry -and $script:Telemetry.Ready) {
        $script:HomeRam.Text = (T '{0:N1} / {1:N0} GB') -f ($script:Telemetry.RamUsed / 1GB), ($script:Telemetry.RamTotal / 1GB)
    }
}
