# Módulo "Red": DNS, latencia y caché DNS (como el cambiador de DNS y el ping de Optimizer)

$DnsPresets = @(
    @{ Id = 'auto'; Icon = 'house-line';       Name = 'Automático';  Note = 'Los del router o tu operador';       Servers = @() }
    @{ Id = 'cloudflare'; Icon = 'brand-cloudflare'; Name = 'Cloudflare';  Note = 'Rápido y sin registro de consultas'; Servers = @('1.1.1.1', '1.0.0.1', '2606:4700:4700::1111', '2606:4700:4700::1001') }
    @{ Id = 'google'; Icon = 'brand-google';     Name = 'Google';      Note = 'Estable en casi cualquier país';     Servers = @('8.8.8.8', '8.8.4.4', '2001:4860:4860::8888', '2001:4860:4860::8844') }
    @{ Id = 'quad9'; Icon = 'shield-check';      Name = 'Quad9';       Note = 'Bloquea dominios de malware';        Servers = @('9.9.9.9', '149.112.112.112', '2620:fe::fe', '2620:fe::9') }
)

function Get-ActiveAdapters {
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
        $cfg = Get-NetIPConfiguration -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue
        $dns = @((Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
        $static = $false
        try {
            $guid = $_.InterfaceGuid
            $ns = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" -Name NameServer -ErrorAction Stop).NameServer
            $static = [bool]$ns
        } catch {}
        [pscustomobject]@{ Index = $_.ifIndex; Name = $_.Name; Desc = $_.InterfaceDescription; Speed = $_.LinkSpeed
                           Gateway = $cfg.IPv4DefaultGateway.NextHop; Dns = $dns; Static = $static }
    }
}

function Measure-Latency([string]$Target, [int]$Count = 4) {
    if (-not $Target) { return $null }
    $ping = New-Object System.Net.NetworkInformation.Ping
    $times = @()
    for ($i = 0; $i -lt $Count; $i++) {
        try { $r = $ping.Send($Target, 1000); if ($r.Status -eq 'Success') { $times += $r.RoundtripTime } } catch {}
        Update-Ui
    }
    if ($times) { [math]::Round(($times | Measure-Object -Average).Average) } else { $null }
}

function Update-NetInfo {
    # Get-NetAdapter y compañía cargan módulos de CIM (un par de segundos): en segundo plano
    $script:NetInfo.Children.Clear()
    [void]$script:NetInfo.Children.Add((New-Text 'Leyendo la conexión...' 14 'Muted'))
    $work = [scriptblock]::Create("function Get-ActiveAdapters {`n${function:Get-ActiveAdapters}`n}`n@(Get-ActiveAdapters)")
    Start-Bg $work @() { param($r) $script:NetAdapters = @($r | Where-Object { $_ }); Show-NetInfo }
}
function Show-NetInfo {
    $script:NetInfo.Children.Clear()
    [void]$script:NetInfo.Children.Add((New-Ruled))
    if (-not $script:NetAdapters) { [void]$script:NetInfo.Children.Add((New-Text 'No hay ningún adaptador de red conectado.' 14 'Muted')); return }
    foreach ($a in $script:NetAdapters) {
        $row = [Windows.Controls.Border]::new(); $row.Style = $window.FindResource('RuleRow')
        $g = New-Cols @('52', '*', 'Auto')
        $wifi = $a.Desc -match 'Wi-?Fi|Wireless|WLAN|802\.11'
        [void](Add-At $g (New-IconWell $(if ($wifi) { 'wifi-high' } else { 'plugs' })) 0)
        $sp = [Windows.Controls.StackPanel]::new()
        [void]$sp.Children.Add((New-Text $a.Name 15 'Ink' 'Medium'))
        $ds = New-Text $a.Desc 14 'Muted'; $ds.Margin = '0,2,0,0'; [void]$sp.Children.Add($ds)
        $meta = [Windows.Controls.WrapPanel]::new(); $meta.Margin = '0,8,0,0'
        [void]$meta.Children.Add((New-Chip $a.Speed 'Paper3' 'Ink2'))
        [void]$meta.Children.Add((New-Chip $(if ($a.Static) { 'DNS elegidos a mano' } else { 'DNS automáticos' }) 'Paper3' 'Ink2'))
        [void]$sp.Children.Add($meta)
        $dn = New-Mono ($(if ($a.Dns) { $a.Dns -join '   ' } else { 'sin DNS' })) 13 'Ink'; $dn.Margin = '0,8,0,0'; if (-not $script:Pro) { $dn.Visibility = 'Collapsed' }
        [void]$sp.Children.Add($dn)
        [void](Add-At $g $sp 1)
        $lat = [Windows.Controls.StackPanel]::new(); $lat.VerticalAlignment = 'Center'; $lat.Margin = '20,0,0,0'
        $l1 = New-Text 'Router' 13 'Muted'; $l1.HorizontalAlignment = 'Right'
        $script:NetGwLatency = New-Mono '-- ms' 22 'Ink'; $script:NetGwLatency.HorizontalAlignment = 'Right'
        [void]$lat.Children.Add($l1); [void]$lat.Children.Add($script:NetGwLatency)
        [void](Add-At $g $lat 2)
        $row.Child = $g
        [void]$script:NetInfo.Children.Add($row)
    }
}
function Invoke-NetLatency {
    # los pings (hasta 1 s cada uno) van en segundo plano; cada resultado aparece en cuanto llega
    if ($script:NetPinging) { return }
    $gw = ($script:NetAdapters | Where-Object Gateway | Select-Object -First 1).Gateway
    $targets = @(, @('gw', $gw)) + @($DnsPresets | Where-Object { $_.Servers } | ForEach-Object { , @($_.Id, $_.Servers[0]) })
    foreach ($t in $targets) { $tb = if ($t[0] -eq 'gw') { $script:NetGwLatency } else { $script:NetLatency[$t[0]] }; if ($tb) { $tb.Text = (T '...') } }
    $script:NetPinging = $true
    $progress = [hashtable]::Synchronized(@{})
    Start-Bg -Work {
        param($A, $P)
        $targets = $A.Targets
        $ping = [System.Net.NetworkInformation.Ping]::new()
        foreach ($t in $targets) {
            $times = @()
            if ($t[1]) { for ($i = 0; $i -lt 4; $i++) { try { $r = $ping.Send($t[1], 1000); if ($r.Status -eq 'Success') { $times += $r.RoundtripTime } } catch {} } }
            $P[$t[0]] = if ($times) { [math]::Round(($times | Measure-Object -Average).Average) } else { -1 }
        }
    } -ArgList @(@{ Targets = $targets }) -Progress $progress -OnTick {
        param($P)
        foreach ($id in @($P.Keys)) {
            $tb = if ($id -eq 'gw') { $script:NetGwLatency } else { $script:NetLatency[$id] }
            if ($tb) { $tb.Text = T $(if ($P[$id] -ge 0) { "$($P[$id]) ms" } else { 'sin respuesta' }) }
        }
    } -Done { $script:NetPinging = $false; Write-Log 'Latencia medida (media de 4 pings).' 'OK' }
}
function Set-DnsPreset($Preset) {
    if (-not $script:NetAdapters) { return }
    Set-Busy $true
    try {
        $v4 = @($Preset.Servers | Where-Object { $_ -notlike '*:*' })
        $v6 = @($Preset.Servers | Where-Object { $_ -like '*:*' })
        $ok = @(); $bad = @()
        # adaptador a adaptador: si uno falla, los demás se cambian igual y el registro dice cuál no
        foreach ($a in $script:NetAdapters) {
            try {
                if ($Preset.Servers.Count -eq 0) { Set-DnsClientServerAddress -InterfaceIndex $a.Index -ResetServerAddresses -ErrorAction Stop }
                else {
                    $hasV6 = [bool](Get-NetAdapterBinding -Name $a.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object Enabled)
                    $list = if ($hasV6) { $v4 + $v6 } else { $v4 }   # IPv6 solo donde IPv6 está activo
                    Set-DnsClientServerAddress -InterfaceIndex $a.Index -ServerAddresses $list -ErrorAction Stop
                }
                $ok += $a.Name
            }
            catch { $bad += "$($a.Name) ($($_.Exception.Message.Trim()))" }
        }
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        if ($ok) { Write-Log "DNS cambiado a $($Preset.Name) en: $($ok -join ', ')." 'OK' }
        if ($bad) { Write-Log "No se pudo cambiar el DNS en: $($bad -join '; ')" 'ERROR' }
    }
    finally { Set-Busy $false; Update-NetInfo }
}

# ---------- test de velocidad, con speed.cloudflare.com como motor (el de su web)
$SpeedWork = {
    param($P)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    [Net.ServicePointManager]::DefaultConnectionLimit = 32
    [Net.ServicePointManager]::Expect100Continue = $false
    $base = 'https://speed.cloudflare.com'
    try { $tr = [Net.WebClient]::new().DownloadString("$base/cdn-cgi/trace"); if ($tr -match 'colo=(\w+)') { $P.Colo = $Matches[1] } } catch { $P.Error = $_.Exception.Message; return }

    # latencia: ping al mismo servidor de Cloudflare que hace el test; si la red bloquea el ping, tiempo de respuesta HTTP
    $P.Phase = 'ping'; $times = @()
    $icmp = [System.Net.NetworkInformation.Ping]::new()
    for ($i = 0; $i -lt 12; $i++) {
        try { $r = $icmp.Send('speed.cloudflare.com', 1500); if ($r.Status -eq 'Success') { $times += [double]$r.RoundtripTime } } catch {}
        $P.Progress = ($i + 1) / 12 * 0.12
    }
    if ($times.Count -lt 4) {
        $times = @()
        for ($i = 0; $i -lt 12; $i++) {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            try { $rq = [Net.HttpWebRequest]::Create("$base/__down?bytes=0"); $rq.Timeout = 5000; $rs = $rq.GetResponse(); $ms = $sw.Elapsed.TotalMilliseconds; $rs.Close(); if ($i -ge 2) { $times += $ms } } catch {}
        }
    }    if ($times) {
        $sorted = $times | Sort-Object; $P.Ping = [math]::Round($sorted[[int][math]::Floor($sorted.Count / 2)])
        $d = for ($i = 1; $i -lt $times.Count; $i++) { [math]::Abs($times[$i] - $times[$i - 1]) }
        $P.Jitter = [math]::Round(($d | Measure-Object -Average).Average, 1)
    }

    # descarga y subida: varias conexiones a la vez durante unos segundos, como hace la web
    function Invoke-Phase([string]$Kind, [int]$Streams, [double]$Seconds, [double]$From, [double]$To) {
        $S = [hashtable]::Synchronized(@{ Stop = $false })
        $pool = [runspacefactory]::CreateRunspacePool(1, $Streams); $pool.Open()
        $worker = {
            param($S, $Key, $Kind, $Base)
            $buf = [byte[]]::new(65536); (New-Object Random).NextBytes($buf); $S[$Key] = [long]0
            while (-not $S.Stop) {
                try {
                    if ($Kind -eq 'down') {
                        $rq = [Net.HttpWebRequest]::Create("$Base/__down?bytes=50000000"); $rq.Timeout = 20000
                        $rs = $rq.GetResponse(); $st = $rs.GetResponseStream()
                        while (-not $S.Stop) { $n = $st.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $S[$Key] += $n }
                        $rs.Close()
                    }
                    else {
                        $len = 8MB
                        $rq = [Net.HttpWebRequest]::Create("$Base/__up"); $rq.Method = 'POST'; $rq.Timeout = 20000; $rq.ContentLength = $len
                        $rq.AllowWriteStreamBuffering = $false; $rq.ContentType = 'application/octet-stream'
                        $st = $rq.GetRequestStream(); $sent = 0
                        while ($sent -lt $len -and -not $S.Stop) { $c = [math]::Min($buf.Length, $len - $sent); $st.Write($buf, 0, $c); $sent += $c; $S[$Key] += $c }
                        $st.Close(); if (-not $S.Stop) { $rq.GetResponse().Close() } else { $rq.Abort() }
                    }
                } catch { Start-Sleep -Milliseconds 100 }
            }
        }
        $runs = for ($k = 0; $k -lt $Streams; $k++) { $ps = [powershell]::Create(); $ps.RunspacePool = $pool; [void]$ps.AddScript($worker).AddArgument($S).AddArgument("b$k").AddArgument($Kind).AddArgument($base); @{ Ps = $ps; H = $ps.BeginInvoke() } }
        $sum = { $t = [long]0; foreach ($k in 0..($Streams - 1)) { if ($S.ContainsKey("b$k")) { $t += $S["b$k"] } }; $t }
        $sw = [Diagnostics.Stopwatch]::StartNew(); $warm = 1.5; $b0 = $null; $lastB = 0; $lastT = 0.0; $live = 0.0
        while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
            Start-Sleep -Milliseconds 250
            $t = $sw.Elapsed.TotalSeconds; $b = & $sum
            if ($null -eq $b0 -and $t -ge $warm) { $b0 = $b; $t0 = $t }
            $inst = if ($t -gt $lastT) { ($b - $lastB) * 8 / 1e6 / ($t - $lastT) } else { 0 }
            $live = if ($live -eq 0) { $inst } else { $live * 0.7 + $inst * 0.3 }
            $lastB = $b; $lastT = $t
            $P["Live$Kind"] = [math]::Round($live, 1); $P.Progress = $From + ($To - $From) * ($t / $Seconds)
        }
        $bEnd = & $sum; $tEnd = $sw.Elapsed.TotalSeconds
        $S.Stop = $true
        foreach ($r in $runs) { try { [void]$r.Ps.EndInvoke($r.H) } catch {}; $r.Ps.Dispose() }
        $pool.Close()
        if ($null -eq $b0) { $b0 = 0; $t0 = 0 }
        [math]::Round(($bEnd - $b0) * 8 / 1e6 / [math]::Max(0.5, $tEnd - $t0), 1)
    }
    $P.Phase = 'down'; $P.Down = Invoke-Phase 'down' 6 10 0.12 0.58
    $P.Phase = 'up';   $P.Up   = Invoke-Phase 'up' 4 9 0.58 1.0
    $P.Phase = 'done'; $P.Progress = 1.0
}

