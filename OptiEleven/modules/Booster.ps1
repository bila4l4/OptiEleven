# Módulo "Game Booster" (idea de Razer Cortex / Hone): antes de jugar cierra apps y pausa servicios;
# al terminar lo devuelve todo. El estado se guarda en boost.json, así que se puede restaurar aunque el panel se cierre.

$BoostApps = @(
    @{ Icon = 'cloud'; Name = 'OneDrive';            Proc = @('OneDrive');                         On = $true;  Desc = 'Sincronización de archivos' }
    @{ Icon = 'microsoft-teams-logo'; Name = 'Microsoft Teams';     Proc = @('ms-teams', 'Teams');                On = $true;  Desc = 'Chat de trabajo' }
    @{ Icon = 'newspaper'; Name = 'Widgets';            Proc = @('Widgets', 'WidgetService');          On = $true;  Desc = 'Noticias y tiempo' }
    @{ Icon = 'device-mobile'; Name = 'Enlace móvil';       Proc = @('PhoneExperienceHost');               On = $true;  Desc = 'Conexión con el móvil' }
    @{ Icon = 'brand-adobecreativecloud'; Name = 'Adobe Creative Cloud'; Proc = @('Creative Cloud', 'CCXProcess', 'AdobeIPCBroker', 'CoreSync'); On = $true; Desc = 'Actualizador y sincronización' }
    @{ Icon = 'brand-docker'; Name = 'Docker Desktop';     Proc = @('Docker Desktop', 'com.docker.backend'); On = $true; Desc = 'Contenedores y su máquina virtual' }
    @{ Icon = 'browsers'; Name = 'Navegadores';        Proc = @('chrome', 'msedge', 'firefox', 'brave', 'opera'); On = $false; Desc = 'Cierra pestañas sin guardar' }
    @{ Icon = 'brand-spotify'; Name = 'Spotify';            Proc = @('Spotify');                           On = $false; Desc = 'Música' }
    @{ Icon = 'brand-discord'; Name = 'Discord';            Proc = @('Discord');                           On = $false; Desc = 'Déjalo abierto si hablas mientras juegas' }
)
$BoostServices = @(
    @{ Icon = 'arrows-clockwise'; Name = 'wuauserv';  Label = 'Windows Update';                 On = $true }
    @{ Icon = 'cloud-arrow-down'; Name = 'BITS';      Label = 'Transferencia en segundo plano';  On = $true }
    @{ Icon = 'share-network'; Name = 'DoSvc';     Label = 'Optimización de distribución';    On = $true }
    @{ Icon = 'files'; Name = 'WSearch';   Label = 'Indexación de búsqueda';          On = $true }
    @{ Icon = 'hard-drives'; Name = 'SysMain';   Label = 'SysMain';                         On = $true }
    @{ Icon = 'printer'; Name = 'Spooler';   Label = 'Cola de impresión';               On = $false }
    @{ Icon = 'broadcast'; Name = 'DiagTrack'; Label = 'Telemetría';                      On = $true }
)
$script:BoostFile = Join-Path $script:Secure 'boost.json'   # carpeta solo de administradores: guarda servicios y rutas a reabrir

# vaciar la lista de memoria en espera (lo que hace ISLC): NtSetSystemInformation con MemoryPurgeStandbyList
if (-not ('GP.Mem' -as [type])) {
    Add-Type -Namespace GP -Name Mem -MemberDefinition @'
[DllImport("ntdll.dll")] public static extern int NtSetSystemInformation(int infoClass, ref int info, int length);
[DllImport("advapi32.dll", SetLastError = true)] public static extern bool OpenProcessToken(IntPtr h, int access, out IntPtr token);
[DllImport("advapi32.dll", SetLastError = true)] public static extern bool LookupPrivilegeValue(string sys, string name, out long luid);
[StructLayout(LayoutKind.Sequential, Pack = 4)] public struct TokPriv { public int Count; public long Luid; public int Attr; }
[DllImport("advapi32.dll", SetLastError = true)] public static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokPriv newState, int len, IntPtr prev, IntPtr ret);
[DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
public static int PurgeStandby() {
    IntPtr tok; if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return -1;
    TokPriv tp = new TokPriv(); tp.Count = 1; tp.Attr = 2;
    if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out tp.Luid)) return -2;
    AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    int cmd = 4; return NtSetSystemInformation(80, ref cmd, 4);
}
'@
}

