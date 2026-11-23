# Módulo "Instalar apps": instala y actualiza programas con winget (como el apartado Apps de Optimizer / Install de WinUtil)

$AppCatalog = [ordered]@{
    'Tiendas y launchers' = @(
        @{ Id = 'Valve.Steam'; Icon = 'brand-steam'; Name = 'Steam' }
        @{ Id = 'EpicGames.EpicGamesLauncher'; Icon = 'brand-epicgames'; Name = 'Epic Games Launcher' }
        @{ Id = 'GOG.Galaxy'; Icon = 'brand-gogdotcom'; Name = 'GOG Galaxy' }
        @{ Id = 'ElectronicArts.EADesktop'; Icon = 'brand-ea'; Name = 'EA app' }
        @{ Id = 'Ubisoft.Connect'; Icon = 'brand-ubisoft'; Name = 'Ubisoft Connect' }
        @{ Id = 'Blizzard.BattleNet'; Icon = 'brand-battledotnet'; Name = 'Battle.net'; Args = '--location "C:\Program Files (x86)\Battle.net"' }
    )
    'Comunicación y streaming' = @(
        @{ Id = 'Discord.Discord'; Icon = 'brand-discord'; Name = 'Discord' }
        @{ Id = 'OBSProject.OBSStudio'; Icon = 'brand-obsstudio'; Name = 'OBS Studio' }
        @{ Id = 'Parsec.Parsec'; Icon = 'monitor-play'; Name = 'Parsec' }
    )
    'Monitorización' = @(
        @{ Id = 'Guru3D.Afterburner'; Icon = 'brand-msi'; Name = 'MSI Afterburner' }
        @{ Id = 'CPUID.HWMonitor'; Icon = 'thermometer'; Name = 'HWMonitor' }
        @{ Id = 'CPUID.CPU-Z'; Icon = 'cpu'; Name = 'CPU-Z' }
        @{ Id = 'TechPowerUp.GPU-Z'; Icon = 'graphics-card'; Name = 'GPU-Z' }
    )
    'Utilidades' = @(
        @{ Id = '7zip.7zip'; Icon = 'brand-7zip'; Name = '7-Zip' }
        @{ Id = 'VideoLAN.VLC'; Icon = 'brand-vlcmediaplayer'; Name = 'VLC' }
        @{ Id = 'Mozilla.Firefox'; Icon = 'brand-firefoxbrowser'; Name = 'Firefox' }
        @{ Id = 'Brave.Brave'; Icon = 'brand-brave'; Name = 'Brave' }
    )
    'Componentes para juegos' = @(
        @{ Id = 'Microsoft.VCRedist.2015+.x64'; Icon = 'brackets-curly'; Name = 'Visual C++ 2015-2022' }
        @{ Id = 'Microsoft.DirectX'; Icon = 'cube'; Name = 'DirectX (runtime clásico)' }
        @{ Id = 'Microsoft.DotNet.DesktopRuntime.8'; Icon = 'brand-dotnet'; Name = '.NET Desktop Runtime 8' }
    )
}

function Update-AppCard([string]$Id) {
    $c = $script:AppCards[$Id]
    $sel = $script:AppSel.Contains($Id)
    $inst = $script:AppInstalled -contains $Id
    if ($sel) {
        $c.Border.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Accent')
        $c.Check.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Accent')
        $c.Check.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Accent')
        $c.Glyph.Visibility = 'Visible'
    }
    else {
        $c.Border.ClearValue([Windows.Controls.Border]::BorderBrushProperty)
        $c.Check.Background = [Windows.Media.Brushes]::Transparent
        $c.Check.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'RuleStrong')
        $c.Glyph.Visibility = 'Hidden'
    }
    if ($null -eq $script:AppInstalled) { $c.State.Text = (T ''); return }
    if ($inst -and $sel) { $c.State.Text = (T 'Instalada, se actualizará'); $c.State.SetResourceReference($FgProp, 'Accent') }
    elseif ($inst) { $c.State.Text = (T 'Instalada'); $c.State.SetResourceReference($FgProp, 'Good') }
    elseif ($sel) { $c.State.Text = (T 'Se instalará'); $c.State.SetResourceReference($FgProp, 'Accent') }
    else { $c.State.Text = (T 'No instalada'); $c.State.SetResourceReference($FgProp, 'Muted') }
}

function Update-AppBar {
    $n = $script:AppSel.Count
    $script:AppBtnInstall.Content = T $(if ($n -gt 0) { "Instalar seleccionadas ($n)" } else { 'Instalar seleccionadas' })
    $script:AppBtnInstall.IsEnabled = $n -gt 0 -and -not $script:AppRunning
    $script:AppBtnUpgrade.IsEnabled = -not $script:AppRunning
}

function Start-AppScan {
    $script:AppStatus.Text = (T 'Comprobando qué tienes instalado...')
    $tmp = Join-Path $env:TEMP 'optieleven-winget.json'
    $script:AppJob = Start-Job -ArgumentList $tmp -ScriptBlock {
        param($f)
        Remove-Item $f -ErrorAction SilentlyContinue
        winget export -o $f --source winget --accept-source-agreements --disable-interactivity *> $null
        if (Test-Path $f) { (Get-Content $f -Raw | ConvertFrom-Json).Sources.Packages.PackageIdentifier }
    }
    $script:AppScanTimer.Start()
}

