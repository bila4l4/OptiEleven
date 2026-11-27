# History: what the panel changed and when, grouped by day. Written by Add-History (OptiEleven.ps1) to history.jsonl.
# Each applied tweak can be undone from its latest entry; undo uses the backup in backup.json, not this file.

function New-HistoryPage {
    $root = [Windows.Controls.StackPanel]::new()
    $script:HistBody = [Windows.Controls.StackPanel]::new()
    [void]$root.Children.Add($script:HistBody)
    $root
}

function Get-HistoryTitle($e) {
    if ($e.source -eq 'tweak') {
        $tw = $Tweaks | Where-Object Id -eq $e.id | Select-Object -First 1
        $name = if ($tw) { T $tw.Name } else { $e.id }
        $verb = if ($e.action -eq 'revert') { T 'Revertido' } else { T 'Aplicado' }
        return "${verb}: $name"
    }
    T $e.text
}

# redrawn every time the page opens ("onShow" in tool.json)
function Update-HistoryView {
    $b = $script:HistBody; if (-not $b) { return }
    $b.Children.Clear()
    $list = @(Get-History | Sort-Object { [string]$_.time } -Descending)
    if (-not $list.Count) {
        $em = New-Text 'Todavía no hay cambios. Lo que apliques, limpies o borres desde el panel aparecerá aquí, con su fecha.' 14 'Muted'
        $em.TextWrapping = 'Wrap'; [void]$b.Children.Add($em); return
    }
    # only the latest time each tweak was applied offers undo
    $latest = @{}
    foreach ($e in $list) { if ($e.source -eq 'tweak' -and $e.ok -and -not $latest.ContainsKey($e.id)) { $latest[$e.id] = $e } }
    $day = $null
    foreach ($e in @($list | Select-Object -First 300)) {
        $t = try { [datetime]::Parse([string]$e.time) } catch { Get-Date }
        if ($t.Date -ne $day) {
            $day = $t.Date
            $culture = try { [Globalization.CultureInfo]::GetCultureInfo($script:LangCode) } catch { [Globalization.CultureInfo]::CurrentCulture }
            $label = if ($day -eq (Get-Date).Date) { T 'Hoy' } elseif ($day -eq (Get-Date).Date.AddDays(-1)) { T 'Ayer' } else { $day.ToString('D', $culture) }
            $h = New-Text $label 13 'Muted' 'SemiBold'; $h.Margin = '2,14,0,6'; [void]$b.Children.Add($h)
        }
        $row = [Windows.Controls.Border]::new(); $row.Style = $window.FindResource('RuleRow'); $row.Margin = '0,0,0,6'
        $g = New-Cols @('60', '*', 'Auto')
        $tm = New-Mono $t.ToString('HH:mm') 12.5 'Muted'; $tm.VerticalAlignment = 'Center'; [void](Add-At $g $tm 0)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
        $tt = New-Text (Get-HistoryTitle $e) 14 $(if ($e.ok) { 'Ink' } else { 'Red' }) 'Medium'; $tt.TextWrapping = 'Wrap'; [void]$sp.Children.Add($tt)
        $sub = if (-not $e.ok) { [string]$e.error } elseif ($e.source -eq 'tweak' -and $e.text) { T $e.text } elseif ($e.changes) { $n = @($e.changes).Count; if ($n -eq 1) { T '1 cambio' } else { T "$n cambios" } } else { '' }
        if ($sub) { $st = New-Text $sub 12.5 'Muted'; $st.TextWrapping = 'Wrap'; $st.Margin = '0,2,0,0'; [void]$sp.Children.Add($st) }
        [void](Add-At $g $sp 1)
        if ($e.changes) {   # before and after for each item, on hover
            $row.ToolTip = (@($e.changes | Select-Object -First 15 | ForEach-Object { "$($_.what):  $(T $_.before)  →  $(T $_.after)" }) -join "`n")
        }
        if ($e.action -eq 'apply' -and $latest[$e.id] -eq $e) {
            $r = $script:Rows[[string]$e.id]
            if ($r -and $r.Applied -eq $true -and -not $r.Tweak.Irreversible) {
                $btn = New-Btn 'Deshacer'; $btn.Tag = [string]$e.id; $btn.VerticalAlignment = 'Center'; $btn.Padding = '14,0'; $btn.MinHeight = 32
                $btn.IsEnabled = $script:IsAdmin -and -not $script:Busy
                if (-not $script:IsAdmin) { $btn.ToolTip = T 'Abre el panel como administrador para deshacer.'; [Windows.Controls.ToolTipService]::SetShowOnDisabled($btn, $true) }
                $btn.Add_Click({ param($s) Undo-HistoryTweak ([string]$s.Tag) })
                [void](Add-At $g $btn 2)
            }
        }
        $row.Child = $g
        [void]$b.Children.Add($row)
    }
}

function Undo-HistoryTweak([string]$Id) {
    $row = $script:Rows[$Id]; if (-not $row) { return }
    $msg = (T '¿Deshacer este ajuste?') + "`n`n" + (T $row.Tweak.Name) + "`n" + (T 'Vuelven los valores que había antes de aplicarlo.')
    if ([Windows.MessageBox]::Show($window, $msg, 'OptiEleven', 'OKCancel', 'Question') -ne 'OK') { return }
    $reboot = $false
    Set-Busy $true
    try { $reboot = Invoke-Tweaks @($row.Tweak) 'Revert' } finally { Set-Busy $false; Update-Status }
    Update-HistoryView
    if ($reboot) { [void][Windows.MessageBox]::Show($window, (T 'Algunos cambios necesitan reiniciar el equipo.'), 'OptiEleven', 'OK', 'Information') }
}