# recortar la memoria de trabajo de los procesos abiertos (lo que hacen los "RAM boosters"): Windows pasa a la
# lista de espera las páginas que no se están usando, y al vaciarla después queda como RAM libre para el juego
if (-not ('GP.Ws' -as [type])) {
    Add-Type -Namespace GP -Name Ws -MemberDefinition '[DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr h);'
}
function Invoke-TrimWorkingSets {
    $n = 0
    foreach ($p in Get-Process) {
        if ($p.Id -le 4) { continue }
        try { if ([GP.Ws]::EmptyWorkingSet($p.Handle)) { $n++ } } catch {}   # procesos protegidos: sin acceso, se saltan
    }
    $n
}
function Get-FreeRam { [double](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB }

# Boost FPS: todo de una vez antes de jugar
function Invoke-BoostFps {
    $msg = "Boost FPS va a:`n`n  - Cerrar las apps marcadas abajo y pausar los servicios marcados`n  - Poner el modo de energía al máximo`n  - Liberar la memoria RAM de los procesos abiertos`n  - Hacer la limpieza completa: temporales, cachés, sombreadores, miniaturas y papelera`n`nLa papelera se vacía para siempre, y la primera partida de cada juego puede ir a tirones mientras se rehace la caché de sombreadores.`n`nAl acabar de jugar, pulsa `"Terminar y restaurar`"."
    if ([Windows.MessageBox]::Show($window, (T $msg), 'OptiEleven', 'OKCancel', 'Question') -ne 'OK') { return }
    foreach ($k in $script:FpsSteps.Keys) { $script:FpsSteps[$k].Text = '...'; $script:FpsSteps[$k].SetResourceReference($FgProp, 'Muted') }
    $ramBefore = Get-FreeRam
    $script:BoostPower.IsChecked = $true; $script:BoostPurge.IsChecked = $false   # la memoria se vacía al final, después de recortar
    if (-not (Get-BoostState)) { Start-Boost }
    $st = Get-BoostState
    Set-Busy $true
    try {
        $script:FpsSteps.Apps.Text = "$(@($st.Apps | Where-Object { $_ }).Count)"
        $script:FpsSteps.Svc.Text = "$(@($st.Servicios | Where-Object { $_ }).Count)"
        Write-Log 'Boost FPS: liberando memoria...'; Update-Ui
        $trimmed = Invoke-TrimWorkingSets
        Start-Sleep -Milliseconds 400
        Invoke-StandbyPurge
        $freedRam = [math]::Max(0, (Get-FreeRam) - $ramBefore)
        $script:FpsSteps.Ram.Text = '+' + (Format-Size $freedRam)
        Write-Log "Boost FPS: memoria recortada en $trimmed procesos, $(Format-Size $freedRam) más de RAM libre." 'OK'
        $cleaned = 0
        foreach ($it in $CleanItems) {
            $before = Get-CleanBytes $it
            Write-Log "Limpiando: $($it.Name)"; Update-Ui
            Invoke-CleanItem $it
            $cleaned += [math]::Max(0, $before - (Get-CleanBytes $it))
            $script:FpsSteps.Clean.Text = Format-Size $cleaned
        }
        Write-Log "Boost FPS listo: $(Format-Size $freedRam) de RAM liberada y $(Format-Size $cleaned) de disco limpiados." 'OK'
        foreach ($k in $script:FpsSteps.Keys) { $script:FpsSteps[$k].SetResourceReference($FgProp, 'Accent') }
        if ($script:CleanRows) { foreach ($r in $script:CleanRows.Values) { $r.Bytes = Get-CleanBytes $r.Item; $r.SizeTb.Text = Format-Size $r.Bytes }; Update-CleanTotal }
    }
    finally { Set-Busy $false; $script:BoostPurge.IsChecked = $true; Update-BoostView }
}

function New-FpsHero {
    $card = [Windows.Controls.Border]::new(); $card.CornerRadius = 12; $card.Padding = '24,22,24,20'; $card.Margin = '0,0,0,8'
    $card.SetResourceReference($BgProp, 'Paper2'); $card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Accent'); $card.BorderThickness = 1.5
    $outer = [Windows.Controls.StackPanel]::new()
    $top = New-Cols @('Auto', '*', 'Auto')
    $well = [Windows.Controls.Border]::new(); $well.Width = 64; $well.Height = 64; $well.CornerRadius = 14; $well.VerticalAlignment = 'Center'
    $well.SetResourceReference($BgProp, 'Accent')
    $ic = New-Icon 'rocket-launch' 34 'AccentInk'; $ic.HorizontalAlignment = 'Center'; $well.Child = $ic
    [void](Add-At $top $well 0)
    $tx = [Windows.Controls.StackPanel]::new(); $tx.VerticalAlignment = 'Center'; $tx.Margin = '18,0,18,0'
    $h = New-Text 'Boost FPS' 30 'Ink' 'Bold'; $h.FontFamily = $window.FindResource('Display')
    $d = New-Text 'Un clic antes de jugar: libera memoria, cierra lo que sobra en segundo plano, pone la energía al máximo y hace la limpieza completa.' 14 'Ink2'; $d.Margin = '0,4,0,0'; $d.MaxWidth = 620; $d.HorizontalAlignment = 'Left'
    [void]$tx.Children.Add($h); [void]$tx.Children.Add($d)
    [void](Add-At $top $tx 1)
    $script:FpsBtn = New-Btn 'Boost FPS' -Primary
    $script:FpsBtn.FontSize = 18; $script:FpsBtn.FontWeight = 'Bold'; $script:FpsBtn.Padding = '34,0'; $script:FpsBtn.MinHeight = 54; $script:FpsBtn.VerticalAlignment = 'Center'
    $bc = [Windows.Controls.StackPanel]::new(); $bc.Orientation = 'Horizontal'
    $bi = New-BtnIcon 'lightning' 20; $bi.Margin = '0,0,10,0'
    $bl = [Windows.Controls.TextBlock]::new(); $bl.Text = 'Boost FPS'; $bl.VerticalAlignment = 'Center'
    [void]$bc.Children.Add($bi); [void]$bc.Children.Add($bl); $script:FpsBtn.Content = $bc
    if (-not $script:IsAdmin) { $script:FpsBtn.IsEnabled = $false; $script:FpsBtn.ToolTip = (T 'Necesita permisos de administrador') }
    $script:FpsBtn.Add_Click({ Invoke-BoostFps })
    [void](Add-At $top $script:FpsBtn 2)
    [void]$outer.Children.Add($top)

    # resultados de cada paso
    $grid = New-Cols @('*', '*', '*', '*'); $grid.Margin = '0,20,0,0'
    $script:FpsSteps = [ordered]@{}
    $i = 0
    foreach ($st in @(@('Ram', 'memory', 'RAM liberada'), @('Apps', 'x-circle', 'Apps cerradas'), @('Svc', 'gear-six','Servicios pausados'), @('Clean', 'broom', 'Disco limpiado'))) {
        $cell = [Windows.Controls.Border]::new(); $cell.CornerRadius = 8; $cell.Padding = '14,10'; $cell.Margin = $(if ($i -lt 3) { '0,0,10,0' } else { '0' })
        $cell.SetResourceReference($BgProp, 'Paper3')
        $cg = New-Cols @('Auto', '*')
        $ci = New-Icon $st[1] 22 'Accent'; $ci.Margin = '0,0,12,0'
        [void](Add-At $cg $ci 0)
        $cs = [Windows.Controls.StackPanel]::new()
        $lab = New-Text $st[2] 12.5 'Muted'; $lab.TextWrapping = 'NoWrap'
        $val = New-Mono '--' 18 'Ink'; $val.FontWeight = 'SemiBold'; $val.Margin = '0,2,0,0'
        [void]$cs.Children.Add($lab); [void]$cs.Children.Add($val)
        [void](Add-At $cg $cs 1)
        $cell.Child = $cg
        [void](Add-At $grid $cell $i)
        $script:FpsSteps[$st[0]] = $val; $i++
    }
    [void]$outer.Children.Add($grid)
    $card.Child = $outer
    $card
}

function Get-BoostState { if (Test-Path $script:BoostFile) { try { Get-Content $script:BoostFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null } } }

function Get-AppMemory($App) {
    $procs = @(Get-Process -Name $App.Proc -ErrorAction SilentlyContinue)
    if (-not $procs) { return $null }
    [double](($procs | Measure-Object WorkingSet64 -Sum).Sum)
}

function Update-BoostView {
    $st = Get-BoostState
    $on = [bool]$st
    $script:BoostTitle.Text = T $(if ($on) { 'Booster activado' } else { 'Booster apagado' })
    $script:BoostSub.Text = T $(if ($on) { "Desde las $(([datetime]$st.Inicio).ToString('HH:mm')). Cerradas $(@($st.Apps).Count) apps y pausados $(@($st.Servicios).Count) servicios." }
                            else { 'Marca lo que quieres apartar mientras juegas y actívalo.' })
    $script:BoostBtn.Content = T $(if ($on) { 'Terminar y restaurar' } else { 'Activar booster' })
    $script:BoostBtn.IsEnabled = $script:IsAdmin
    foreach ($r in $script:BoostAppRows) {
        $mem = Get-AppMemory $r.App
        $r.Mem.Text = T $(if ($null -ne $mem) { Format-Size $mem } else { 'cerrada' })
        $r.Mem.SetResourceReference($FgProp, $(if ($null -ne $mem) { 'Ink' } else { 'Muted' }))
        $r.Switch.IsEnabled = -not $on
    }
    foreach ($r in $script:BoostSvcRows) {
        $svc = Get-Service -Name $r.Svc.Name -ErrorAction SilentlyContinue
        $r.State.Text = T $(if (-not $svc) { 'no existe' } elseif ($svc.Status -eq 'Running') { 'en marcha' } else { 'parado' })
        $r.Switch.IsEnabled = -not $on
    }
}

function Start-Boost {
    Set-Busy $true
    try {
        $closed = @(); $paused = @()
        foreach ($r in $script:BoostAppRows | Where-Object { $_.Switch.IsChecked }) {
            $procs = @(Get-Process -Name $r.App.Proc -ErrorAction SilentlyContinue)
            if (-not $procs) { continue }
            $paths = @($procs | ForEach-Object { try { $_.Path } catch {} } | Where-Object { $_ } | Select-Object -Unique)
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            $closed += [pscustomobject]@{ Name = $r.App.Name; Paths = $paths }
            Write-Log "Booster: cerrada $($r.App.Name)"
        }
        foreach ($r in $script:BoostSvcRows | Where-Object { $_.Switch.IsChecked }) {
            $svc = Get-Service -Name $r.Svc.Name -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') {
                try { Stop-Service -Name $r.Svc.Name -Force -ErrorAction Stop -WarningAction SilentlyContinue; $paused += $r.Svc.Name; Write-Log "Booster: pausado $($r.Svc.Label)" }
                catch { Write-Log "Booster: no se pudo pausar $($r.Svc.Label): $($_.Exception.Message)" 'WARN' }
            }
        }
        $overlay = $null
        if ($script:BoostPower.IsChecked) {
            $overlay = Get-OverlayGuid
            try { Set-OverlayGuid 'ded574b5-45a0-4f42-8737-46345c09c238'; Write-Log 'Booster: modo de energía en máximo rendimiento' } catch {}
        }
        if ($script:BoostPurge.IsChecked) { Invoke-StandbyPurge }
        [pscustomobject]@{ Inicio = (Get-Date).ToString('s'); Apps = $closed; Servicios = $paused; Overlay = $overlay } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:BoostFile -Encoding UTF8
        Write-Log 'Booster activado. Pulsa "Terminar y restaurar" al acabar de jugar.' 'OK'
    }
    finally { Set-Busy $false; Update-BoostView }
}

function Stop-Boost {
    $st = Get-BoostState
    if (-not $st) { return }
    Set-Busy $true
    try {
        foreach ($s in @($st.Servicios)) { if ($s) { Start-Service -Name $s -ErrorAction SilentlyContinue; Write-Log "Booster: reanudado $s" } }
        foreach ($a in @($st.Apps)) {
            foreach ($p in @($a.Paths)) {
                # se vuelven a abrir sin permisos de administrador, como las abriría Windows (vía el Explorador)
                if ($p -and (Test-Path -LiteralPath $p)) { Start-Process explorer.exe -ArgumentList "`"$p`""; Write-Log "Booster: reabierta $($a.Name)"; break }
            }
        }
        if ($st.Overlay) { try { Set-OverlayGuid $st.Overlay } catch {} }
        Remove-Item -LiteralPath $script:BoostFile -Force -ErrorAction SilentlyContinue
        Write-Log 'Booster terminado: todo vuelve a como estaba.' 'OK'
    }
    finally { Set-Busy $false; Update-BoostView }
}