function Start-WingetConsole([string]$Title, [string[]]$Commands) {
    $lines = @("`$Host.UI.RawUI.WindowTitle = '$Title'") + $Commands +
             @("Write-Host ''", "Write-Host 'Terminado. Pulsa Intro para cerrar.' -ForegroundColor Green", 'Read-Host | Out-Null')
    # los comandos van codificados en la propia llamada: no hay un .ps1 en disco que otro programa pueda cambiar
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($lines -join "`n")))
    $script:AppProc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc" -PassThru
    $script:AppRunning = $true; Update-AppBar
    $script:AppStatus.Text = (T 'winget está trabajando en su propia ventana. Al cerrarla se actualiza esta lista.')
    $script:AppProcTimer.Start()
}

function New-AppsPage {
    $root = New-Object Windows.Controls.StackPanel
    $script:AppSel = New-Object 'System.Collections.Generic.HashSet[string]'
    $script:AppCards = @{}
    $script:AppInstalled = $null
    $script:AppRunning = $false

    $bar = New-Cols @('*', 'Auto'); $bar.Margin = '0,0,0,6'
    $script:AppStatus = New-Text '' 13 'Muted'; $script:AppStatus.VerticalAlignment = 'Center'
    [void](Add-At $bar $script:AppStatus 0)
    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'
    $script:AppBtnUpgrade = New-Btn 'Actualizar todo'; $script:AppBtnUpgrade.Margin = '0,0,8,0'
    $script:AppBtnInstall = New-Btn 'Instalar seleccionadas' -Primary
    [void]$btns.Children.Add($script:AppBtnUpgrade); [void]$btns.Children.Add($script:AppBtnInstall)
    [void](Add-At $bar $btns 1)
    [void]$root.Children.Add($bar)

    $groupIcons = @{}
    foreach ($group in $AppCatalog.Keys) {
        [void]$root.Children.Add((New-Section $group))
        $wrap = New-Object Windows.Controls.Primitives.UniformGrid; $wrap.Columns = 4; $wrap.Margin = '0,0,-10,0'
        foreach ($app in $AppCatalog[$group]) {
            $card = New-Object Windows.Controls.Border
            $card.Style = $window.FindResource('Row'); $card.RenderTransform = New-Object Windows.Media.TranslateTransform
            $card.Margin = '0,0,10,10'; $card.Padding = '16,14'; $card.Cursor = 'Hand'; $card.Tag = $app.Id
            $g = New-Cols @('50', '*', 'Auto')
            [void](Add-At $g (New-IconWell $app.Icon 36) 0)
            $sp = New-Object Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'
            $nm = New-Text $app.Name 14 'Ink' 'Medium'
            $st = New-Text '' 12 'Muted'; $st.Margin = '0,3,0,0'
            [void]$sp.Children.Add($nm); [void]$sp.Children.Add($st)
            [void](Add-At $g $sp 1)
            $chk = New-Object Windows.Controls.Border; $chk.Width = 22; $chk.Height = 22; $chk.CornerRadius = 11; $chk.BorderThickness = 1.5
            $chk.VerticalAlignment = 'Center'; $chk.Margin = '12,0,0,0'
            $gl = New-Icon 'check' 13 'AccentInk'; $gl.HorizontalAlignment = 'Center'; $gl.Visibility = 'Hidden'
            $chk.Child = $gl
            [void](Add-At $g $chk 2)
            $card.Child = $g
            $card.Add_MouseLeftButtonUp({
                param($src, $e)
                $id = [string]$src.Tag
                if (-not $script:AppSel.Remove($id)) { [void]$script:AppSel.Add($id) }
                Update-AppCard $id; Update-AppBar
            })
            [void]$wrap.Children.Add($card)
            $script:AppCards[$app.Id] = @{ App = $app; Border = $card; State = $st; Check = $chk; Glyph = $gl }
            Update-AppCard $app.Id
        }
        [void]$root.Children.Add($wrap)
    }

    $script:AppBtnInstall.Add_Click({
        $cmds = foreach ($grp in $AppCatalog.Values) {
            foreach ($a in $grp) {
                if ($script:AppSel.Contains($a.Id)) {
                    "Write-Host ''; Write-Host '==> $($a.Name)' -ForegroundColor Cyan"
                    "winget install --id '$($a.Id)' -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity $($a.Args)"
                }
            }
        }
        Write-Log "Instalando con winget: $(@($script:AppSel) -join ', ')"
        Start-WingetConsole 'OptiEleven - instalando apps' $cmds
    })
    $script:AppBtnUpgrade.Add_Click({
        Write-Log 'Actualizando todas las apps con winget.'
        Start-WingetConsole 'OptiEleven - actualizando apps' @(
            "Write-Host 'Buscando actualizaciones...' -ForegroundColor Cyan",
            'winget upgrade --all --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity')
    })

    $script:AppScanTimer = New-Timer 0.5 {
        if ($script:AppJob.State -in 'Completed', 'Failed', 'Stopped') {
            $script:AppScanTimer.Stop()
            $ids = @(Receive-Job $script:AppJob -ErrorAction SilentlyContinue); Remove-Job $script:AppJob -Force
            $script:AppInstalled = @($ids | Where-Object { $_ })
            foreach ($id in $script:AppCards.Keys) { Update-AppCard $id }
            $have = @($script:AppCards.Keys | Where-Object { $script:AppInstalled -contains $_ }).Count
            $script:AppStatus.Text = (T "Tienes $have de $($script:AppCards.Count) instaladas. Marca las que quieras y pulsa Instalar.")
        }
    }
    $script:AppProcTimer = New-Timer 1 {
        if ($script:AppProc.HasExited) {
            $script:AppProcTimer.Stop(); $script:AppRunning = $false
            $script:AppSel.Clear(); Update-AppBar
            Write-Log 'winget ha terminado.' 'OK'
            Start-AppScan
        }
    }
    Update-AppBar
    Start-AppScan
    $root
}
