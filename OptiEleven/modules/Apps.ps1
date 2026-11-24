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
    $script:AppHeroTitle.Text = T $(if ($n -eq 0) { 'Elige tus apps' } elseif ($n -eq 1) { '1 app elegida' } else { "$n apps elegidas" })
    $script:AppBtnInstall.Content = T $(if ($n -gt 0) { "Instalar ahora ($n)" } else { 'Instalar ahora' })
    $script:AppBtnInstall.IsEnabled = $n -gt 0 -and -not $script:AppRunning
    $script:AppBtnPack.IsEnabled = $n -gt 0
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

# ---------- instalador único (como Ninite): un solo archivo que instala todo lo elegido, en cualquier PC
function Remove-Accents([string]$Text) {
    # el .cmd se guarda en ASCII: cmd.exe no lleva bien la marca UTF-8 al principio del archivo
    $n = $Text.Normalize([Text.NormalizationForm]::FormD)
    (-join ($n.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })) -replace '[^\x20-\x7E\r\n\t]', ''
}
function Get-AppInstallScript([object[]]$Apps) {
    $q = { param($x) "'" + ($x -replace "'", "''") + "'" }
    $list = ($Apps | ForEach-Object { "    @{ Id = $(& $q $_.Id); Name = $(& $q (T $_.Name)); Args = $(& $q ([string]$_.Args)) }" }) -join "`r`n"
    $m = @{
        Title = T 'OptiEleven - instalador de apps'; Intro = T 'Instalando {0} apps con winget. Puedes dejarlo trabajando; no cierres esta ventana.'
        NoWinget = T 'winget no está disponible. Instala "Instalador de aplicación" desde Microsoft Store y vuelve a abrir este archivo.'
        Already = T 'ya estaba instalada'; Done = T 'instalada'; Fail = T 'no se pudo instalar (código {0})'
        Summary = T 'Listo: {0} instaladas, {1} ya estaban y {2} con error.'; Close = T 'Pulsa Intro para cerrar.'
    }
    foreach ($k in @($m.Keys)) { $m[$k] = & $q $m[$k] }
@"
`$Host.UI.RawUI.WindowTitle = $($m.Title)
`$apps = @(
$list
)
Write-Host ''
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Host ($($m.NoWinget)) -ForegroundColor Yellow; Write-Host ''; Read-Host ($($m.Close)) | Out-Null; return }
Write-Host ($($m.Intro) -f `$apps.Count) -ForegroundColor Cyan
`$ok = 0; `$had = 0; `$bad = 0; `$i = 0
foreach (`$a in `$apps) {
    `$i++
    Write-Host ''
    Write-Host ('[{0}/{1}] {2}' -f `$i, `$apps.Count, `$a.Name) -ForegroundColor White
    winget list --id `$a.Id -e --accept-source-agreements --disable-interactivity *> `$null
    if (`$LASTEXITCODE -eq 0) { Write-Host ('  ' + $($m.Already)) -ForegroundColor DarkGray; `$had++; continue }
    `$cmd = "winget install --id '`$(`$a.Id)' -e --silent --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity `$(`$a.Args)"
    Invoke-Expression `$cmd *> `$null
    if (`$LASTEXITCODE -eq 0) { Write-Host ('  ' + $($m.Done)) -ForegroundColor Green; `$ok++ }
    else { Write-Host ('  ' + ($($m.Fail) -f `$LASTEXITCODE)) -ForegroundColor Red; `$bad++ }
}
Write-Host ''
Write-Host ($($m.Summary) -f `$ok, `$had, `$bad) -ForegroundColor Cyan
Write-Host ''
Read-Host ($($m.Close)) | Out-Null
"@
}
function Save-AppInstaller([object[]]$Apps, [string]$Path) {
    # .cmd que se eleva solo una vez (como Ninite) y ejecuta el PowerShell que lleva dentro
    $ps = Get-AppInstallScript $Apps
    $cmd = @"
@echo off
rem OptiEleven - instalador de apps. Generado por OptiEleven (https://github.com/bila4l4/OptiEleven).
rem Instala con winget, en silencio, las apps elegidas; las que ya estan instaladas se saltan.
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
set "OE_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "`$t = [IO.File]::ReadAllText(`$env:OE_SELF); Invoke-Expression (`$t.Substring(`$t.IndexOf('#OE-PS' + '-START#')))"
exit /b
#OE-PS-START#
$ps
"@
    [IO.File]::WriteAllText($Path, (Remove-Accents ($cmd -replace "(?<!`r)`n", "`r`n")), [Text.Encoding]::ASCII)
}
function Get-SelectedApps { @(foreach ($grp in $AppCatalog.Values) { foreach ($a in $grp) { if ($script:AppSel.Contains($a.Id)) { $a } } }) }

function New-AppsPage {
    $root = [Windows.Controls.StackPanel]::new()
    $script:AppSel = New-Object 'System.Collections.Generic.HashSet[string]'
    $script:AppCards = @{}
    $script:AppInstalled = $null
    $script:AppRunning = $false

    # cabecera como la de Ninite: eliges, y sale un instalador con todo
    $hero = [Windows.Controls.Border]::new(); $hero.CornerRadius = 12; $hero.Padding = '22,18'; $hero.Margin = '0,0,0,6'; $hero.BorderThickness = 1.5
    $hero.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Paper2'); $hero.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Cat-Actualizaciones')
    $hg = New-Cols @('Auto', '*', 'Auto')
    $hw = [Windows.Controls.Border]::new(); $hw.Width = 56; $hw.Height = 56; $hw.CornerRadius = 13; $hw.VerticalAlignment = 'Center'
    $hw.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Cat-Actualizaciones')
    $hi = New-Icon 'package' 30 'AccentInk'; $hi.HorizontalAlignment = 'Center'; $hw.Child = $hi
    [void](Add-At $hg $hw 0)
    $ht = [Windows.Controls.StackPanel]::new(); $ht.Margin = '16,0,16,0'; $ht.VerticalAlignment = 'Center'
    $script:AppHeroTitle = New-Text '' 22 'Ink' 'Bold'; $script:AppHeroTitle.FontFamily = $window.FindResource('Display')
    $script:AppStatus = New-Text '' 13.5 'Ink2'; $script:AppStatus.Margin = '0,4,0,0'
    [void]$ht.Children.Add($script:AppHeroTitle); [void]$ht.Children.Add($script:AppStatus)
    [void](Add-At $hg $ht 1)
    $btns = [Windows.Controls.StackPanel]::new(); $btns.Orientation = 'Horizontal'; $btns.VerticalAlignment = 'Center'
    $script:AppBtnUpgrade = New-Btn 'Actualizar todo'; $script:AppBtnUpgrade.Margin = '0,0,8,0'; $script:AppBtnUpgrade.MinHeight = 44
    $script:AppBtnUpgrade.ToolTip = (T 'Actualiza con winget todas las apps que tengas instaladas.')
    $script:AppBtnPack = New-Btn 'Crear instalador'; $script:AppBtnPack.Margin = '0,0,8,0'; $script:AppBtnPack.MinHeight = 44
    $script:AppBtnPack.ToolTip = (T 'Guarda un solo archivo que instala todo lo elegido en cualquier PC, como Ninite.')
    $script:AppBtnInstall = New-Btn 'Instalar ahora' -Primary; $script:AppBtnInstall.MinHeight = 44; $script:AppBtnInstall.FontSize = 15; $script:AppBtnInstall.Padding = '22,0'
    foreach ($b in $script:AppBtnUpgrade, $script:AppBtnPack, $script:AppBtnInstall) { [void]$btns.Children.Add($b) }
    [void](Add-At $hg $btns 2)
    $hero.Child = $hg
    [void]$root.Children.Add($hero)

    $groupIcons = @{}
    foreach ($group in $AppCatalog.Keys) {
        [void]$root.Children.Add((New-Section $group))
        $wrap = [Windows.Controls.Primitives.UniformGrid]::new(); $wrap.Columns = 4; $wrap.Margin = '0,0,-10,0'
        foreach ($app in $AppCatalog[$group]) {
            $card = [Windows.Controls.Border]::new()
            $card.Style = $window.FindResource('Row'); $card.RenderTransform = [Windows.Media.TranslateTransform]::new()
            $card.Margin = '0,0,10,10'; $card.Padding = '16,14'; $card.Cursor = 'Hand'; $card.Tag = $app.Id
            $g = New-Cols @('50', '*', 'Auto')
            [void](Add-At $g (New-IconWell $app.Icon 36) 0)
            $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
            $nm = New-Text $app.Name 14 'Ink' 'Medium'
            $st = New-Text '' 12 'Muted'; $st.Margin = '0,3,0,0'
            [void]$sp.Children.Add($nm); [void]$sp.Children.Add($st)
            [void](Add-At $g $sp 1)
            $chk = [Windows.Controls.Border]::new(); $chk.Width = 22; $chk.Height = 22; $chk.CornerRadius = 11; $chk.BorderThickness = 1.5
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
        $apps = Get-SelectedApps
        if (-not $apps) { return }
        Write-Log "Instalando con winget: $(($apps | ForEach-Object Name) -join ', ')"
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-AppInstallScript $apps)))
        $script:AppProc = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc" -PassThru
        $script:AppRunning = $true; Update-AppBar
        $script:AppStatus.Text = (T 'winget está trabajando en su propia ventana. Al cerrarla se actualiza esta lista.')
        $script:AppProcTimer.Start()
    })
    $script:AppBtnPack.Add_Click({
        $apps = Get-SelectedApps
        if (-not $apps) { return }
        $dlg = [Microsoft.Win32.SaveFileDialog]::new()
        $dlg.FileName = 'OptiEleven-Apps.cmd'; $dlg.Filter = T 'Instalador (*.cmd)|*.cmd'
        $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        if (-not $dlg.ShowDialog($window)) { return }
        try {
            Save-AppInstaller $apps $dlg.FileName
            Write-Log "Instalador creado con $($apps.Count) apps: $($dlg.FileName)" 'OK'
            $script:AppStatus.Text = (T "Instalador creado: $([IO.Path]::GetFileName($dlg.FileName)). Ábrelo en cualquier PC con Windows 10 u 11 y lo instala todo de una vez.")
        }
        catch { Write-Log "No se pudo crear el instalador: $($_.Exception.Message)" 'ERROR' }
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
            $script:AppStatus.Text = (T "Tienes $have de $($script:AppCards.Count) instaladas. Márcalas y pulsa Instalar ahora, o crea un instalador para otro PC.")
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
