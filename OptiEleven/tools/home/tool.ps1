# Home: a ring with your PC's score (0-100) that draws itself on entry. It has four segments (privacy, performance,
# space and startup), and each one lights up on hover and takes you to its page on click. Below, the categories and
# what can be improved, each with a button. Everything computed here is fast.

$RingSize = 280; $RingRadius = 116; $RingThick = 18
# each segment: name, icon, where it leads
$RingParts = @(
    @{ Id = 'privacy'; Name = 'Privacidad'; Icon = 'shield-check'; Go = 'c-privacy' }
    @{ Id = 'perf'; Name = 'Rendimiento'; Icon = 'gauge'; Go = 'c-optimize' }
    @{ Id = 'space'; Name = 'Espacio'; Icon = 'hard-drives'; Go = 'disk' }
    @{ Id = 'startup'; Name = 'Arranque'; Icon = 'sign-in'; Go = 'startup' }
)

# ---------- geometry: angles in degrees, 0 at the top, clockwise
function Get-RingPoint([double]$Deg) {
    $rad = ($Deg - 90) * [math]::PI / 180
    [Windows.Point]::new($RingSize / 2 + $RingRadius * [math]::Cos($rad), $RingSize / 2 + $RingRadius * [math]::Sin($rad))
}
function Get-ArcGeometry([double]$From, [double]$To) {
    if ($To - $From -lt 0.5) { return [Windows.Media.Geometry]::Empty }
    $fig = [Windows.Media.PathFigure]::new(); $fig.StartPoint = Get-RingPoint $From; $fig.IsClosed = $false
    $seg = [Windows.Media.ArcSegment]::new((Get-RingPoint $To), [Windows.Size]::new($RingRadius, $RingRadius), 0, (($To - $From) -gt 180), [Windows.Media.SweepDirection]::Clockwise, $true)
    $fig.Segments.Add($seg)
    $g = [Windows.Media.PathGeometry]::new(); $g.Figures.Add($fig); $g
}
function New-RingPath([string]$Brush) {
    $p = [Windows.Shapes.Path]::new(); $p.StrokeThickness = $RingThick
    $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'
    $p.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, $Brush)
    $p
}

# ---------- the score: each segment is worth 0 to 1 (recommended tweaks applied, free space, how many apps start on their own)
function Get-RingValues {
    $rows = @(if ($script:Rows) { $script:Rows.Values })
    $known = @($rows | Where-Object { $null -ne $_.Applied }).Count -gt 0
    $fr = {
        param($cats)
        $r = @($rows | Where-Object { $cats -contains $_.Tweak.Cat -and $_.Tweak.Presets -contains 'R' })
        $a = @($r | Where-Object { $_.Applied -eq $true }).Count
        @{ F = $(if ($r.Count) { $a / $r.Count } else { 1 }); A = $a; N = $r.Count }
    }
    $priv = & $fr @('Privacidad')
    $perf = & $fr @('Rendimiento', 'Latencia', 'Juegos')
    $free = 0; $total = 1
    try { $c = [IO.DriveInfo]::new($env:SystemDrive.TrimEnd(':')); $free = [double]$c.AvailableFreeSpace; $total = [double]$c.TotalSize } catch {}
    $startup = @(try { Get-StartupEntries | Where-Object Enabled } catch { }).Count
    @{
        Known = $known
        privacy = @{ F = $priv.F; Text = (T "$($priv.A) de $($priv.N) recomendados aplicados") }
        perf = @{ F = $perf.F; Text = (T "$($perf.A) de $($perf.N) recomendados aplicados") }
        space = @{ F = [math]::Min([double]1, ($free / $total) / 0.25); Text = (T "$(Format-Size $free) libres de $(Format-Size $total)") }   # 25 % free or more = full
        startup = @{ F = [math]::Max([double]0, [math]::Min([double]1, (12 - $startup) / 9)); Text = (T "$startup apps al iniciar") }   # 3 or fewer = full, 12 or more = empty
    }
}

