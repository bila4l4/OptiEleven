# "My games" module: finds Steam, Epic and GOG games (and the ones you add by hand) and applies Windows settings per game.
# All of them are reversible: they come off the same way they go on.

$script:GamesFile = Join-Path $script:Root 'games.json'
$GpuPrefKey = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$LayersKey  = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$IfeoKey    = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
$FsoFlag    = 'DISABLEDXMAXIMIZEDWINDOWEDMODE'

function Find-MainExe([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { return $null }
    $skip = 'unins|crash|setup|redist|dxsetup|vcredist|vc_redist|easyanticheat|eac_|beservice|battleye|report|helper|uploader|cef|ue4prereq|dotnet|installer|update|touchup|launcherpatcher|7za?|python'
    $exes = Get-ChildItem -LiteralPath $Dir -Filter *.exe -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -notmatch $skip }
    ($exes | Sort-Object Length -Descending | Select-Object -First 1).FullName
}

function Get-InstalledGames {
    $games = @()
    # Steam
    try {
        $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath -replace '/', '\'
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        $libs = @($steam)
        if (Test-Path $vdf) { $libs += [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' } }
        foreach ($lib in ($libs | Select-Object -Unique)) {
            foreach ($acf in Get-ChildItem -LiteralPath (Join-Path $lib 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
                $txt = Get-Content -LiteralPath $acf.FullName -Raw
                $name = [regex]::Match($txt, '"name"\s+"([^"]+)"').Groups[1].Value
                $dir = [regex]::Match($txt, '"installdir"\s+"([^"]+)"').Groups[1].Value
                if (-not $name -or $name -match 'Steamworks|Redistributable|Proton|Steam Linux Runtime') { continue }
                $full = Join-Path $lib "steamapps\common\$dir"
                $games += [pscustomobject]@{ Name = $name; Store = 'Steam'; Exe = (Find-MainExe $full); Dir = $full; Manual = $false }
            }
        }
    }
    catch {}
    # Epic
    foreach ($item in Get-ChildItem "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests" -Filter *.item -ErrorAction SilentlyContinue) {
        try {
            $j = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
            if (-not $j.DisplayName -or -not $j.InstallLocation) { continue }
            $exe = if ($j.LaunchExecutable) { Join-Path $j.InstallLocation $j.LaunchExecutable } else { Find-MainExe $j.InstallLocation }
            $games += [pscustomobject]@{ Name = $j.DisplayName; Store = 'Epic'; Exe = $exe; Dir = $j.InstallLocation; Manual = $false }
        }
        catch {}
    }
    # GOG
    foreach ($k in Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p.gameName) { continue }
        $exe = if ($p.exe) { $p.exe } elseif ($p.path -and $p.exeFile) { Join-Path $p.path $p.exeFile } else { $null }
        $games += [pscustomobject]@{ Name = $p.gameName; Store = 'GOG'; Exe = $exe; Dir = $p.path; Manual = $false }
    }
    # added by hand
    if (Test-Path $script:GamesFile) {
        try { foreach ($m in @(Get-Content $script:GamesFile -Raw -Encoding UTF8 | ConvertFrom-Json)) {
            $games += [pscustomobject]@{ Name = $m.Name; Store = 'Manual'; Exe = $m.Exe; Dir = (Split-Path $m.Exe); Manual = $true } } } catch {}
    }
    $games | Where-Object { $_.Exe -and (Test-Path -LiteralPath $_.Exe) } | Sort-Object Name -Unique
}

# --- the three per-game settings
function Get-RegString([string]$Key, [string]$Name) { try { [string](Get-Item -LiteralPath $Key -ErrorAction Stop).GetValue($Name) } catch { '' } }

function Test-GameGpu([string]$Exe) { (Get-RegString $GpuPrefKey $Exe) -match 'GpuPreference=2;' }
function Set-GameGpu([string]$Exe, [bool]$On) {
    $v = (Get-RegString $GpuPrefKey $Exe) -replace 'GpuPreference=\d;', ''
    if ($On) { $v = "GpuPreference=2;$v" }
    if ($v) { Set-RegValue $GpuPrefKey $Exe $v 'String' } else { Remove-RegValue $GpuPrefKey $Exe }
}

function Test-GameFso([string]$Exe) { (Get-RegString $LayersKey $Exe) -match $FsoFlag }
function Set-GameFso([string]$Exe, [bool]$On) {
    $tokens = @((Get-RegString $LayersKey $Exe) -split '\s+' | Where-Object { $_ -and $_ -ne '~' -and $_ -ne $FsoFlag })
    if ($On) { $tokens += $FsoFlag }
    if ($tokens) { Set-RegValue $LayersKey $Exe ('~ ' + ($tokens -join ' ')) 'String' } else { Remove-RegValue $LayersKey $Exe }
}

function Test-GamePrio([string]$Exe) {
    try { (Get-ItemProperty "$IfeoKey\$(Split-Path $Exe -Leaf)\PerfOptions" -Name CpuPriorityClass -ErrorAction Stop).CpuPriorityClass -eq 3 } catch { $false }
}
function Set-GamePrio([string]$Exe, [bool]$On) {
    $k = "$IfeoKey\$(Split-Path $Exe -Leaf)"
    if ($On) { Set-RegValue "$k\PerfOptions" 'CpuPriorityClass' 3 'DWord'; return }
    Remove-RegValue "$k\PerfOptions" 'CpuPriorityClass'
    foreach ($kk in "$k\PerfOptions", $k) {   # cleans up only what was left empty
        $it = Get-Item -LiteralPath $kk -ErrorAction SilentlyContinue
        if ($it -and $it.ValueCount -eq 0 -and $it.SubKeyCount -eq 0) { Remove-Item -LiteralPath $kk -ErrorAction SilentlyContinue }
    }
}

function New-GameSwitch([string]$Exe, [string]$Kind, [bool]$Checked, [bool]$Enabled) {
    $sw = New-Switch; $sw.IsChecked = $Checked; $sw.IsEnabled = $Enabled; $sw.HorizontalAlignment = 'Center'
    $sw.Tag = @{ Exe = $Exe; Kind = $Kind }
    $sw.Add_Click({
        param($src, $e)
        $t = $src.Tag; $on = [bool]$src.IsChecked
        try {
            switch ($t.Kind) { 'gpu' { Set-GameGpu $t.Exe $on } 'fso' { Set-GameFso $t.Exe $on } 'prio' { Set-GamePrio $t.Exe $on } }
            $what = @{ gpu = 'GPU de alto rendimiento'; fso = 'sin optimizaciones de pantalla completa'; prio = 'prioridad alta' }[$t.Kind]
            Write-Log ("{0}: {1} {2}" -f (Split-Path $t.Exe -Leaf), $what, $(if ($on) { 'activado' } else { 'quitado' })) 'OK'
            Add-History 'games' 'toggle' ("{0}: {1} {2}" -f (Split-Path $t.Exe -Leaf), $what, $(if ($on) { 'activado' } else { 'quitado' }))
        }
        catch { $src.IsChecked = -not $on; Write-Log "No se pudo cambiar $($t.Exe): $($_.Exception.Message)" 'ERROR' }
    })
    $sw
}

function Update-GamesList {
    $script:GamesList.Children.Clear()
    $script:GamesStatus.Text = (T 'Buscando juegos en Steam, Epic y GOG...'); Update-Ui
    $games = @(Get-InstalledGames)
    $script:GamesStatus.Text = T $(if ($games) { "$($games.Count) juegos encontrados. Los cambios se aplican al momento y se quitan igual." }
                               else { 'No he encontrado juegos de Steam, Epic ni GOG. Añade el .exe de un juego a mano.' })
    if (-not $games) { return }

    $cols = @('*', '96', '96', '104', '124')
    $hdr = New-Cols $cols; $hdr.Margin = '0,0,0,8'
    $i = 0
    foreach ($h in 'Juego', 'Tienda', 'GPU alta', 'Prioridad alta', 'Sin opt. pantalla completa') {
        $t = New-Text $h 13 'Muted' 'Medium'; if ($i -ge 2) { $t.TextAlignment = 'Center' }; [void](Add-At $hdr $t $i); $i++
    }
    $hdr.ToolTip = (T 'Pantalla completa: quita la capa de Windows que convierte la pantalla completa en ventana sin bordes.')
    [void]$script:GamesList.Children.Add($hdr)
    [void]$script:GamesList.Children.Add((New-Ruled))

    foreach ($gm in $games) {
        $row = [Windows.Controls.Border]::new(); $row.Style = $window.FindResource('RuleRow'); $row.Padding = '0,10'
        $g = New-Cols $cols
        $who = New-Cols @('40', '*')
        $ic = Get-ExeIcon $gm.Exe 28
        if (-not $ic) { $ic = New-Icon 'game-controller' 24 'Ink2' }
        $ic.VerticalAlignment = 'Center'
        [void](Add-At $who $ic 0)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
        [void]$sp.Children.Add((New-Text $gm.Name 15 'Ink' 'Medium'))
        $ex = New-Mono $gm.Exe 12 'Muted'; $ex.TextTrimming = 'CharacterEllipsis'; $ex.ToolTip = $gm.Exe; $ex.Margin = '0,2,0,0'; if (-not $script:Pro) { $ex.Visibility = 'Collapsed' }
        [void]$sp.Children.Add($ex)
        if ($gm.Manual) {
            $rm = New-Text 'Quitar de la lista' 12.5 'Muted'; $rm.Cursor = 'Hand'; $rm.TextDecorations = 'Underline'; $rm.Tag = $gm.Exe; $rm.Margin = '0,4,0,0'
            $rm.Add_MouseLeftButtonUp({
                param($src, $e)
                $keep = @(Get-Content $script:GamesFile -Raw -Encoding UTF8 | ConvertFrom-Json | Where-Object Exe -ne $src.Tag)
                ConvertTo-Json @($keep) -Depth 3 | Set-Content $script:GamesFile -Encoding UTF8
                Update-GamesList
            })
            [void]$sp.Children.Add($rm)
        }
        [void](Add-At $who $sp 1)
        [void](Add-At $g $who 0)
        $chipBox = [Windows.Controls.Border]::new(); $chipBox.HorizontalAlignment = 'Left'; $chipBox.VerticalAlignment = 'Center'
        $chipBox.Child = (New-Chip $gm.Store 'Paper3' 'Ink2')
        [void](Add-At $g $chipBox 1)
        [void](Add-At $g (New-GameSwitch $gm.Exe 'gpu' (Test-GameGpu $gm.Exe) $true) 2)
        [void](Add-At $g (New-GameSwitch $gm.Exe 'prio' (Test-GamePrio $gm.Exe) $script:IsAdmin) 3)
        [void](Add-At $g (New-GameSwitch $gm.Exe 'fso' (Test-GameFso $gm.Exe) $true) 4)
        $row.Child = $g
        [void]$script:GamesList.Children.Add($row)
        Update-Ui
    }
}

function New-GamesPage {
    $root = [Windows.Controls.StackPanel]::new()
    $bar = New-Cols @('*', 'Auto'); $bar.Margin = '0,0,0,16'
    $script:GamesStatus = New-Text '' 14 'Muted'; $script:GamesStatus.VerticalAlignment = 'Center'; $script:GamesStatus.Margin = '0,0,16,0'
    [void](Add-At $bar $script:GamesStatus 0)
    $btns = [Windows.Controls.StackPanel]::new(); $btns.Orientation = 'Horizontal'
    $bAdd = New-Btn 'Añadir un juego'; $bAdd.Margin = '0,0,8,0'
    $bAdd.Add_Click({
        $dlg = New-Object Microsoft.Win32.OpenFileDialog; $dlg.Filter = T 'Ejecutable del juego (*.exe)|*.exe'
        if ($dlg.ShowDialog($window)) {
            $list = @(); if (Test-Path $script:GamesFile) { $list = @(Get-Content $script:GamesFile -Raw -Encoding UTF8 | ConvertFrom-Json) }
            $list += [pscustomobject]@{ Name = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName); Exe = $dlg.FileName }
            ConvertTo-Json @($list) -Depth 3 | Set-Content $script:GamesFile -Encoding UTF8
            Update-GamesList
        }
    })
    $bScan = New-Btn 'Buscar de nuevo'
    $bScan.Add_Click({ Update-GamesList })
    [void]$btns.Children.Add($bAdd); [void]$btns.Children.Add($bScan)
    [void](Add-At $bar $btns 1)
    [void]$root.Children.Add($bar)
    $script:GamesList = [Windows.Controls.StackPanel]::new()
    [void]$root.Children.Add($script:GamesList)
    Update-GamesList
    $root
}
