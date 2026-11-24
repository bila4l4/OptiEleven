# Módulo "Inicio": programas que arrancan con Windows.
# Se activan/desactivan igual que en el Administrador de tareas (claves StartupApproved), así que es reversible.

$StartupSources = @(
    @{ Kind = 'Reg';    Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';
       Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Scope = 'Tu usuario'; Admin = $false }
    @{ Kind = 'Reg';    Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';
       Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'; Scope = 'Todos los usuarios'; Admin = $true }
    @{ Kind = 'Reg';    Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';
       Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Scope = 'Todos los usuarios'; Admin = $true }
    @{ Kind = 'Folder'; Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";
       Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Scope = 'Tu usuario'; Admin = $false }
    @{ Kind = 'Folder'; Path = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp";
       Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Scope = 'Todos los usuarios'; Admin = $true }
)

function Get-StartupApproved([string]$Key, [string]$Name) {
    try {
        $v = (Get-Item -LiteralPath $Key -ErrorAction Stop).GetValue($Name)
        if ($v -is [byte[]] -and $v.Length -gt 0) { return (($v[0] -band 1) -eq 0) }
    }
    catch {}
    return $true
}

function Set-StartupApproved([string]$Key, [string]$Name, [bool]$On) {
    if (-not (Test-Path -LiteralPath $Key)) { New-Item -Path $Key -Force | Out-Null }
    $bytes = New-Object byte[] 12
    if ($On) { $bytes[0] = 2 } else { $bytes[0] = 3; [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($bytes, 4) }
    New-ItemProperty -LiteralPath $Key -Name $Name -Value $bytes -PropertyType Binary -Force | Out-Null
}

function Get-StartupEntries {
    $shell = New-Object -ComObject WScript.Shell
    foreach ($s in $StartupSources) {
        if ($s.Kind -eq 'Reg') {
            if (-not (Test-Path -LiteralPath $s.Path)) { continue }
            $k = Get-Item -LiteralPath $s.Path
            foreach ($n in $k.GetValueNames()) {
                if (-not $n) { continue }
                [pscustomobject]@{ Name = $n; Command = [string]$k.GetValue($n); Scope = $s.Scope; Approved = $s.Approved; Admin = $s.Admin
                                   Enabled = (Get-StartupApproved $s.Approved $n) }
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $s.Path)) { continue }
            foreach ($f in Get-ChildItem -LiteralPath $s.Path -File -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini') {
                $cmd = $f.FullName
                if ($f.Extension -eq '.lnk') { try { $cmd = $shell.CreateShortcut($f.FullName).TargetPath } catch {} }
                [pscustomobject]@{ Name = $f.BaseName; Command = $cmd; Scope = $s.Scope; Approved = $s.Approved; Admin = $s.Admin
                                   Enabled = (Get-StartupApproved $s.Approved $f.Name); FileName = $f.Name }
            }
        }
    }
}

function Update-StartupList {
    $script:StartupList.Children.Clear()
    $items = @(Get-StartupEntries | Sort-Object @{ e = { -not $_.Enabled } }, Name)
    $on = @($items | Where-Object Enabled).Count
    $script:StartupStatus.Text = (T "$on de $($items.Count) programas arrancan con Windows. Cada uno que quites es memoria y CPU libres al jugar.")
    if (-not $items) { [void]$script:StartupList.Children.Add((New-Text 'No hay programas de inicio registrados.' 13 'Muted')); return }
    [void]$script:StartupList.Children.Add((New-Ruled))
    foreach ($it in $items) {
        $card = New-Object Windows.Controls.Border
        $card.Style = $window.FindResource('RuleRow')
        $g = New-Cols @('52', '*', 'Auto')
        $ic = Get-ExeIcon $it.Command 28
        if ($ic) { $ic.VerticalAlignment = 'Top'; $ic.HorizontalAlignment = 'Left'; $ic.Margin = '3,3,0,0'; [void](Add-At $g $ic 0) }
        else { [void](Add-At $g (New-IconWell 'sign-in') 0) }
        $sp = New-Object Windows.Controls.StackPanel
        $nm = New-Text $it.Name 15 'Ink' 'Medium'
        $cmd = New-Mono $it.Command 12 'Muted'; $cmd.TextTrimming = 'CharacterEllipsis'; $cmd.Margin = '0,3,0,0'; $cmd.ToolTip = $it.Command; if (-not $script:Pro) { $cmd.Visibility = 'Collapsed' }
        $meta = New-Object Windows.Controls.WrapPanel; $meta.Margin = '0,8,0,0'
        [void]$meta.Children.Add((New-Chip $it.Scope 'Paper3' 'Ink2'))
        foreach ($el in $nm, $cmd, $meta) { [void]$sp.Children.Add($el) }
        [void](Add-At $g $sp 1)
        $sw = New-Switch; $sw.Margin = '20,0,0,0'; $sw.IsChecked = $it.Enabled
        [Windows.Automation.AutomationProperties]::SetName($sw, $it.Name)
        $sw.Tag = $it
        if ($it.Admin -and -not $script:IsAdmin) { $sw.IsEnabled = $false; $sw.ToolTip = (T 'Necesita permisos de administrador') }
        $sw.Add_Click({
            param($src, $e)
            $entry = $src.Tag
            $valueName = if ($entry.FileName) { $entry.FileName } else { $entry.Name }
            try {
                Set-StartupApproved $entry.Approved $valueName ([bool]$src.IsChecked)
                Write-Log ("Inicio: {0} {1}" -f $entry.Name, $(if ($src.IsChecked) { 'activado' } else { 'desactivado' })) 'OK'
            }
            catch { $src.IsChecked = -not $src.IsChecked; Write-Log "Inicio: no se pudo cambiar $($entry.Name): $($_.Exception.Message)" 'ERROR' }
            $all = @($script:StartupList.Children | Where-Object { $_.Child -is [Windows.Controls.Grid] } | ForEach-Object { $_.Child.Children | Where-Object { $_ -is [Windows.Controls.Primitives.ToggleButton] } })
            $script:StartupStatus.Text = (T "$(@($all | Where-Object IsChecked).Count) de $($all.Count) programas arrancan con Windows. Cada uno que quites es memoria y CPU libres al jugar.")
        })
        [void](Add-At $g $sw 2)
        $card.Child = $g
        [void]$script:StartupList.Children.Add($card)
    }
}

function New-StartupPage {
    $root = New-Object Windows.Controls.StackPanel
    $bar = New-Cols @('*', 'Auto'); $bar.Margin = '0,0,0,14'
    $script:StartupStatus = New-Text '' 13 'Muted'; $script:StartupStatus.VerticalAlignment = 'Center'; $script:StartupStatus.Margin = '0,0,16,0'
    [void](Add-At $bar $script:StartupStatus 0)
    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'
    $b1 = New-Btn 'Apps de la Store'; $b1.Margin = '0,0,8,0'; $b1.ToolTip = (T 'Teams, Spotify y otras apps de la Store se gestionan en Configuración')
    $b1.Add_Click({ Start-Process 'ms-settings:startupapps' })
    $b2 = New-Btn 'Volver a leer'
    $b2.Add_Click({ Update-StartupList })
    [void]$btns.Children.Add($b1); [void]$btns.Children.Add($b2)
    [void](Add-At $bar $btns 1)
    [void]$root.Children.Add($bar)
    $script:StartupList = New-Object Windows.Controls.StackPanel
    [void]$root.Children.Add($script:StartupList)
    Update-StartupList
    $root
}