function New-HomePage {
    $root = [Windows.Controls.StackPanel]::new()
    $script:HomeInfo = [Windows.Controls.StackPanel]::new(); [void]$root.Children.Add($script:HomeInfo)

    # ---------- ring
    $hero = [Windows.Controls.Grid]::new(); $hero.Width = $RingSize; $hero.Height = $RingSize; $hero.HorizontalAlignment = 'Center'; $hero.Margin = '0,8,0,0'
    $cv = [Windows.Controls.Canvas]::new(); $cv.Width = $RingSize; $cv.Height = $RingSize
    $script:RingSeg = @()
    for ($i = 0; $i -lt $RingParts.Count; $i++) {
        $from = $i * 90 + 5; $to = $i * 90 + 85   # a gap between segments
        $track = New-RingPath 'Track'; $track.Data = Get-ArcGeometry $from $to
        $fill = New-RingPath 'Accent'; $fill.IsHitTestVisible = $false
        foreach ($p in $track, $fill) { [void]$cv.Children.Add($p) }
        $track.Cursor = 'Hand'; $track.Tag = $i
        $track.Add_MouseEnter({ param($s) Set-RingHover ([int]$s.Tag) })
        $track.Add_MouseLeave({ Set-RingHover -1 })
        $track.Add_MouseLeftButtonUp({ param($s) Select-NavKey $RingParts[[int]$s.Tag].Go })
        [Windows.Automation.AutomationProperties]::SetName($track, (T $RingParts[$i].Name))
        $script:RingSeg += @{ Track = $track; Fill = $fill; From = $from; To = $to; Now = 0.0 }
    }
    [void]$hero.Children.Add($cv)
    # center: the score, or the segment under the mouse
    $mid = [Windows.Controls.StackPanel]::new(); $mid.VerticalAlignment = 'Center'; $mid.HorizontalAlignment = 'Center'; $mid.IsHitTestVisible = $false
    $script:RingIcon = [Windows.Controls.ContentControl]::new(); $script:RingIcon.HorizontalAlignment = 'Center'; $script:RingIcon.Visibility = 'Collapsed'; $script:RingIcon.Margin = '0,0,0,6'
    $num = [Windows.Controls.StackPanel]::new(); $num.Orientation = 'Horizontal'; $num.HorizontalAlignment = 'Center'
    $script:RingNum = New-Text '0' 56 'Ink' 'SemiBold'; $script:RingNum.FontFamily = $window.FindResource('Display'); $script:RingNum.Text = '0'
    $script:RingOf = New-Text '/100' 16 'Ink2'; $script:RingOf.Text = '/100'; $script:RingOf.VerticalAlignment = 'Bottom'; $script:RingOf.Margin = '4,0,0,12'
    [void]$num.Children.Add($script:RingNum); [void]$num.Children.Add($script:RingOf)
    $script:RingLabel = New-Text 'Estado del equipo' 13 'Ink2'; $script:RingLabel.HorizontalAlignment = 'Center'; $script:RingLabel.TextAlignment = 'Center'; $script:RingLabel.MaxWidth = 170; $script:RingLabel.TextWrapping = 'Wrap'
    foreach ($x in $script:RingIcon, $num, $script:RingLabel) { [void]$mid.Children.Add($x) }
    [void]$hero.Children.Add($mid)
    [void]$root.Children.Add($hero)

    $script:RingSummary = New-Text '' 15 'Ink' 'Medium'; $script:RingSummary.HorizontalAlignment = 'Center'; $script:RingSummary.Margin = '0,14,0,2'
    [void]$root.Children.Add($script:RingSummary)
    # legend: what each segment is and its value; it also reacts to hover and click
    $script:RingLegend = [Windows.Controls.WrapPanel]::new(); $script:RingLegend.HorizontalAlignment = 'Center'; $script:RingLegend.Margin = '0,6,0,0'
    [void]$root.Children.Add($script:RingLegend)

    # ---------- free memory: Home's one-click button. Only things with no lasting effect: it touches no tweak
    $free = New-Btn '' -Primary; $free.HorizontalAlignment = 'Center'; $free.MinHeight = 44; $free.Padding = '22,0'; $free.FontSize = 15; $free.Margin = '0,18,0,0'
    $fsp = [Windows.Controls.StackPanel]::new(); $fsp.Orientation = 'Horizontal'
    $fi = New-BtnIcon 'lightning' 18; $fi.Margin = '0,0,10,0'; [void]$fsp.Children.Add($fi)
    $ft = [Windows.Controls.TextBlock]::new(); $ft.Text = T 'Liberar memoria'; $ft.VerticalAlignment = 'Center'; [void]$fsp.Children.Add($ft)
    $free.Content = $fsp; $free.ToolTip = T 'Libera RAM, borra archivos temporales y vacía la caché DNS. No cambia ningún ajuste.'
    $free.Add_Click({ Invoke-HomeFreeUp })
    [void]$root.Children.Add($free)
    $script:FreeResult = New-Text 'RAM, temporales y caché DNS. No cambia ningún ajuste.' 12.5 'Ink2'; $script:FreeResult.HorizontalAlignment = 'Center'; $script:FreeResult.Margin = '0,6,0,0'
    [void]$root.Children.Add($script:FreeResult)

    # ---------- categories, as shortcuts
    $cats = [Windows.Controls.WrapPanel]::new(); $cats.HorizontalAlignment = 'Center'; $cats.Margin = '0,20,0,4'
    foreach ($k in @($Pages.Keys | Where-Object { $_ -like 'c-*' })) {
        $pg = $Pages[$k]
        $b = New-Btn ''; $b.MinHeight = 36; $b.Padding = '14,0'; $b.Margin = '4'; $b.Tag = $k
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
        $ic = New-BtnIcon $pg.Icon 16; $ic.Margin = '0,0,8,0'; [void]$sp.Children.Add($ic)
        $tl = [Windows.Controls.TextBlock]::new(); $tl.Text = T $pg.Label; $tl.VerticalAlignment = 'Center'; [void]$sp.Children.Add($tl)
        $b.Content = $sp
        $b.Add_Click({ param($s) Select-NavKey ([string]$s.Tag) })
        [void]$cats.Children.Add($b)
    }
    [void]$root.Children.Add($cats)

    # ---------- what to improve
    $st = New-Text 'Qué mejorar' 14 'Ink' 'SemiBold'; $st.Margin = '2,22,0,8'; [void]$root.Children.Add($st)
    $script:HomeSug = [Windows.Controls.StackPanel]::new(); [void]$root.Children.Add($script:HomeSug)
    $root
}

