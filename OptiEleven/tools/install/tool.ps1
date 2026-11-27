# Módulo "Instalar apps": instala y actualiza programas con winget (como el apartado Apps de Optimizer / Install de WinUtil)

# Como Ninite: una versión de cada cosa (la actual), sin variantes por arquitectura ni versiones antiguas.
$AppCatalog = [ordered]@{
    'Juegos' = @(
        @{ Id = 'Valve.Steam'; Icon = 'brand-steam'; Name = 'Steam' }
        @{ Id = 'EpicGames.EpicGamesLauncher'; Icon = 'brand-epicgames'; Name = 'Epic Games Launcher' }
        @{ Id = 'GOG.Galaxy'; Icon = 'brand-gogdotcom'; Name = 'GOG Galaxy' }
        @{ Id = 'ElectronicArts.EADesktop'; Icon = 'brand-ea'; Name = 'EA app' }
        @{ Id = 'Ubisoft.Connect'; Icon = 'brand-ubisoft'; Name = 'Ubisoft Connect' }
        @{ Id = 'Blizzard.BattleNet'; Icon = 'brand-battledotnet'; Name = 'Battle.net'; Args = '--location "C:\Program Files (x86)\Battle.net"' }
        @{ Id = 'Playnite.Playnite'; Icon = 'game-controller'; Name = 'Playnite' }
        @{ Id = 'HeroicGamesLauncher.HeroicGamesLauncher'; Icon = 'joystick'; Name = 'Heroic Games Launcher' }
        @{ Id = 'Overwolf.CurseForge'; Icon = 'brand-curseforge'; Name = 'CurseForge' }
        @{ Id = 'Modrinth.ModrinthApp'; Icon = 'brand-modrinth'; Name = 'Modrinth App' }
        @{ Id = 'RiotGames.Valorant.EU'; Icon = 'game-controller'; Name = 'Valorant (Riot Client)' }
        @{ Id = 'RiotGames.LeagueOfLegends.EUW'; Icon = 'game-controller'; Name = 'League of Legends' }
        @{ Id = 'Mojang.MinecraftLauncher'; Icon = 'cube'; Name = 'Minecraft Launcher' }
        @{ Id = 'Roblox.Roblox'; Icon = 'game-controller'; Name = 'Roblox' }
        @{ Id = 'RockstarGames.Launcher'; Icon = 'game-controller'; Name = 'Rockstar Games Launcher' }
        @{ Id = 'Amazon.Games'; Icon = 'game-controller'; Name = 'Amazon Games' }
        @{ Id = 'ItchIo.Itch'; Icon = 'game-controller'; Name = 'itch.io' }
        @{ Id = 'PrismLauncher.PrismLauncher'; Icon = 'cube'; Name = 'Prism Launcher' }
    )
    'Periféricos' = @(
        @{ Id = 'Logitech.GHUB'; Icon = 'mouse'; Name = 'Logitech G HUB' }
        @{ Id = 'Corsair.iCUE.5'; Icon = 'keyboard'; Name = 'Corsair iCUE' }
        @{ Id = 'SteelSeries.GG'; Icon = 'headset'; Name = 'SteelSeries GG' }
    )
    'Navegadores' = @(
        @{ Id = 'Google.Chrome'; Icon = 'brand-googlechrome'; Name = 'Chrome' }
        @{ Id = 'Mozilla.Firefox'; Icon = 'brand-firefoxbrowser'; Name = 'Firefox' }
        @{ Id = 'Brave.Brave'; Icon = 'brand-brave'; Name = 'Brave' }
        @{ Id = 'Opera.OperaGX'; Icon = 'brand-operagx'; Name = 'Opera GX' }
        @{ Id = 'Opera.Opera'; Icon = 'brand-opera'; Name = 'Opera' }
        @{ Id = 'Vivaldi.Vivaldi'; Icon = 'brand-vivaldi'; Name = 'Vivaldi' }
    )
    'Chat y llamadas' = @(
        @{ Id = 'Discord.Discord'; Icon = 'brand-discord'; Name = 'Discord' }
        @{ Id = 'TeamSpeakSystems.TeamSpeakClient'; Icon = 'brand-teamspeak'; Name = 'TeamSpeak' }
        @{ Id = 'Telegram.TelegramDesktop'; Icon = 'brand-telegram'; Name = 'Telegram' }
        @{ Id = 'OpenWhisperSystems.Signal'; Icon = 'brand-signal'; Name = 'Signal' }
        @{ Id = 'Zoom.Zoom'; Icon = 'brand-zoom'; Name = 'Zoom' }
        @{ Id = 'Microsoft.Teams'; Icon = 'microsoft-teams-logo'; Name = 'Teams' }
        @{ Id = 'SlackTechnologies.Slack'; Icon = 'brand-slack'; Name = 'Slack' }
        @{ Id = 'Mozilla.Thunderbird'; Icon = 'brand-thunderbird'; Name = 'Thunderbird' }
    )
    'Grabar y streaming' = @(
        @{ Id = 'OBSProject.OBSStudio'; Icon = 'brand-obsstudio'; Name = 'OBS Studio' }
        @{ Id = 'Parsec.Parsec'; Icon = 'monitor-play'; Name = 'Parsec' }
        @{ Id = 'ShareX.ShareX'; Icon = 'brand-sharex'; Name = 'ShareX' }
        @{ Id = 'Greenshot.Greenshot'; Icon = 'scissors'; Name = 'Greenshot' }
        @{ Id = 'Skillbrains.Lightshot'; Icon = 'scissors'; Name = 'Lightshot' }
        @{ Id = 'KDE.Kdenlive'; Icon = 'brand-kdenlive'; Name = 'Kdenlive' }
        @{ Id = 'HandBrake.HandBrake'; Icon = 'film-strip'; Name = 'HandBrake' }
    )
    'Música y vídeo' = @(
        @{ Id = 'Spotify.Spotify'; Icon = 'brand-spotify'; Name = 'Spotify' }
        @{ Id = 'VideoLAN.VLC'; Icon = 'brand-vlcmediaplayer'; Name = 'VLC' }
        @{ Id = 'shinchiro.mpv'; Icon = 'brand-mpv'; Name = 'mpv' }
        @{ Id = 'AIMP.AIMP'; Icon = 'music-notes'; Name = 'AIMP' }
        @{ Id = 'PeterPawlowski.foobar2000'; Icon = 'brand-foobar2000'; Name = 'foobar2000' }
        @{ Id = 'Audacity.Audacity'; Icon = 'brand-audacity'; Name = 'Audacity' }
        @{ Id = 'CodecGuide.K-LiteCodecPack.Standard'; Icon = 'play-circle'; Name = 'K-Lite Codecs' }
        @{ Id = 'Plex.Plex'; Icon = 'brand-plex'; Name = 'Plex' }
        @{ Id = 'Apple.iTunes'; Icon = 'music-notes'; Name = 'iTunes' }
    )
    'Imagen y diseño' = @(
        @{ Id = 'dotPDN.PaintDotNet'; Icon = 'paint-brush'; Name = 'Paint.NET' }
        @{ Id = 'GIMP.GIMP.3'; Icon = 'brand-gimp'; Name = 'GIMP' }
        @{ Id = 'KDE.Krita'; Icon = 'brand-krita'; Name = 'Krita' }
        @{ Id = 'Inkscape.Inkscape'; Icon = 'brand-inkscape'; Name = 'Inkscape' }
        @{ Id = 'BlenderFoundation.Blender'; Icon = 'brand-blender'; Name = 'Blender' }
        @{ Id = 'IrfanSkiljan.IrfanView'; Icon = 'image'; Name = 'IrfanView' }
    )
    'Documentos' = @(
        @{ Id = 'TheDocumentFoundation.LibreOffice'; Icon = 'brand-libreoffice'; Name = 'LibreOffice' }
        @{ Id = 'SumatraPDF.SumatraPDF'; Icon = 'file-pdf'; Name = 'SumatraPDF' }
        @{ Id = 'Adobe.Acrobat.Reader.64-bit'; Icon = 'file-pdf'; Name = 'Adobe Acrobat Reader' }
        @{ Id = 'Foxit.FoxitReader'; Icon = 'file-pdf'; Name = 'Foxit PDF Reader' }
        @{ Id = 'Notion.Notion'; Icon = 'brand-notion'; Name = 'Notion' }
        @{ Id = 'Obsidian.Obsidian'; Icon = 'brand-obsidian'; Name = 'Obsidian' }
        @{ Id = 'Notepad++.Notepad++'; Icon = 'brand-notepadplusplus'; Name = 'Notepad++' }
    )
    'Seguridad' = @(
        @{ Id = 'Malwarebytes.Malwarebytes'; Icon = 'brand-malwarebytes'; Name = 'Malwarebytes' }
        @{ Id = 'Bitwarden.Bitwarden'; Icon = 'brand-bitwarden'; Name = 'Bitwarden' }
        @{ Id = 'KeePassXCTeam.KeePassXC'; Icon = 'brand-keepassxc'; Name = 'KeePassXC' }
        @{ Id = 'AgileBits.1Password'; Icon = 'brand-1password'; Name = '1Password' }
        @{ Id = 'Proton.ProtonVPN'; Icon = 'shield-check'; Name = 'Proton VPN' }
        @{ Id = 'NordSecurity.NordVPN'; Icon = 'shield-check'; Name = 'NordVPN' }
    )
    'Archivos y nube' = @(
        @{ Id = '7zip.7zip'; Icon = 'brand-7zip'; Name = '7-Zip' }
        @{ Id = 'RARLab.WinRAR'; Icon = 'file-zip'; Name = 'WinRAR' }
        @{ Id = 'voidtools.Everything'; Icon = 'magnifying-glass'; Name = 'Everything' }
        @{ Id = 'qBittorrent.qBittorrent'; Icon = 'brand-qbittorrent'; Name = 'qBittorrent' }
        @{ Id = 'Google.GoogleDrive'; Icon = 'brand-googledrive'; Name = 'Google Drive' }
        @{ Id = 'Dropbox.Dropbox'; Icon = 'brand-dropbox'; Name = 'Dropbox' }
        @{ Id = 'WinDirStat.WinDirStat'; Icon = 'tree-structure'; Name = 'WinDirStat' }
        @{ Id = 'CodeSector.TeraCopy'; Icon = 'copy'; Name = 'TeraCopy' }
    )
    'Utilidades' = @(
        @{ Id = 'Microsoft.PowerToys'; Icon = 'magic-wand'; Name = 'PowerToys' }
        @{ Id = 'AnyDesk.AnyDesk'; Icon = 'brand-anydesk'; Name = 'AnyDesk' }
        @{ Id = 'TeamViewer.TeamViewer'; Icon = 'brand-teamviewer'; Name = 'TeamViewer' }
        @{ Id = 'Tailscale.Tailscale'; Icon = 'brand-tailscale'; Name = 'Tailscale' }
        @{ Id = 'WireGuard.WireGuard'; Icon = 'brand-wireguard'; Name = 'WireGuard' }
        @{ Id = 'RevoUninstaller.RevoUninstaller'; Icon = 'trash'; Name = 'Revo Uninstaller' }
        @{ Id = 'Rufus.Rufus'; Icon = 'usb'; Name = 'Rufus' }
        @{ Id = 'File-New-Project.EarTrumpet'; Icon = 'speaker-high'; Name = 'EarTrumpet' }
        @{ Id = 'CharlesMilette.TranslucentTB'; Icon = 'app-window'; Name = 'TranslucentTB' }
        @{ Id = 'Flow-Launcher.Flow-Launcher'; Icon = 'magnifying-glass'; Name = 'Flow Launcher' }
        @{ Id = 'rocksdanister.LivelyWallpaper'; Icon = 'image'; Name = 'Lively Wallpaper' }
        @{ Id = 'Google.EarthPro'; Icon = 'globe'; Name = 'Google Earth Pro' }
    )
    'Monitorización' = @(
        @{ Id = 'Guru3D.Afterburner'; Icon = 'brand-msi'; Name = 'MSI Afterburner' }
        @{ Id = 'REALiX.HWiNFO'; Icon = 'pulse'; Name = 'HWiNFO' }
        @{ Id = 'CPUID.HWMonitor'; Icon = 'thermometer'; Name = 'HWMonitor' }
        @{ Id = 'CPUID.CPU-Z'; Icon = 'cpu'; Name = 'CPU-Z' }
        @{ Id = 'TechPowerUp.GPU-Z'; Icon = 'graphics-card'; Name = 'GPU-Z' }
        @{ Id = 'CrystalDewWorld.CrystalDiskInfo'; Icon = 'hard-drive'; Name = 'CrystalDiskInfo' }
    )
    'Programación' = @(
        @{ Id = 'Microsoft.VisualStudioCode'; Icon = 'code'; Name = 'Visual Studio Code' }
        @{ Id = 'Git.Git'; Icon = 'brand-git'; Name = 'Git' }
        @{ Id = 'GitHub.GitHubDesktop'; Icon = 'brand-github'; Name = 'GitHub Desktop' }
        @{ Id = 'Python.Python.3.13'; Icon = 'brand-python'; Name = 'Python 3' }
        @{ Id = 'OpenJS.NodeJS.LTS'; Icon = 'brand-nodedotjs'; Name = 'Node.js LTS' }
        @{ Id = 'Docker.DockerDesktop'; Icon = 'brand-docker'; Name = 'Docker Desktop' }
        @{ Id = 'PuTTY.PuTTY'; Icon = 'terminal'; Name = 'PuTTY' }
    )
    'Componentes para juegos' = @(
        @{ Id = 'Microsoft.VCRedist.2015+.x64'; Icon = 'brackets-curly'; Name = 'Visual C++ Redistributable' }
        @{ Id = 'Microsoft.DirectX'; Icon = 'cube'; Name = 'DirectX (runtime clásico)' }
        @{ Id = 'Microsoft.DotNet.DesktopRuntime.8'; Icon = 'brand-dotnet'; Name = '.NET Desktop Runtime' }
        @{ Id = 'Oracle.JavaRuntimeEnvironment'; Icon = 'code'; Name = 'Java' }
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
    if ($inst -and $sel) { $c.State.Text = (T 'Instalada, se actualizará'); $c.State.SetResourceReference($FgProp, 'Accent'); $c.State.FontWeight = 'SemiBold' }
    elseif ($inst) { $c.State.Text = (T 'Instalada'); $c.State.SetResourceReference($FgProp, 'Cat-Rendimiento'); $c.State.FontWeight = 'SemiBold' }
    elseif ($sel) { $c.State.Text = (T 'Se instalará'); $c.State.SetResourceReference($FgProp, 'Accent'); $c.State.FontWeight = 'SemiBold' }
    else { $c.State.Text = (T 'No instalada'); $c.State.SetResourceReference($FgProp, 'Muted'); $c.State.FontWeight = 'Normal' }
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
# ---------- instalador .exe, como el de Ninite: una ventana con la lista y el progreso, se eleva una sola vez
# Se compila aquí mismo (assets\installer.cs) con el compilador de C# que trae Windows, sin descargar nada.
function ConvertTo-CsString([string]$x) { $x.Replace('\', '\\').Replace('"', '\"') }
function Save-AppInstallerExe([object[]]$Apps, [string]$Path) {
    $assets = Join-Path $script:AppDir 'assets'
    $rows = ($Apps | ForEach-Object { '        new string[] {{ "{0}", "{1}", "{2}" }},' -f (ConvertTo-CsString $_.Id), (ConvertTo-CsString (T $_.Name)), (ConvertTo-CsString ([string]$_.Args)) }) -join "`r`n"
    $m = [ordered]@{
        '__TITLE__' = T 'OptiEleven - instalador de apps'; '__INTRO__' = T 'Instalando {0} apps con winget. Puedes dejarlo trabajando.'
        '__CHECK__' = T 'Comprobando...'; '__INSTALLING__' = T 'Instalando...'; '__DONE__' = T 'Instalada'; '__ALREADY__' = T 'Ya estaba instalada'
        '__FAIL__' = T 'Error (código {0})'; '__WAIT__' = T 'En espera'; '__SUMMARY__' = T '{0} instaladas, {1} ya estaban y {2} con error.'; '__READY__' = T 'Listo'
        '__CLOSE__' = T 'Cerrar'; '__NOWINGET__' = T 'winget no está disponible. Instala "Instalador de aplicación" desde Microsoft Store.'
    }
    $cs = Join-Path $assets 'installer.cs'
    # versión publicada: native\OptiEleven-Apps.exe ya viene compilado (build\Build.ps1) y aquí solo se le añade al final
    # la lista y los textos, sin compilar nada en este PC. Su "Comments" lleva el hash de installer.cs: si no coincide
    # (installer.cs cambiado a mano), se compila como antes.
    $stub = Join-Path $script:AppDir 'native\OptiEleven-Apps.exe'
    if (Test-Path -LiteralPath $stub) {
        $sha = [Security.Cryptography.SHA256]::Create()
        $hash = -join ($sha.ComputeHash([IO.File]::ReadAllBytes($cs))[0..5] | ForEach-Object { $_.ToString('x2') })
        if ([Diagnostics.FileVersionInfo]::GetVersionInfo($stub).Comments -eq $hash) {
            $clean = { param($x) ([string]$x) -replace "[`t`r`n]", ' ' }
            $lines = @("T`t" + (@($m.Values | ForEach-Object { & $clean $_ }) -join "`t"))
            $lines += @($Apps | ForEach-Object { "A`t$(& $clean $_.Id)`t$(& $clean (T $_.Name))`t$(& $clean $_.Args)" })
            $data = [Text.Encoding]::UTF8.GetBytes($lines -join "`n")
            $fs = [IO.File]::Create($Path)
            try {
                $exe = [IO.File]::ReadAllBytes($stub); $fs.Write($exe, 0, $exe.Length)
                $fs.Write($data, 0, $data.Length)
                $fs.Write([BitConverter]::GetBytes([int]$data.Length), 0, 4)
                $magic = [Text.Encoding]::ASCII.GetBytes('OPTIELEVEN-APPS1'); $fs.Write($magic, 0, $magic.Length)
            }
            finally { $fs.Dispose() }
            return
        }
    }
    $src = [IO.File]::ReadAllText($cs).Replace('__APPS__', $rows)
    foreach ($k in $m.Keys) { $src = $src.Replace($k, (ConvertTo-CsString $m[$k])) }
    $tmp = Join-Path $env:TEMP ('optieleven-exe-' + [guid]::NewGuid().ToString('N')); [void](New-Item -ItemType Directory -Path $tmp)
    try {
        [IO.File]::WriteAllText((Join-Path $tmp 'installer.cs'), $src, (New-Object Text.UTF8Encoding $true))
        # pide administrador al abrirse (una sola vez para todas las apps) y se ve nítido con escalado de pantalla
        $manifest = '<?xml version="1.0" encoding="utf-8"?><assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1"><assemblyIdentity version="1.0.0.0" name="OptiEleven.AppInstaller"/>' +
            '<trustInfo xmlns="urn:schemas-microsoft-com:asm.v2"><security><requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3"><requestedExecutionLevel level="requireAdministrator" uiAccess="false"/></requestedPrivileges></security></trustInfo>' +
            '<application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware></windowsSettings></application></assembly>'
        [IO.File]::WriteAllText((Join-Path $tmp 'app.manifest'), $manifest, (New-Object Text.UTF8Encoding $false))
        $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
        $out = Join-Path $tmp 'OptiEleven-Apps.exe'
        $cargs = @('/nologo', '/target:winexe', '/optimize+', "/out:$out", "/win32manifest:$(Join-Path $tmp 'app.manifest')", '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll')
        $ico = Join-Path $assets 'optieleven.ico'; if (Test-Path $ico) { $cargs += "/win32icon:$ico" }
        $log = & $csc @cargs (Join-Path $tmp 'installer.cs') 2>&1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $out)) { throw "csc: $(($log | Out-String).Trim())" }
        Copy-Item -LiteralPath $out -Destination $Path -Force
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
function Get-SelectedApps { @(foreach ($grp in $AppCatalog.Values) { foreach ($a in $grp) { if ($script:AppSel.Contains($a.Id)) { $a } } }) }

# logo real de la app (assets\apps\<id>.png, de la base de iconos de UniGetUI y de Dashboard Icons); si no hay, el icono vectorial
function New-AppLogo($App, [double]$Box = 40) {
    $file = Join-Path $script:AppDir "assets\apps\$(($App.Id.ToLower() -replace '[^a-z0-9.-]', '_')).png"
    if (-not (Test-Path -LiteralPath $file)) { return (New-IconWell $App.Icon $Box) }
    $w = [Windows.Controls.Border]::new(); $w.Width = $Box; $w.Height = $Box; $w.CornerRadius = 10; $w.VerticalAlignment = 'Center'
    $w.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Paper3')
    $bi = [Windows.Media.Imaging.BitmapImage]::new(); $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.UriSource = [Uri]$file; $bi.DecodePixelWidth = 64; $bi.EndInit(); $bi.Freeze()
    $img = [Windows.Controls.Image]::new(); $img.Source = $bi; $img.Width = $Box * 0.7; $img.Height = $Box * 0.7
    [Windows.Media.RenderOptions]::SetBitmapScalingMode($img, 'HighQuality')
    $w.Child = $img
    $w
}
function New-AppsPage {
    $root = [Windows.Controls.StackPanel]::new()
    $script:AppSel = New-Object 'System.Collections.Generic.HashSet[string]'
    $script:AppCards = @{}
    $script:AppInstalled = $null
    $script:AppRunning = $false

    # cabecera como la de Ninite: eliges, y sale un instalador con todo
    $hero = [Windows.Controls.Border]::new(); $hero.CornerRadius = 8; $hero.Padding = '20,18'; $hero.Margin = '0,0,0,6'; $hero.BorderThickness = 1
    $hero.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Glass'); $hero.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'GlassEdge')
    $hg = New-Cols @('Auto', '*', 'Auto')
    $hw = [Windows.Controls.Border]::new(); $hw.Width = 48; $hw.Height = 48; $hw.CornerRadius = 8; $hw.VerticalAlignment = 'Center'
    $hw.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'AccentSoft')
    $hi = New-Icon 'package' 22 'Accent'; $hi.HorizontalAlignment = 'Center'; $hw.Child = $hi
    [void](Add-At $hg $hw 0)
    $ht = [Windows.Controls.StackPanel]::new(); $ht.Margin = '16,0,16,0'; $ht.VerticalAlignment = 'Center'
    $script:AppHeroTitle = New-Text '' 20 'Ink' 'SemiBold'; $script:AppHeroTitle.FontFamily = $window.FindResource('Display')
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

    # buscador: filtra las tarjetas mientras escribes
    $sb = [Windows.Controls.Border]::new(); $sb.CornerRadius = 10; $sb.Padding = '12,0'; $sb.Margin = '0,12,0,0'; $sb.BorderThickness = 1; $sb.MinHeight = 42
    $sb.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Paper2'); $sb.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Rule')
    $sg = New-Cols @('Auto', '*')
    $si = New-Icon 'magnifying-glass' 17 'Muted'; $si.Margin = '0,0,10,0'; [void](Add-At $sg $si 0)
    $sgrid = [Windows.Controls.Grid]::new()
    $script:AppSearch = [Windows.Controls.TextBox]::new(); $script:AppSearch.Background = [Windows.Media.Brushes]::Transparent; $script:AppSearch.BorderThickness = 0
    $script:AppSearch.FontSize = 14.5; $script:AppSearch.VerticalContentAlignment = 'Center'; $script:AppSearch.VerticalAlignment = 'Center'
    $script:AppSearch.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'Ink'); $script:AppSearch.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'Accent')
    $ph = New-Text "Buscar entre $(@($AppCatalog.Values | ForEach-Object { $_ }).Count) apps..." 14.5 'Muted'; $ph.IsHitTestVisible = $false; $ph.VerticalAlignment = 'Center'; $ph.Margin = '2,0,0,0'
    [void]$sgrid.Children.Add($ph); [void]$sgrid.Children.Add($script:AppSearch)
    [void](Add-At $sg $sgrid 1)
    $sb.Child = $sg
    $script:AppSearch.Tag = $ph
    $script:AppSearch.Add_TextChanged({
        param($src)
        $q = $src.Text.Trim()
        $src.Tag.Visibility = if ($q) { 'Hidden' } else { 'Visible' }
        foreach ($sec in $script:AppSections) {
            $any = $false
            foreach ($c in $sec.Cards) { $show = (-not $q) -or ($c.Name -like "*$q*"); $c.Card.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }; if ($show) { $any = $true } }
            $sec.Head.Visibility = if ($any) { 'Visible' } else { 'Collapsed' }; $sec.Wrap.Visibility = $sec.Head.Visibility
        }
    })
    $script:AppSearch.Add_GotKeyboardFocus({ $sb.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Accent') }.GetNewClosure())
    $script:AppSearch.Add_LostKeyboardFocus({ $sb.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Rule') }.GetNewClosure())
    [void]$root.Children.Add($sb)
    $script:AppSections = @()

    $groupIcons = @{}
    foreach ($group in $AppCatalog.Keys) {
        $secHead = New-Section $group; [void]$root.Children.Add($secHead)
        $wrap = [Windows.Controls.Primitives.UniformGrid]::new(); $wrap.Columns = 4; $wrap.Margin = '0,0,-10,0'
        $secCards = @()
        foreach ($app in $AppCatalog[$group]) {
            $card = [Windows.Controls.Border]::new()
            $card.Style = $window.FindResource('Row'); $card.RenderTransform = [Windows.Media.TranslateTransform]::new()
            $card.Margin = '0,0,10,10'; $card.Padding = '16,14'; $card.Cursor = 'Hand'; $card.Tag = $app.Id
            $g = New-Cols @('50', '*', 'Auto')
            [void](Add-At $g (New-AppLogo $app 40) 0)
            $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
            $nm = New-Text $app.Name 14 'Ink' 'Medium'
            $st = New-Text '' 12 'Muted'; $st.Margin = '0,3,0,0'
            [void]$sp.Children.Add($nm); [void]$sp.Children.Add($st)
            [void](Add-At $g $sp 1)
            $chk = [Windows.Controls.Border]::new(); $chk.Width = 22; $chk.Height = 22; $chk.CornerRadius = 11; $chk.BorderThickness = 1
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
            $secCards += @{ Card = $card; Name = $app.Name }
            Update-AppCard $app.Id
        }
        [void]$root.Children.Add($wrap)
        $script:AppSections += @{ Head = $secHead; Wrap = $wrap; Cards = $secCards }
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
        $dlg.FileName = 'OptiEleven-Apps.exe'; $dlg.Filter = T 'Instalador (*.exe)|*.exe'
        $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        if (-not $dlg.ShowDialog($window)) { return }
        try {
            $window.Cursor = [Windows.Input.Cursors]::Wait; Update-Ui
            try { Save-AppInstallerExe $apps $dlg.FileName } finally { $window.Cursor = $null }
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