function Invoke-StandbyPurge {
    $before = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB
    $r = [GP.Mem]::PurgeStandby()
    Start-Sleep -Milliseconds 300
    $after = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory * 1KB
    if ($r -eq 0) { Write-Log "Memoria en espera vaciada: $(Format-Size ([math]::Max(0, $after - $before))) más de RAM libre." 'OK' }
    else { Write-Log "No se pudo vaciar la memoria en espera (código $r). Necesita administrador." 'WARN' }
}

function New-BoosterPage {
    $root = [Windows.Controls.StackPanel]::new()
    $script:BoostAppRows = @(); $script:BoostSvcRows = @()
    [void]$root.Children.Add((New-FpsHero))
    [void]$root.Children.Add((New-Section 'O a tu manera'))

    # cabecera de estado
    $head = New-Cols @('*', 'Auto'); $head.Margin = '0,0,0,6'
    $hs = [Windows.Controls.StackPanel]::new()
    $script:BoostTitle = New-Text '' 22 'Ink' 'SemiBold'; $script:BoostTitle.FontFamily = $window.FindResource('Display')
    $script:BoostSub = New-Text '' 14 'Muted'; $script:BoostSub.Margin = '0,4,0,0'
    [void]$hs.Children.Add($script:BoostTitle); [void]$hs.Children.Add($script:BoostSub)
    [void](Add-At $head $hs 0)
    $btns = [Windows.Controls.StackPanel]::new(); $btns.Orientation = 'Horizontal'; $btns.VerticalAlignment = 'Center'
    $bPurge = New-Btn 'Vaciar memoria en espera'; $bPurge.Margin = '0,0,8,0'
    $bPurge.ToolTip = (T 'Libera la caché de archivos de la RAM, como ISLC. Útil si un juego da tirones tras horas abierto.')
    if (-not $script:IsAdmin) { $bPurge.IsEnabled = $false }
    $bPurge.Add_Click({ Set-Busy $true; try { Invoke-StandbyPurge } finally { Set-Busy $false } })
    $script:BoostBtn = New-Btn '' -Primary
    $script:BoostBtn.Add_Click({ if (Get-BoostState) { Stop-Boost } else { Start-Boost } })
    [void]$btns.Children.Add($bPurge); [void]$btns.Children.Add($script:BoostBtn)
    [void](Add-At $head $btns 1)
    [void]$root.Children.Add($head)

    # apps
    [void]$root.Children.Add((New-Section 'Apps que se cierran'))
    [void]$root.Children.Add((New-Ruled))
    foreach ($a in $BoostApps) {
        $sw = New-Switch; $sw.IsChecked = $a.On
        $mem = New-Mono '' 13 'Ink'; $mem.VerticalAlignment = 'Center'; $mem.Margin = '0,0,16,0'
        $act = [Windows.Controls.StackPanel]::new(); $act.Orientation = 'Horizontal'
        [void]$act.Children.Add($mem); [void]$act.Children.Add($sw)
        $row = New-ActionRow $a.Icon $a.Name $a.Desc $act
        [void]$root.Children.Add($row)
        $script:BoostAppRows += @{ App = $a; Switch = $sw; Mem = $mem }
    }

    # servicios
    [void]$root.Children.Add((New-Section 'Servicios que se pausan'))
    [void]$root.Children.Add((New-Ruled))
    foreach ($s in $BoostServices) {
        $sw = New-Switch; $sw.IsChecked = $s.On
        $stt = New-Text '' 13 'Muted'; $stt.VerticalAlignment = 'Center'; $stt.Margin = '0,0,16,0'
        $act = [Windows.Controls.StackPanel]::new(); $act.Orientation = 'Horizontal'
        [void]$act.Children.Add($stt); [void]$act.Children.Add($sw)
        [void]$root.Children.Add((New-ActionRow $s.Icon $s.Label $(if ($script:Pro) { $s.Name } else { $null }) $act))
        $script:BoostSvcRows += @{ Svc = $s; Switch = $sw; State = $stt }
    }

    # extras
    [void]$root.Children.Add((New-Section 'Además'))
    [void]$root.Children.Add((New-Ruled))
    $script:BoostPower = New-Switch; $script:BoostPower.IsChecked = $true
    [void]$root.Children.Add((New-ActionRow 'gauge' 'Modo de energía al máximo' 'Mientras dura el booster. Al terminar vuelve el modo que tenías.' $script:BoostPower))
    $script:BoostPurge = New-Switch; $script:BoostPurge.IsChecked = $true
    [void]$root.Children.Add((New-ActionRow 'memory' 'Vaciar la memoria en espera al empezar' 'Deja más RAM libre para el juego desde el primer minuto.' $script:BoostPurge))

    if (-not $script:IsAdmin) { $script:BoostSub.Text = (T 'Ábrelo como administrador para usar el booster.') }
    Update-BoostView
    if (-not $script:IsAdmin) { $script:BoostSub.Text = (T 'Ábrelo como administrador para usar el booster.') }
    $root
}