# the ring's center shows the score, or the segment under the mouse (and that segment gets thicker)
function Set-RingHover([int]$Index) {
    for ($i = 0; $i -lt $script:RingSeg.Count; $i++) {
        $t = if ($i -eq $Index) { $RingThick + 6 } else { $RingThick }
        $script:RingSeg[$i].Track.StrokeThickness = $t; $script:RingSeg[$i].Fill.StrokeThickness = $t
    }
    if ($Index -lt 0 -or -not $script:RingVals) {
        $script:RingIcon.Visibility = 'Collapsed'
        $script:RingNum.Text = "$($script:RingScore)"; $script:RingOf.Text = '/100'
        $script:RingLabel.Text = T 'Estado del equipo'
        return
    }
    $part = $RingParts[$Index]; $v = $script:RingVals[$part.Id]
    $script:RingIcon.Content = (New-Icon $part.Icon 22 'Accent'); $script:RingIcon.Visibility = 'Visible'
    $script:RingNum.Text = "$([int][math]::Round($v.F * 100))"; $script:RingOf.Text = '%'
    $script:RingLabel.Text = (T $part.Name) + "`n" + $v.Text
}

# animation: the segments grow from where they were to their value while the score counts up (~0.9 s, easing out)
function Start-RingAnimation {
    $vals = $script:RingVals
    if ($script:RingHandler) { [Windows.Media.CompositionTarget]::remove_Rendering($script:RingHandler); $script:RingHandler = $null }
    $script:RingAnim = @{ Clock = [Diagnostics.Stopwatch]::StartNew(); From = @($script:RingSeg | ForEach-Object { $_.Now }); FromScore = [int]$script:RingShown
                          To = @($RingParts | ForEach-Object { [double]$vals[$_.Id].F }); ToScore = [int]$script:RingScore }
    $step = {
        $a = $script:RingAnim
        $t = [math]::Min([double]1, $a.Clock.Elapsed.TotalMilliseconds / 900)
        if (-not [Windows.SystemParameters]::ClientAreaAnimation) { $t = 1 }   # animations off in Windows: jump straight to the end
        $e = 1 - [math]::Pow(1 - $t, 3)
        for ($i = 0; $i -lt $script:RingSeg.Count; $i++) {
            $s = $script:RingSeg[$i]; $s.Now = $a.From[$i] + ($a.To[$i] - $a.From[$i]) * $e
            $s.Fill.Data = Get-ArcGeometry $s.From ($s.From + ($s.To - $s.From) * $s.Now)
            $s.Fill.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, $(if ($a.To[$i] -lt 0.5) { 'Amber' } else { 'Accent' }))
        }
        $script:RingShown = [int][math]::Round($a.FromScore + ($a.ToScore - $a.FromScore) * $e)
        if ($script:RingOf.Text -eq '/100') { $script:RingNum.Text = "$($script:RingShown)" }
        if ($t -ge 1) { [Windows.Media.CompositionTarget]::remove_Rendering($script:RingHandler); $script:RingHandler = $null }
    }
    $script:RingHandler = [EventHandler]$step
    [Windows.Media.CompositionTarget]::add_Rendering($script:RingHandler)
}