function Start-SpeedTest {
    if ($script:SpeedRunning) { return }
    $script:SpeedRunning = $true
    $script:SpeedBtn.IsEnabled = $false
    foreach ($k in 'Down', 'Up', 'Ping', 'Jitter') { $script:SpeedVals[$k].Text = '--' }
    $script:SpeedPhase.Text = (T 'Conectando con Cloudflare...')
    $P = [hashtable]::Synchronized(@{ Phase = 'start'; Progress = 0.0 })
    Start-Bg -Work $SpeedWork -Progress $P -OnTick {
        param($P)
        $script:SpeedBar.Width = [math]::Max(0, [math]::Min(1, [double]$P.Progress)) * $script:SpeedTrack.ActualWidth
        if ($null -ne $P.Ping) { $script:SpeedVals.Ping.Text = "$($P.Ping)"; $script:SpeedVals.Jitter.Text = "$($P.Jitter)" }
        switch ($P.Phase) {
            'ping' { $script:SpeedPhase.Text = (T 'Midiendo la latencia...') }
            'down' { $script:SpeedPhase.Text = (T 'Midiendo la descarga...'); if ($P.Livedown) { $script:SpeedVals.Down.Text = '{0:N0}' -f $P.Livedown } }
            'up'   { $script:SpeedPhase.Text = (T 'Midiendo la subida...'); if ($null -ne $P.Down) { $script:SpeedVals.Down.Text = '{0:N0}' -f $P.Down }; if ($P.Liveup) { $script:SpeedVals.Up.Text = '{0:N0}' -f $P.Liveup } }
        }
        if ($P.Colo) { $script:SpeedServer.Text = (T "Servidor de Cloudflare en $($P.Colo)") }
    } -Done {
        $script:SpeedRunning = $false; $script:SpeedBtn.IsEnabled = $true
        $P = $script:SpeedLast
    }
    $script:SpeedLast = $P
    $script:SpeedDoneWatch = $P
    $script:SpeedFinish = New-Timer 0.3 {
        $P = $script:SpeedDoneWatch
        if ($P.Error) { $script:SpeedFinish.Stop(); $script:SpeedPhase.Text = (T "No se pudo conectar: $($P.Error)"); return }
        if ($P.Phase -ne 'done' -or $null -eq $P.Up) { return }
        $script:SpeedFinish.Stop()
        $script:SpeedVals.Down.Text = '{0:N0}' -f $P.Down; $script:SpeedVals.Up.Text = '{0:N0}' -f $P.Up
        $script:SpeedPhase.Text = (T "Listo a las $((Get-Date).ToString('HH:mm')).")
        Write-Log "Test de velocidad: $($P.Down) Mbps de bajada, $($P.Up) Mbps de subida, $($P.Ping) ms de ping." 'OK'
    }
    $script:SpeedFinish.Start()
}

