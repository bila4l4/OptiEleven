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
    $script:NetAdapters = @(Get-ActiveAdapters)
    $script:NetInfo.Children.Clear()
    [void]$script:NetInfo.Children.Add((New-Ruled))
    if (-not $script:NetAdapters) { [void]$script:NetInfo.Children.Add((New-Text 'No hay ningún adaptador de red conectado.' 14 'Muted')); return }
    foreach ($a in $script:NetAdapters) {
        $row = New-Object Windows.Controls.Border; $row.Style = $window.FindResource('RuleRow')
        $g = New-Cols @('52', '*', 'Auto')
        $wifi = $a.Desc -match 'Wi-?Fi|Wireless|WLAN|802\.11'
        [void](Add-At $g (New-IconWell $(if ($wifi) { 'wifi-high' } else { 'plugs' })) 0)
        $sp = New-Object Windows.Controls.StackPanel
        [void]$sp.Children.Add((New-Text $a.Name 15 'Ink' 'Medium'))
        $ds = New-Text $a.Desc 14 'Muted'; $ds.Margin = '0,2,0,0'; [void]$sp.Children.Add($ds)
        $meta = New-Object Windows.Controls.WrapPanel; $meta.Margin = '0,8,0,0'
        [void]$meta.Children.Add((New-Chip $a.Speed 'Paper3' 'Ink2'))
        [void]$meta.Children.Add((New-Chip $(if ($a.Static) { 'DNS elegidos a mano' } else { 'DNS automáticos' }) 'Paper3' 'Ink2'))
        [void]$sp.Children.Add($meta)
        $dn = New-Mono ($(if ($a.Dns) { $a.Dns -join '   ' } else { 'sin DNS' })) 13 'Ink'; $dn.Margin = '0,8,0,0'
        [void]$sp.Children.Add($dn)
        [void](Add-At $g $sp 1)
        $lat = New-Object Windows.Controls.StackPanel; $lat.VerticalAlignment = 'Center'; $lat.Margin = '20,0,0,0'
        $l1 = New-Text 'Router' 13 'Muted'; $l1.HorizontalAlignment = 'Right'
        $script:NetGwLatency = New-Mono '-- ms' 22 'Ink'; $script:NetGwLatency.HorizontalAlignment = 'Right'
        [void]$lat.Children.Add($l1); [void]$lat.Children.Add($script:NetGwLatency)
        [void](Add-At $g $lat 2)
        $row.Child = $g
        [void]$script:NetInfo.Children.Add($row)
    }
}
function Invoke-NetLatency {
    Set-Busy $true
    try {
        $gw = ($script:NetAdapters | Where-Object Gateway | Select-Object -First 1).Gateway
        $ms = Measure-Latency $gw
        $script:NetGwLatency.Text = T $(if ($null -ne $ms) { "$ms ms" } else { 'sin respuesta' })
        foreach ($p in $DnsPresets) {
            $tb = $script:NetLatency[$p.Id]; if (-not $tb) { continue }
            $tb.Text = (T '...'); Update-Ui
            $ms = Measure-Latency $p.Servers[0]
            $tb.Text = T $(if ($null -ne $ms) { "$ms ms" } else { 'sin respuesta' })
        }
        Write-Log 'Latencia medida (media de 4 pings).' 'OK'
    }
    finally { Set-Busy $false }
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

function New-NetworkPage {
    $root = New-Object Windows.Controls.StackPanel
    $script:NetLatency = @{}

    $bar = New-Cols @('*', 'Auto'); $bar.Margin = '0,0,0,16'
    $t = New-Text 'Cambiar de DNS no baja el ping del juego: acelera la búsqueda de servidores y la carga de webs y launchers.' 14 'Muted'
    $t.VerticalAlignment = 'Center'; $t.Margin = '0,0,16,0'
    [void](Add-At $bar $t 0)
    $btns = New-Object Windows.Controls.StackPanel; $btns.Orientation = 'Horizontal'
    $bFlush = New-Btn 'Vaciar caché DNS'; $bFlush.Margin = '0,0,8,0'
    $bFlush.Add_Click({ $o = ipconfig /flushdns 2>&1; Write-Log 'Caché DNS vaciada.' 'OK' })
    $bLat = New-Btn 'Medir latencia' -Primary
    $bLat.Add_Click({ Invoke-NetLatency })
    [void]$btns.Children.Add($bFlush); [void]$btns.Children.Add($bLat)
    [void](Add-At $bar $btns 1)
    [void]$root.Children.Add($bar)

    $script:NetInfo = New-Object Windows.Controls.StackPanel
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
        $row = New-Object Windows.Controls.Border; $row.Style = $window.FindResource('RuleRow')
        $g = New-Cols $cols
        [void](Add-At $g (New-IconWell $p.Icon) 0)
        $sp = New-Object Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'
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