# the core calls it when the tweak state changes (after the check finishes or after applying)
function Update-HomeStats {
    if (-not $script:RingSeg) { return }
    $script:RingVals = Get-RingValues
    $sum = 0.0; foreach ($p in $RingParts) { $sum += $script:RingVals[$p.Id].F }
    $script:RingScore = [int][math]::Round($sum / $RingParts.Count * 100)
    $low = @($RingParts | Where-Object { $script:RingVals[$_.Id].F -lt 0.8 }).Count
    $script:RingSummary.Text = if (-not $script:RingVals.Known) { T 'Comprobando el estado de los ajustes...' }
                               elseif ($script:RingScore -ge 80) { T 'Tu PC está en buena forma.' }
                               elseif ($script:RingScore -ge 50) { T 'Tu PC está bien, pero hay cosas que mejorar.' }
                               else { T 'Tu PC puede ir bastante mejor.' }
    $script:RingOf.Text = '/100'
    $script:RingLegend.Children.Clear()
    for ($i = 0; $i -lt $RingParts.Count; $i++) {
        $f = $script:RingVals[$RingParts[$i].Id].F
        $it = [Windows.Controls.Border]::new(); $it.Padding = '10,5'; $it.Margin = '2'; $it.CornerRadius = 4; $it.Cursor = 'Hand'; $it.Tag = $i
        $it.Background = [Windows.Media.Brushes]::Transparent
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
        $dot = [Windows.Shapes.Ellipse]::new(); $dot.Width = 8; $dot.Height = 8; $dot.Margin = '0,0,7,0'; $dot.VerticalAlignment = 'Center'
        $dot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, $(if ($f -lt 0.5) { 'Amber' } else { 'Accent' }))
        $nm = New-Text $RingParts[$i].Name 13 'Ink2'; $nm.VerticalAlignment = 'Center'
        $pc = New-Text "$([int][math]::Round($f * 100)) %" 13 'Ink' 'SemiBold'; $pc.Margin = '6,0,0,0'; $pc.VerticalAlignment = 'Center'
        foreach ($x in $dot, $nm, $pc) { [void]$sp.Children.Add($x) }
        $it.Child = $sp
        $it.Add_MouseEnter({ param($s) $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'AccentSoft'); Set-RingHover ([int]$s.Tag) })
        $it.Add_MouseLeave({ param($s) $s.Background = [Windows.Media.Brushes]::Transparent; Set-RingHover -1 })
        $it.Add_MouseLeftButtonUp({ param($s) Select-NavKey $RingParts[[int]$s.Tag].Go })
        [void]$script:RingLegend.Children.Add($it)
    }
    Start-RingAnimation
}