function New-SpeedTestCard {
    $card = [Windows.Controls.Border]::new(); $card.CornerRadius = 14; $card.Padding = '24,20'; $card.Margin = '0,0,0,18'; $card.BorderThickness = 1
    $card.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Glass'); $card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'GlassEdge')
    $sp = [Windows.Controls.StackPanel]::new()
    $top = New-Cols @('Auto', '*', 'Auto')
    $w = [Windows.Controls.Border]::new(); $w.Width = 56; $w.Height = 56; $w.CornerRadius = 13; $w.VerticalAlignment = 'Center'
    $w.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Cat-Privacidad')
    $wi = New-Icon 'gauge' 30 'AccentInk'; $wi.HorizontalAlignment = 'Center'; $w.Child = $wi
    [void](Add-At $top $w 0)
    $tx = [Windows.Controls.StackPanel]::new(); $tx.Margin = '16,0,16,0'; $tx.VerticalAlignment = 'Center'
    $h = New-Text 'Test de velocidad' 22 'Ink' 'Bold'; $h.FontFamily = $window.FindResource('Display')
    $script:SpeedServer = New-Text 'Con el motor de speed.cloudflare.com. Gasta entre 100 y 500 MB de datos.' 13.5 'Ink2'; $script:SpeedServer.Margin = '0,4,0,0'
    [void]$tx.Children.Add($h); [void]$tx.Children.Add($script:SpeedServer)
    [void](Add-At $top $tx 1)
    $script:SpeedBtn = New-Btn 'Iniciar test' -Primary; $script:SpeedBtn.MinHeight = 46; $script:SpeedBtn.FontSize = 15; $script:SpeedBtn.Padding = '26,0'; $script:SpeedBtn.VerticalAlignment = 'Center'
    $script:SpeedBtn.Add_Click({ Start-SpeedTest })
    [void](Add-At $top $script:SpeedBtn 2)
    [void]$sp.Children.Add($top)

    $grid = New-Cols @('*', '*', '*', '*'); $grid.Margin = '0,20,0,0'
    $script:SpeedVals = @{}
    $i = 0
    foreach ($m in @(@('Down', 'arrow-circle-down', 'Descarga', 'Mbps', 'Cat-Juegos'), @('Up', 'arrow-circle-up', 'Subida', 'Mbps', 'Cat-Interfaz'), @('Ping', 'pulse', 'Ping', 'ms', 'Cat-Latencia'), @('Jitter', 'wave-sine', 'Jitter', 'ms', 'Cat-Servicios'))) {
        $cell = [Windows.Controls.Border]::new(); $cell.CornerRadius = 10; $cell.Padding = '16,12'; $cell.Margin = $(if ($i -lt 3) { '0,0,10,0' } else { '0' })
        $cell.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, "Soft$($m[4])")
        $cs = [Windows.Controls.StackPanel]::new()
        $hd = [Windows.Controls.StackPanel]::new(); $hd.Orientation = 'Horizontal'
        $ic = New-Icon $m[1] 18 $m[4]; $ic.Margin = '0,0,8,0'; [void]$hd.Children.Add($ic)
        [void]$hd.Children.Add((New-Text $m[2] 13 'Ink2' 'SemiBold'))
        [void]$cs.Children.Add($hd)
        $vr = [Windows.Controls.StackPanel]::new(); $vr.Orientation = 'Horizontal'; $vr.Margin = '0,6,0,0'
        $v = New-Mono '--' 30 'Ink'; $v.FontWeight = 'Bold'
        $u = New-Text $m[3] 13 'Muted'; $u.VerticalAlignment = 'Bottom'; $u.Margin = '6,0,0,5'
        [void]$vr.Children.Add($v); [void]$vr.Children.Add($u)
        [void]$cs.Children.Add($vr)
        $cell.Child = $cs
        [void](Add-At $grid $cell $i); $i++
        $script:SpeedVals[$m[0]] = $v
    }
    [void]$sp.Children.Add($grid)
    $script:SpeedTrack = [Windows.Controls.Border]::new(); $script:SpeedTrack.Height = 4; $script:SpeedTrack.CornerRadius = 2; $script:SpeedTrack.Margin = '0,16,0,0'
    $script:SpeedTrack.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Paper3')
    $script:SpeedBar = [Windows.Controls.Border]::new(); $script:SpeedBar.Height = 4; $script:SpeedBar.CornerRadius = 2; $script:SpeedBar.HorizontalAlignment = 'Left'; $script:SpeedBar.Width = 0
    $script:SpeedBar.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Cat-Privacidad')
    $script:SpeedTrack.Child = $script:SpeedBar
    [void]$sp.Children.Add($script:SpeedTrack)
    $script:SpeedPhase = New-Text 'Pulsa Iniciar test. Cierra descargas y streaming para que el resultado sea real.' 13 'Muted'; $script:SpeedPhase.Margin = '0,8,0,0'
    [void]$sp.Children.Add($script:SpeedPhase)
    $card.Child = $sp
    $card
}
function New-NetworkPage {
    $root = [Windows.Controls.StackPanel]::new()
    $script:NetLatency = @{}
    [void]$root.Children.Add((New-SpeedTestCard))

    $bar = New-Cols @('*', 'Auto'); $bar.Margin = '0,0,0,16'
    $t = New-Text 'Cambiar de DNS no baja el ping del juego: acelera la búsqueda de servidores y la carga de webs y launchers.' 14 'Muted'
    $t.VerticalAlignment = 'Center'; $t.Margin = '0,0,16,0'
    [void](Add-At $bar $t 0)
    $btns = [Windows.Controls.StackPanel]::new(); $btns.Orientation = 'Horizontal'
    $bFlush = New-Btn 'Vaciar caché DNS'; $bFlush.Margin = '0,0,8,0'
    $bFlush.Add_Click({ $o = ipconfig /flushdns 2>&1; Write-Log 'Caché DNS vaciada.' 'OK' })
    $bLat = New-Btn 'Medir latencia' -Primary
    $bLat.Add_Click({ Invoke-NetLatency })
    [void]$btns.Children.Add($bFlush); [void]$btns.Children.Add($bLat)
    [void](Add-At $bar $btns 1)
    [void]$root.Children.Add($bar)

    $script:NetInfo = [Windows.Controls.StackPanel]::new()
    [void]$root.Children.Add($script:NetInfo)
    Update-NetInfo

    [void]$root.Children.Add((New-Section 'Servidores DNS'))
    $cols = @('52', '*', '170', '90', 'Auto')
    $hdr = New-Cols $cols; $hdr.Margin = '0,0,0,8'
    $h1 = New-Text 'Servicio' 13 'Muted' 'Medium'; [void](Add-At $hdr $h1 1)
    $h2 = New-Text 'Direcciones' 13 'Muted' 'Medium'; [void](Add-At $hdr $h2 2)
    $h3 = New-Text 'Latencia' 13 'Muted' 'Medium'; $h3.TextAlignment = 'Right'; [void](Add-At $hdr $h3 3)
    [void]$root.Children.Add($hdr)
    [void]$root.Children.Add((New-Ruled))
    for ($i = 0; $i -lt $DnsPresets.Count; $i++) {
        $p = $DnsPresets[$i]
        $row = [Windows.Controls.Border]::new(); $row.Style = $window.FindResource('RuleRow')
        $g = New-Cols $cols
        [void](Add-At $g (New-IconWell $p.Icon) 0)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
        [void]$sp.Children.Add((New-Text $p.Name 15 'Ink' 'Medium'))
        $nt = New-Text $p.Note 14 'Muted'; $nt.Margin = '0,2,0,0'; [void]$sp.Children.Add($nt)
        [void](Add-At $g $sp 1)
        $ip = New-Mono $(if ($p.Servers) { "$($p.Servers[0])`n$($p.Servers[1])" } else { 'los del router' }) 13 'Ink'; $ip.VerticalAlignment = 'Center'
        [void](Add-At $g $ip 2)
        $lt = New-Mono $(if ($p.Servers) { '-- ms' } else { '' }) 15 'Ink'; $lt.VerticalAlignment = 'Center'; $lt.TextAlignment = 'Right'
        if ($p.Servers) { $script:NetLatency[$p.Id] = $lt }
        [void](Add-At $g $lt 3)
        $b = New-Btn 'Usar este'; $b.Tag = $i; $b.Margin = '20,0,0,0'; $b.VerticalAlignment = 'Center'
        if (-not $script:IsAdmin) { $b.IsEnabled = $false; $b.ToolTip = (T 'Necesita permisos de administrador') }
        $b.Add_Click({ param($src, $e) Set-DnsPreset $DnsPresets[[int]$src.Tag] })
        [void](Add-At $g $b 4)
        $row.Child = $g
        [void]$root.Children.Add($row)
    }
    $root
}