# Free memory: trims the RAM of running processes, empties standby memory (with admin), flushes the DNS cache
# and deletes temp files and crash dumps. Not the recycle bin (that would be permanent) nor the shader cache (causes stutter in games).
function Invoke-HomeFreeUp {
    if ($script:Busy) { return }
    $ramBefore = Get-FreeRam
    $script:FreeWork = Show-Working (T 'Liberando memoria') (T 'Liberando memoria RAM...'); Set-WorkingProgress $script:FreeWork 0.1
    Set-Busy $true
    $async = $false
    try {
        [void](Invoke-TrimWorkingSets)
        Start-Sleep -Milliseconds 400
        if ($script:IsAdmin) { Invoke-StandbyPurge }
        $script:FreeRam = [math]::Max([double]0, [double]((Get-FreeRam) - $ramBefore))
        try { ipconfig /flushdns | Out-Null } catch {}
        $script:FreeWork.Detail.Text = T 'Borrando archivos temporales...'; Set-WorkingProgress $script:FreeWork 0.4; Update-Ui
        $items = @($CleanItems | Where-Object { $_.Id -in 'temp-user', 'temp-win', 'dumps' -and ($script:IsAdmin -or -not $_.Admin) })
        Start-CleanJob $items -OnTick {
            param($P)
            if ($P.Current) { Set-WorkingProgress $script:FreeWork (0.4 + 0.6 * ([math]::Max(0, $P.Index - 1) + 0.5) / [math]::Max(1, $P.Count)) }
        } -Done {
            param($P)
            Close-Working $script:FreeWork; Set-Busy $false
            $msg = "Liberados $(Format-Size $script:FreeRam) de RAM y $(Format-Size $P.Bytes) de disco."
            Write-Log $msg 'OK'; Add-History 'home' 'free-up' $msg
            $script:FreeResult.Text = T $msg; $script:FreeResult.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Accent')
            Update-HomeStats
        }
        $async = $true
    }
    finally { if (-not $async) { Close-Working $script:FreeWork; Set-Busy $false } }
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

# "onShow" from tool.json: every time Home opens it recalculates and the ring is redrawn from scratch
function Update-HomeView {
    if (-not $script:RingSeg) { return }
    # greeting based on the time of day, with your Windows user name and the PC name
    $hour = (Get-Date).Hour
    $hi = if ($hour -lt 12) { T 'Buenos días' } elseif ($hour -lt 20) { T 'Buenas tardes' } else { T 'Buenas noches' }
    $ui.PageTitle.Text = "$hi, $env:USERNAME"
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $os = if ($cv) { ([string]$cv.ProductName -replace 'Windows 10', $(if ([int]$cv.CurrentBuild -ge 22000) { 'Windows 11' } else { 'Windows 10' })) + " $($cv.DisplayVersion)" } else { 'Windows 11' }
    $ui.PageDesc.Text = "$env:COMPUTERNAME  ·  $os  ·  " + (T $(if ($script:IsAdmin) { 'Administrador' } else { 'Sin permisos de administrador' }))
    $ui.PageDesc.Visibility = 'Visible'
    foreach ($s in $script:RingSeg) { $s.Now = 0.0 }; $script:RingShown = 0
    Update-HomeStats

    $script:HomeInfo.Children.Clear()
    if (-not $script:IsAdmin) {
        [void]$script:HomeInfo.Children.Add((New-InfoBar 'lock-simple' 'Ves el estado de todo, pero para aplicar cambios hace falta abrir el panel como administrador.' 'warn' 'Reiniciar como admin' { Restart-AsAdmin }))
    }

    # what to improve, most important first; only what applies to this PC
    $script:HomeSug.Children.Clear()
    $ready = $script:StatusReady -or @($script:Rows.Values | Where-Object { $null -ne $_.Applied }).Count -gt 0
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
    $startup = @(try { Get-StartupEntries | Where-Object Enabled } catch { })
    if ($startup.Count -ge 6) {
        [void]$script:HomeSug.Children.Add((New-Suggestion 'sign-in' (T "$($startup.Count) apps se abren al iniciar Windows") (($startup | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', ') 'Revisar' { Select-NavKey 'startup' }))
    }
    [void]$script:HomeSug.Children.Add((New-Suggestion 'lightning' (T 'Antes de jugar') (T 'Sesión de juego cierra lo que sobra y lo devuelve al terminar.') 'Abrir' { Select-NavKey 'booster' }))
}
