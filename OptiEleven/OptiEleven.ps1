#Requires -Version 5.1
<#
  OptiEleven - optimizaciones reversibles para Windows 11
  - Cada ajuste guarda el estado original la primera vez que se aplica
    (%ProgramData%\OptiEleven\secure\backup.json) y "Revertir" lo restaura.
  - Uso:
      .\OptiEleven.ps1                          -> abre el panel
      .\OptiEleven.ps1 -Page m-clean            -> abre directamente un apartado (m-apps, m-startup, m-clean, m-net, m-hw, tools...)
      .\OptiEleven.ps1 -Status                  -> muestra el estado de cada ajuste (sin cambiar nada)
      .\OptiEleven.ps1 -Preset Recomendado -NoGui  -> aplica un preset sin interfaz (requiere admin)
      .\OptiEleven.ps1 -Config perfil.json -NoGui  -> aplica un perfil exportado desde el panel (requiere admin)
#>
param(
    [ValidateSet('Recomendado', 'Avanzado', 'Competitivo')] [string]$Preset,
    [string]$Config,
    [string]$Page = 'all',
    [switch]$NoGui,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
$script:Root       = Join-Path $env:ProgramData 'OptiEleven'
# Lo que el panel elevado lee y usa para tocar el sistema (copias, estado del booster) va en una carpeta que
# solo pueden escribir Administradores y SYSTEM; si no, un programa sin permisos podría editarla y conseguir
# que el panel escriba en el registro lo que él quiera al "revertir".
$script:Secure     = Join-Path $script:Root 'secure'
$script:BackupFile = Join-Path $script:Secure 'backup.json'
$script:LogFile    = Join-Path $script:Root 'panel.log'
$script:IsAdmin    = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:LogBox     = $null
try { if (-not (Test-Path $script:Root)) { New-Item -ItemType Directory -Path $script:Root -Force | Out-Null } } catch {}
function Protect-Folder([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)   # sin permisos heredados de ProgramData
    $inh = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [System.Security.AccessControl.PropagationFlags]::None
    foreach ($r in @(@('S-1-5-32-544', 'FullControl'), @('S-1-5-18', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
        $sid = New-Object System.Security.Principal.SecurityIdentifier $r[0]
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $sid, $r[1], $inh, $none, 'Allow'))
    }
    $acl.SetOwner((New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
    Set-Acl -LiteralPath $Path -AclObject $acl
}
# datos de cuando el panel se llamaba Gaming Panel: tema, juegos añadidos y (con admin) las copias de seguridad
$oldRoot = Join-Path $env:ProgramData 'GamingPanel'
if (Test-Path $oldRoot) {
    foreach ($n in 'theme.txt', 'games.json') { $src = Join-Path $oldRoot $n; $dst = Join-Path $script:Root $n; if ((Test-Path $src) -and -not (Test-Path $dst)) { try { Copy-Item $src $dst } catch {} } }
}
if ($script:IsAdmin) {
    try {
        Protect-Folder $script:Secure
        foreach ($n in 'backup.json', 'boost.json', 'capabilities.done') {
            $src = Join-Path (Join-Path $oldRoot 'secure') $n; $dst = Join-Path $script:Secure $n
            if ((Test-Path $src) -and -not (Test-Path $dst)) { Copy-Item $src $dst }
        }
        # copias de versiones anteriores del panel, que estaban en la carpeta abierta
        $oldBk = Join-Path $script:Root 'backup.json'
        if ((Test-Path $oldBk) -and -not (Test-Path $script:BackupFile)) { Move-Item -LiteralPath $oldBk -Destination $script:BackupFile }
    }
    catch {}
}

# Llamadas nativas (energía, barra de título oscura, memoria). Compilar C# con Add-Type cuesta ~300 ms cada vez,
# así que se compila una sola vez a una DLL y las siguientes veces solo se carga. Con permisos de administrador la
# DLL vive en la carpeta segura (si estuviera en una carpeta del usuario, otro programa podría cambiarla y el panel
# elevado la cargaría); sin ellos, en la del usuario, que no da más permisos de los que ya tiene.
$GpSource = @'
using System;
using System.Runtime.InteropServices;
namespace GP {
    public static class PowerOverlay {
        [DllImport("powrprof.dll")] public static extern uint PowerSetActiveOverlayScheme(Guid g);
        [DllImport("powrprof.dll")] public static extern uint PowerGetEffectiveOverlayScheme(out Guid g);
    }
    public static class Dwm {
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
    }
    public static class Ws {
        [DllImport("psapi.dll")] public static extern bool EmptyWorkingSet(IntPtr h);
    }
    public static class Mem {
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
    }
}
'@
if (-not ('GP.PowerOverlay' -as [type])) {
    $loaded = $false
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        $hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($GpSource))[0..5] | ForEach-Object { $_.ToString('x2') })
        $cacheDir = if ($script:IsAdmin) { $script:Secure } else { Join-Path $env:LOCALAPPDATA 'OptiEleven\cache' }
        $dll = Join-Path $cacheDir "native-$hash.dll"
        if (-not (Test-Path -LiteralPath $dll)) {
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            Add-Type -TypeDefinition $GpSource -OutputAssembly $dll -OutputType Library
        }
        Add-Type -LiteralPath $dll; $loaded = $true
    }
    catch {}
    if (-not $loaded -and -not ('GP.PowerOverlay' -as [type])) { Add-Type -TypeDefinition $GpSource }
}

# ============================================================ utilidades
function Update-Ui {
    if (-not $script:LogBox) { return }
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; $null }, $frame)
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

# ---------- idiomas
# Los textos del panel están escritos en español; lang\<código>.json da la traducción:
#   "strings":  texto exacto -> traducción
#   "patterns": [regex, sustitución]; en la sustitución $1 copia el grupo tal cual y @1 lo traduce también.
# Para añadir un idioma basta con copiar en.json con otro código (fr.json...) y traducir los valores.
$script:LangDir  = Join-Path $PSScriptRoot 'lang'
$script:LangFile = Join-Path $script:Root 'lang.txt'
$script:LangCode = 'en'
try { if (Test-Path $script:LangFile) { $c = (Get-Content -LiteralPath $script:LangFile -Raw).Trim(); if ($c -match '^[a-z]{2}(-[A-Za-z]{2})?$') { $script:LangCode = $c } } } catch {}
$script:LangStrings = $null; $script:LangPatterns = @()
function Get-Languages {
    Add-Type -AssemblyName System.Web.Extensions
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer; $js.MaxJsonLength = 16MB
    foreach ($f in (Get-ChildItem -LiteralPath $script:LangDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $d = $js.DeserializeObject([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)); [pscustomobject]@{ Code = $f.BaseName; Name = [string]$d['name']; Data = $d } } catch {}
    }
}
function Import-Language([string]$Code) {
    # JavaScriptSerializer distingue mayúsculas ("Instalada" e "instalada" son entradas distintas), ConvertFrom-Json de PS 5.1 no
    $script:LangStrings = $null; $script:LangPatterns = @()
    $l = Get-Languages | Where-Object Code -eq $Code | Select-Object -First 1
    if (-not $l) { return }
    $dict = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    if ($l.Data['strings']) { foreach ($k in $l.Data['strings'].Keys) { $dict[$k] = [string]$l.Data['strings'][$k] } }
    if ($dict.Count) { $script:LangStrings = $dict }
    $script:LangPatterns = @(foreach ($p in @($l.Data['patterns'])) { if ($p -and $p.Count -ge 2) { , @([regex]::new([string]$p[0]), [string]$p[1]) } })
}
function T([string]$Text) {
    if ([string]::IsNullOrEmpty($Text) -or (-not $script:LangStrings -and -not $script:LangPatterns.Count)) { return $Text }
    if ($Text.Contains("`n")) { return (($Text -split "`n") | ForEach-Object { T ($_.TrimEnd("`r")) }) -join "`n" }
    $hit = $null
    if ($script:LangStrings -and $script:LangStrings.TryGetValue($Text, [ref]$hit)) { return $hit }
    foreach ($p in $script:LangPatterns) {
        $m = $p[0].Match($Text)
        if ($m.Success) {
            return [regex]::Replace($p[1], '([$@])(\d)', {
                param($x) $g = $m.Groups[[int]$x.Groups[2].Value].Value
                if ($x.Groups[1].Value -eq '@') { T $g } else { $g } })
        }
    }
    $Text
}
Import-Language $script:LangCode

function Write-Log([string]$Msg, [string]$Level = 'INFO') {
    $Msg = T $Msg
    $line = '[{0}] {1,-5} {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Msg
    if ($script:LogBox) { $script:LogBox.AppendText($line + "`r`n"); $script:LogBox.ScrollToEnd(); if ($script:Busy -and $script:PendingTb) { $script:PendingTb.Text = $Msg }; Update-Ui }
    else { Write-Host $line }
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch {}
}

# ---------- registro
function RegV([string]$Path, [string]$Name, $Value, [string]$Kind = 'DWord', $Default = $null) {
    # Default: valor de Windows para revertir si no hay copia (si no se indica, se borra el valor)
    @{ Path = $Path; Name = $Name; Value = $Value; Kind = $Kind; Default = $Default }
}
function Get-RegState($r) {
    $exists = $false; $val = $null; $kind = $null
    if (Test-Path -LiteralPath $r.Path) {
        $k = Get-Item -LiteralPath $r.Path
        if ($k.GetValueNames() -contains $r.Name) {
            $exists = $true
            $val  = $k.GetValue($r.Name, $null, 'DoNotExpandEnvironmentNames')
            $kind = $k.GetValueKind($r.Name).ToString()
        }
    }
    [pscustomobject]@{ Path = $r.Path; Name = $r.Name; Exists = $exists; Value = $val; Kind = $kind }
}
function Set-RegValue($Path, $Name, $Value, $Kind) {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null
}
function Remove-RegValue($Path, $Name) {
    if (Test-Path -LiteralPath $Path) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue }
}
function Test-Reg($r) {
    $s = Get-RegState $r
    return [bool]($s.Exists -and ("$($s.Value)" -eq "$($r.Value)"))
}

# ---------- servicios
function SvcV([string]$Name, [string]$Start, [string]$Default) { @{ Name = $Name; Start = $Start; Default = $Default } }
function Get-StartCode([string]$s) { switch ($s) { 'Auto' { 2 } 'Delayed' { 2 } 'Manual' { 3 } 'Disabled' { 4 } default { 3 } } }
function Get-SvcState([string]$Name) {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $k = Get-ItemProperty -LiteralPath $p
    $delayed = ($k.PSObject.Properties.Name -contains 'DelayedAutostart') -and ($k.DelayedAutostart -eq 1)
    [pscustomobject]@{ Name = $Name; Start = [int]$k.Start; Delayed = [bool]$delayed }
}
function Set-SvcStart([string]$Name, [int]$Start, [bool]$Delayed) {
    if (-not (Get-SvcState $Name)) { return }
    $mode = switch ($Start) { 2 { if ($Delayed) { 'delayed-auto' } else { 'auto' } } 3 { 'demand' } 4 { 'disabled' } default { $null } }
    if (-not $mode) { return }
    $out = & sc.exe config $Name start= $mode 2>&1
    if ($LASTEXITCODE -ne 0) {
        # algunos servicios no aceptan sc.exe: probar por registro
        try { Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name Start -Value $Start -Type DWord }
        catch { throw "No se pudo cambiar el servicio $Name ($out)" }
    }
    if ($Start -eq 4) { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
}

# ---------- tareas programadas
function Split-TaskPath([string]$Full) { $i = $Full.LastIndexOf('\'); @($Full.Substring(0, $i + 1), $Full.Substring($i + 1)) }
function Get-TaskState([string]$Full) {
    # API COM del Programador de tareas: ~1 ms por tarea (Get-ScheduledTask tarda ~650 ms)
    if (-not $script:TaskSvc) { $script:TaskSvc = New-Object -ComObject Schedule.Service; $script:TaskSvc.Connect() }
    $p, $n = Split-TaskPath $Full
    try { $t = $script:TaskSvc.GetFolder($(if ($p -eq '\') { '\' } else { $p.TrimEnd('\') })).GetTask($n) } catch { return $null }
    [pscustomobject]@{ Task = $Full; Enabled = [bool]$t.Enabled }
}
function Set-TaskEnabled([string]$Full, [bool]$Enabled) {
    $p, $n = Split-TaskPath $Full
    if (-not (Get-ScheduledTask -TaskPath $p -TaskName $n -ErrorAction SilentlyContinue)) { return }
    if ($Enabled) { Enable-ScheduledTask -TaskPath $p -TaskName $n | Out-Null }
    else { Disable-ScheduledTask -TaskPath $p -TaskName $n | Out-Null }
}

# ---------- energía
function Get-OverlayGuid { $g = [guid]::Empty; [void][GP.PowerOverlay]::PowerGetEffectiveOverlayScheme([ref]$g); $g.ToString() }
function Set-OverlayGuid([string]$g) {
    $r = [GP.PowerOverlay]::PowerSetActiveOverlayScheme([guid]$g)
    if ($r -ne 0) { throw "PowerSetActiveOverlayScheme devolvió $r" }
}
function Get-ActiveSchemeGuid { if ((powercfg /getactivescheme) -match '([0-9a-f]{8}-[0-9a-f-]{27})') { $Matches[1] } }

# ---------- copias de seguridad
function Read-Store {
    if (Test-Path $script:BackupFile) { try { return (Get-Content $script:BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {} }
    [pscustomobject]@{}
}
$script:Store = Read-Store
function Write-Store { $script:Store | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:BackupFile -Encoding UTF8 }
function Get-Backup([string]$Id) { $p = $script:Store.PSObject.Properties[$Id]; if ($p) { $p.Value } else { $null } }
function Save-Backup([string]$Id, $Bk) { $script:Store | Add-Member -NotePropertyName $Id -NotePropertyValue $Bk -Force; Write-Store }
function Remove-Backup([string]$Id) { $script:Store.PSObject.Properties.Remove($Id); Write-Store }

# ============================================================ catálogo de ajustes
# Risk: Seguro / Moderado / Avanzado
# Presets: R = Recomendado (quita casi toda la basura, sin romper nada que se use a diario)
#          A = Avanzado (Recomendado + lo que conviene saber qué hace). Sin preset: solo a mano.
# Ideas cruzadas con WinUtil (Chris Titus), Win11Debloat (Raphire), Optimizer (hellzerg) y Atlas OS.
$P   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$MM  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'

$DebloatApps = @(
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.WindowsFeedbackHub', 'Clipchamp.Clipchamp', 'Microsoft.Todos',
    'Microsoft.PowerAutomateDesktop', 'MSTeams', 'Microsoft.Copilot', 'Microsoft.MicrosoftOfficeHub',
    'Microsoft.OutlookForWindows', 'Microsoft.WindowsMaps', 'Microsoft.549981C3F5F10', 'Microsoft.People',
    'Microsoft.ZuneVideo', 'MicrosoftCorporationII.QuickAssist', 'Microsoft.Windows.DevHome',
    # más de Microsoft que viene de serie o llega con las actualizaciones
    'Microsoft.WindowsCommunicationsApps', 'Microsoft.SkypeApp', 'Microsoft.MixedReality.Portal', 'Microsoft.Microsoft3DViewer',
    'Microsoft.Print3D', 'Microsoft.MSPaint', 'Microsoft.Office.OneNote', 'Microsoft.Wallet', 'Microsoft.Messaging', 'Microsoft.OneConnect',
    'Microsoft.BingFinance', 'Microsoft.BingSports', 'Microsoft.BingTranslator', 'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness',
    'Microsoft.BingTravel', 'Microsoft.News', 'MicrosoftCorporationII.MicrosoftFamily', 'Microsoft.Windows.Ai.Copilot.Provider',
    'MicrosoftWindows.Client.WebExperience', 'Microsoft.StartExperiencesApp', 'Microsoft.Edge.GameAssist',
    # patrocinadas que Windows instala solo (se aceptan comodines)
    '*CandyCrush*', '*BubbleWitch*', '*FarmHeroes*', '*MarchofEmpires*', '*Facebook*', '*Instagram*', '*TikTok*', '*Twitter*',
    '*LinkedIn*', '*Disney*', '*Duolingo*', '*PicsArt*', '*Royal Revolt*', '*HiddenCity*', '*AdobePhotoshopExpress*', '*EclipseManager*'
)
function Get-DebloatPresent([string[]]$List) {
    # nombres de la lista que siguen instalados (con comodines)
    $names = if ($script:AppxNames) { $script:AppxNames } else { @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object Name) }
    @($List | Where-Object { $pat = $_; $names | Where-Object { $_ -like $pat } | Select-Object -First 1 })
}
function Remove-AppList([string[]]$List) {
    $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($n in $List) {
        foreach ($x in @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)) {
            try { Remove-AppxPackage -Package $x.PackageFullName -AllUsers -ErrorAction Stop; Write-Log "  quitada: $($x.Name)" }
            catch { Write-Log "  no se pudo quitar $($x.Name): $($_.Exception.Message)" 'WARN' }
        }
        $prov | Where-Object DisplayName -like $n | ForEach-Object {
            try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -AllUsers -ErrorAction Stop | Out-Null } catch {} }
    }
}

$Tweaks = @(
    # ---------------- Privacidad
    @{ Id = 'priv-telemetry'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Telemetría al mínimo'
       Desc = 'Diagnósticos al mínimo que permite Windows Pro, sin programa de mejora (CEIP), sin inventario de apps y sin las tareas programadas que recogen datos.'
       Reg  = @( (RegV "$P\DataCollection" 'AllowTelemetry' 0), (RegV "$P\DataCollection" 'DoNotShowFeedbackNotifications' 1),
                 (RegV "$P\DataCollection" 'AllowDeviceNameInTelemetry' 0), (RegV "$P\DataCollection" 'LimitDiagnosticLogCollection' 1),
                 (RegV "$P\DataCollection" 'DisableOneSettingsDownloads' 1), (RegV "$P\DataCollection" 'LimitDumpCollection' 1),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0),
                 (RegV "$P\AppCompat" 'AITEnable' 0), (RegV "$P\AppCompat" 'DisableInventory' 1), (RegV "$P\AppCompat" 'DisableUAR' 1),
                 (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1) )
       Task = @( '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
                 '\Microsoft\Windows\Application Experience\MareBackup',
                 '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
                 '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
                 '\Microsoft\Windows\Device Information\Device',
                 '\Microsoft\Windows\Device Information\Device User',
                 '\Microsoft\Windows\CloudExperienceHost\CreateObjectTask',
                 '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
                 '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
                 '\Microsoft\Windows\Maps\MapsToastTask',
                 '\Microsoft\Windows\Maps\MapsUpdateTask',
                 '\Microsoft\Windows\PI\Sqm-Tasks',
                 '\Microsoft\Office\OfficeTelemetryAgentLogOn2016',
                 '\Microsoft\Office\OfficeTelemetryAgentFallBack2016',
                 '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
                 '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
                 '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
                 '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
                 '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
                 '\Microsoft\Windows\Feedback\Siuf\DmClient',
                 '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
                 '\Microsoft\Windows\Autochk\Proxy' ) }
    @{ Id = 'priv-ads'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Publicidad, sugerencias e instalaciones silenciosas'
       Desc = 'Quita el ID de publicidad, las apps que Windows instala solo, los consejos, los anuncios de Configuración y del menú Inicio y el "terminemos de configurar tu PC".'
       Reg  = @( (RegV "$P\AdvertisingInfo" 'DisabledByGroupPolicy' 1), (RegV "$P\CloudContent" 'DisableWindowsConsumerFeatures' 1),
                 (RegV "$P\CloudContent" 'DisableSoftLanding' 1), (RegV "$P\CloudContent" 'DisableCloudOptimizedContent' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1),
                 (RegV $CDM 'SubscribedContent-338393Enabled' 0), (RegV $CDM 'SubscribedContent-310093Enabled' 0),
                 (RegV $CDM 'ContentDeliveryAllowed' 0), (RegV $CDM 'OemPreInstalledAppsEnabled' 0), (RegV $CDM 'PreInstalledAppsEnabled' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_AccountNotifications' 0),
                 (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 1),
                 (RegV $CDM 'SilentInstalledAppsEnabled' 0), (RegV $CDM 'SystemPaneSuggestionsEnabled' 0),
                 (RegV $CDM 'SubscribedContent-338388Enabled' 0), (RegV $CDM 'SubscribedContent-338389Enabled' 0),
                 (RegV $CDM 'SubscribedContent-353694Enabled' 0), (RegV $CDM 'SubscribedContent-353696Enabled' 0),
                 (RegV $CDM 'RotatingLockScreenOverlayEnabled' 0), (RegV $CDM 'SubscribedContent-338387Enabled' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0) ) }
    @{ Id = 'priv-ai'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Copilot, Recall y la IA de Windows'
       Desc = 'Desactiva Copilot, Recall, Click to Do, la IA de Paint y del Bloc de notas, y el servicio de IA que arranca con Windows (WSAIFabricSvc).'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1),
                 (RegV "$P\WindowsCopilot" 'TurnOffWindowsCopilot' 1),
                 (RegV "$P\WindowsAI" 'DisableAIDataAnalysis' 1), (RegV "$P\WindowsAI" 'AllowRecallEnablement' 0),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1),
                 (RegV 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1),
                 (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableCocreator' 1),
                 (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableGenerativeFill' 1),
                 (RegV 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableImageCreator' 1) )
       Svc  = @( (SvcV 'WSAIFabricSvc' 'Manual' 'Auto') ) }
    @{ Id = 'priv-activity'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Historial de actividad'
       Desc = 'Windows deja de registrar y subir lo que abres, y el portapapeles no se sincroniza con la nube.'
       Reg  = @( (RegV "$P\System" 'PublishUserActivities' 0), (RegV "$P\System" 'UploadUserActivities' 0), (RegV "$P\System" 'EnableActivityFeed' 0),
                 (RegV "$P\System" 'AllowCrossDeviceClipboard' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0) ) }
    @{ Id = 'priv-bing'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Sin Bing en el menú Inicio'
       Desc = 'La búsqueda del menú Inicio solo busca en tu PC: sin resultados web, sin "destacados" del día y sin buscar en tu cuenta en la nube.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1),
                 (RegV "$P\Windows Search" 'EnableDynamicContentInWSB' 0), (RegV "$P\Windows Search" 'AllowCloudSearch' 0),
                 (RegV "$P\Windows Search" 'ConnectedSearchUseWeb' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsMSACloudSearchEnabled' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsAADCloudSearchEnabled' 0) ) }
    @{ Id = 'priv-widgets'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Widgets y noticias'
       Desc = 'Desactiva el panel de Widgets (y su proceso WebView en segundo plano).'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0) ) }

    # ---------------- Servicios
    @{ Id = 'svc-telemetry'; Cat = 'Servicios'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Servicios de telemetría e informes de errores'
       Desc = 'DiagTrack (experiencias del usuario conectado), dmwappushservice, InventorySvc (inventario de apps para Microsoft) y WerSvc.'
       Svc  = @( (SvcV 'DiagTrack' 'Disabled' 'Auto'), (SvcV 'dmwappushservice' 'Disabled' 'Delayed'), (SvcV 'WerSvc' 'Disabled' 'Manual'),
                 (SvcV 'InventorySvc' 'Disabled' 'Delayed'), (SvcV 'diagnosticshub.standardcollector.service' 'Disabled' 'Manual') ) }
    @{ Id = 'svc-misc'; Cat = 'Servicios'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Servicios que nadie usa'
       Desc = 'Mapas sin conexión, modo demo de tienda y fax.'
       Svc  = @( (SvcV 'MapsBroker' 'Disabled' 'Delayed'), (SvcV 'RetailDemo' 'Disabled' 'Manual'), (SvcV 'Fax' 'Disabled' 'Manual') ) }
    @{ Id = 'svc-sysmain'; Cat = 'Servicios'; Risk = 'Moderado'; Presets = 'R', 'A'
       Name = 'SysMain (Superfetch)'
       Desc = 'Con SSD y 32 GB apenas aporta, y quita lecturas de disco en segundo plano. Las apps pueden tardar un poco más en abrir la primera vez.'
       Svc  = @( (SvcV 'SysMain' 'Disabled' 'Auto') ) }
    @{ Id = 'svc-search'; Cat = 'Servicios'; Risk = 'Moderado'; Presets = @('A')
       Name = 'Indexación de búsqueda'
       Desc = 'Quita el indexador. Las apps siguen saliendo en Inicio, pero buscar archivos y correos será más lento.'
       Svc  = @( (SvcV 'WSearch' 'Disabled' 'Delayed') ) }
    @{ Id = 'svc-print'; Cat = 'Servicios'; Risk = 'Moderado'; Presets = @()
       Name = 'Cola de impresión (Spooler)'
       Desc = 'Solo si NO imprimes ni usas "Imprimir a PDF".'
       Svc  = @( (SvcV 'Spooler' 'Disabled' 'Auto') ) }
    @{ Id = 'svc-geo'; Cat = 'Servicios'; Risk = 'Moderado'; Presets = @('A')
       Name = 'Ubicación'
       Desc = 'Desactiva la geolocalización. Deja de funcionar la zona horaria automática y el tiempo local.'
       Svc  = @( (SvcV 'lfsvc' 'Disabled' 'Manual') ) }
    @{ Id = 'svc-xbox'; Cat = 'Servicios'; Risk = 'Avanzado'; Presets = @()
       Name = 'Servicios de Xbox'
       Desc = 'NO lo actives si usas Game Pass, la app Xbox o juegos de la Microsoft Store. Steam/Epic/Riot no se ven afectados.'
       Svc  = @( (SvcV 'XblAuthManager' 'Disabled' 'Manual'), (SvcV 'XblGameSave' 'Disabled' 'Manual'), (SvcV 'XboxNetApiSvc' 'Disabled' 'Manual') ) }

    # ---------------- Rendimiento
    @{ Id = 'perf-powermode'; Cat = 'Rendimiento'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Modo de energía: Máximo rendimiento'
       Desc = 'Equivale a Configuración > Energía > "Mejor rendimiento" para la fuente de energía actual. En batería gasta más; ponlo enchufado.'
       Custom = @{
           Backup = { @{ Prev = (Get-OverlayGuid) } }
           Test   = { param($bk) (Get-OverlayGuid) -eq 'ded574b5-45a0-4f42-8737-46345c09c238' }
           Apply  = { param($bk) Set-OverlayGuid 'ded574b5-45a0-4f42-8737-46345c09c238' }
           Revert = { param($bk) $g = '00000000-0000-0000-0000-000000000000'; if ($bk -and $bk.Custom.Prev) { $g = $bk.Custom.Prev }; Set-OverlayGuid $g }
       } }
    @{ Id = 'perf-ultimate'; Cat = 'Rendimiento'; Risk = 'Avanzado'; Presets = @()
       Name = 'Plan "Rendimiento máximo" (Ultimate)'
       Desc = 'Crea y activa el plan oculto Ultimate Performance: la CPU nunca baja de frecuencia. Solo para jugar enchufado; más calor y ruido.'
       Custom = @{
           Backup = { @{ Prev = (Get-ActiveSchemeGuid); Created = $null } }
           Test   = { param($bk) [bool]($bk -and $bk.Custom.Created -and ((Get-ActiveSchemeGuid) -eq $bk.Custom.Created)) }
           Apply  = { param($bk)
               $out = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
               if (-not ("$out" -match '([0-9a-f]{8}-[0-9a-f-]{27})')) { throw "No se pudo crear el plan: $out" }
               $g = $Matches[1]; powercfg /setactive $g | Out-Null; $bk.Custom.Created = $g
               Sync-PowerTweaks }   # el plan nuevo nace con los valores de fábrica: se le copian los ajustes de energía aplicados
           Revert = { param($bk)
               $prev = '381b4222-f694-41f0-9685-ff5bb260df2e'
               if ($bk -and $bk.Custom.Prev) { $prev = $bk.Custom.Prev }
               powercfg /setactive $prev | Out-Null
               if ($bk -and $bk.Custom.Created) { powercfg /delete $bk.Custom.Created | Out-Null } }
       } }
    @{ Id = 'perf-mmcss'; Cat = 'Rendimiento'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Prioridad multimedia para juegos (MMCSS)'
       Desc = 'Reserva menos CPU para tareas de fondo y da prioridad alta a los hilos de juego registrados.'
       Reg  = @( (RegV $MM 'SystemResponsiveness' 10), (RegV "$MM\Tasks\Games" 'GPU Priority' 8), (RegV "$MM\Tasks\Games" 'Priority' 6),
                 (RegV "$MM\Tasks\Games" 'Scheduling Category' 'High' 'String'), (RegV "$MM\Tasks\Games" 'SFIO Priority' 'High' 'String') ) }
    @{ Id = 'perf-netthrottle'; Cat = 'Rendimiento'; Risk = 'Moderado'; Presets = @('A')
       Name = 'Sin limitación de red multimedia'
       Desc = 'Quita el límite que Windows pone a la red mientras suena audio o vídeo. Útil si juegas online con Discord o música abiertos.'
       Reg  = @( (RegV $MM 'NetworkThrottlingIndex' -1) ) }   # -1 = 0xFFFFFFFF
    @{ Id = 'perf-bgapps'; Cat = 'Rendimiento'; Risk = 'Moderado'; Presets = 'R', 'A'
       Name = 'Apps de la Store en segundo plano'
       Desc = 'Las apps de la Store no se ejecutan en segundo plano. Sus notificaciones (WhatsApp de la Store, Correo...) pueden no llegar.'
       Reg  = @( (RegV "$P\AppPrivacy" 'LetAppsRunInBackground' 2) ) }
    @{ Id = 'perf-faststartup'; Cat = 'Rendimiento'; Risk = 'Seguro'; Presets = 'R', 'A'; Reboot = $true
       Name = 'Desactivar Inicio rápido'
       Desc = 'Cada arranque carga el kernel y los drivers desde cero: evita fallos raros de drivers y de memoria acumulada.'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0) ) }
    @{ Id = 'perf-visual'; Cat = 'Rendimiento'; Risk = 'Seguro'; Presets = @('A')
       Name = 'Menos efectos visuales'
       Desc = 'Quita las transparencias y las animaciones de ventanas y barra de tareas. Requiere cerrar sesión.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0),
                 (RegV 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String') ) }
    @{ Id = 'perf-vbs'; Cat = 'Rendimiento'; Risk = 'Avanzado'; Presets = @(); Reboot = $true
       Name = 'Desactivar VBS / Integridad de memoria'
       Desc = 'Puede dar un 5-10 % más de FPS en algunos juegos, a cambio de menos protección contra malware a nivel de kernel. Algunos anticheat pueden pedir que esté activado.'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0),
                 (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0) ) }

    # ---------------- Juegos
    @{ Id = 'game-mode'; Cat = 'Juegos'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Modo juego activado'
       Desc = 'Windows prioriza el juego en primer plano y pausa Windows Update mientras juegas.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1), (RegV 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1) ) }
    @{ Id = 'game-hags'; Cat = 'Juegos'; Risk = 'Seguro'; Presets = 'R', 'A'; Reboot = $true
       Name = 'Programación de GPU acelerada por hardware'
       Desc = 'La GPU gestiona su propia cola de trabajo: menos latencia y menos carga de CPU. Necesario para Frame Generation.'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2) ) }
    @{ Id = 'game-dvr'; Cat = 'Juegos'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Sin grabación en segundo plano (Game DVR)'
       Desc = 'Desactiva la captura continua de la Xbox Game Bar. Si grabas clips con Win+G, déjalo como está.'
       Reg  = @( (RegV 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0), (RegV "$P\GameDVR" 'AllowGameDVR' 0) ) }
    @{ Id = 'game-mouse'; Cat = 'Juegos'; Risk = 'Seguro'; Presets = @('A')
       Name = 'Sin aceleración del ratón'
       Desc = 'Desactiva "Mejorar la precisión del puntero": el movimiento es 1:1, mejor para apuntar. Requiere cerrar sesión.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'), (RegV 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'),
                 (RegV 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String') ) }
    @{ Id = 'game-sticky'; Cat = 'Juegos'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Sin atajo de Teclas especiales'
       Desc = 'Pulsar Mayús cinco veces ya no saca el aviso de Teclas especiales en mitad de la partida.'
       Reg  = @( (RegV 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String' '510'),
                 (RegV 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String' '126'),
                 (RegV 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String' '62') ) }
    @{ Id = 'perf-startupdelay'; Cat = 'Rendimiento'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Sin retraso de las apps de inicio'
       Desc = 'Windows espera unos segundos antes de abrir las apps de inicio. Con SSD no hace falta.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0) ) }

    # ---------------- Actualizaciones
    @{ Id = 'wu-noreboot'; Cat = 'Actualizaciones'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Sin reinicios automáticos con la sesión abierta'
       Desc = 'Windows Update no reinicia el equipo mientras estás conectado; te avisa y reinicias tú.'
       Reg  = @( (RegV "$P\WindowsUpdate\AU" 'NoAutoRebootWithLoggedOnUsers' 1) ) }
    @{ Id = 'wu-delivery'; Cat = 'Actualizaciones'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Sin compartir actualizaciones con otros equipos'
       Desc = 'Desactiva la Optimización de distribución (P2P): tu conexión no sube actualizaciones a otros PCs mientras juegas online.'
       Reg  = @( (RegV "$P\DeliveryOptimization" 'DODownloadMode' 0) ) }
    @{ Id = 'wu-drivers'; Cat = 'Actualizaciones'; Risk = 'Moderado'; Presets = @('A')
       Name = 'No instalar drivers desde Windows Update'
       Desc = 'Evita que Windows sustituya el driver de AMD/NVIDIA que instalaste. Los drivers de chipset, Wi-Fi y audio tendrás que ponerlos tú.'
       Reg  = @( (RegV "$P\WindowsUpdate" 'ExcludeWUDriversInQualityUpdate' 1) ) }
    @{ Id = 'wu-feature'; Cat = 'Actualizaciones'; Risk = 'Moderado'; Presets = @()
       Name = 'Retrasar las versiones nuevas de Windows un año'
       Desc = 'Sigues recibiendo los parches de seguridad, pero las actualizaciones grandes (25H2, 26H2...) llegan 365 días después, ya pulidas.'
       Reg  = @( (RegV "$P\WindowsUpdate" 'DeferFeatureUpdates' 1), (RegV "$P\WindowsUpdate" 'DeferFeatureUpdatesPeriodInDays' 365) ) }

    # ---------------- Interfaz
    @{ Id = 'ui-ext'; Cat = 'Interfaz'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Mostrar extensiones de archivo'
       Desc = 'Ver ".exe", ".pdf"... también es más seguro (evita archivos "foto.jpg.exe").'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0) ) }
    @{ Id = 'ui-context'; Cat = 'Interfaz'; Risk = 'Seguro'; Presets = @()
       Name = 'Menú contextual clásico'
       Desc = 'Recupera el menú de clic derecho completo de Windows 10 (sin "Mostrar más opciones"). Reinicia el Explorador para verlo.'
       Custom = @{
           Test   = { param($bk) Test-Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' }
           Apply  = { param($bk) $k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
                      New-Item -Path $k -Force | Out-Null; Set-Item -LiteralPath $k -Value '' }
           Revert = { param($bk) Remove-Item 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction SilentlyContinue }
       } }
    @{ Id = 'ui-endtask'; Cat = 'Interfaz'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = '"Finalizar tarea" en la barra de tareas'
       Desc = 'Clic derecho en un icono de la barra de tareas para cerrar a la fuerza un juego colgado, sin abrir el Administrador de tareas.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' 1) ) }

    # ---------------- Apps
    @{ Id = 'app-debloat'; Cat = 'Apps'; Risk = 'Moderado'; Presets = 'R', 'A'; Irreversible = $true
       Name = 'Quitar apps preinstaladas'
       Desc = 'Unas 60 apps para todos los usuarios: Noticias, Tiempo, Clipchamp, Solitaire, Teams personal, Copilot, Outlook (nuevo), Office Hub, To Do, Mapas, Dev Home, Widgets, Skype, Correo y Calendar antiguos, y las patrocinadas (Candy Crush, TikTok, Facebook, Disney+...). Se quedan Fotos, Paint, Bloc de notas, Recortes, Calculadora, Cámara y la Store.'
       Custom = @{
           Test   = { param($bk) -not (Get-DebloatPresent $DebloatApps) }
           Apply  = { param($bk) Remove-AppList $DebloatApps }
           Revert = { param($bk) Write-Log 'Las apps quitadas no se reinstalan solas: búscalas en Microsoft Store si quieres alguna.' 'WARN' }
       } }
    @{ Id = 'app-onedrive'; Cat = 'Apps'; Risk = 'Moderado'; Presets = @('A'); Irreversible = $true
       Name = 'Desinstalar OneDrive'
       Desc = 'Quita OneDrive y su sincronización en segundo plano. Tus archivos de la carpeta OneDrive se quedan en el disco. Se puede reinstalar desde onedrive.com.'
       Custom = @{
           Test   = { param($bk) -not ((Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")) }
           Apply  = { param($bk)
               Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
               $out = & winget uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements --disable-interactivity 2>&1
               if ($LASTEXITCODE -ne 0) {
                   $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
                   if (-not $setup) { throw "winget no pudo desinstalarlo: $($out | Select-Object -Last 1)" }
                   Start-Process $setup -ArgumentList '/uninstall' -Wait
               } }
           Revert = { param($bk) Write-Log 'OneDrive no se reinstala solo: descárgalo de onedrive.com o con "winget install Microsoft.OneDrive".' 'WARN' }
       } }
)

# ---------- Latencia avanzada (ideas de Hone, Atlas y los foros de latencia)
# Ajustes de un valor del plan de energía actual (solo enchufado / AC). Lee el valor con powercfg /query:
# las dos últimas cifras 0x... de la salida son el índice AC y el DC, en cualquier idioma.
function Get-PowerAc([string]$Sub, [string]$Setting) {
    $hex = [regex]::Matches((powercfg /query SCHEME_CURRENT $Sub $Setting | Out-String), '0x([0-9a-fA-F]{8})')
    if ($hex.Count -ge 2) { return [Convert]::ToInt32($hex[$hex.Count - 2].Groups[1].Value, 16) }
    # ajuste oculto: powercfg no lo enseña; se lee del plan activo o, si no se ha tocado, del valor por defecto del plan
    $scheme = Get-ActiveSchemeGuid
    $u = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$scheme\$Sub\$Setting"
    try { return [int](Get-ItemProperty $u -Name ACSettingIndex -ErrorAction Stop).ACSettingIndex } catch {}
    $d = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\$Sub\$Setting\DefaultPowerSchemeValues\$scheme"
    try { return [int](Get-ItemProperty $d -Name ACSettingIndex -ErrorAction Stop).ACSettingIndex } catch {}
    $null
}
function Set-PowerAc([string]$Sub, [string]$Setting, [int]$Value, [string]$Scheme = 'SCHEME_CURRENT') {
    powercfg /setacvalueindex $Scheme $Sub $Setting $Value | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "powercfg no aceptó el valor $Value" }
    powercfg /setactive SCHEME_CURRENT | Out-Null
}
# Los ajustes de energía van al plan activo, pero la copia recuerda en qué plan se hicieron: al revertir se
# restauran en ese plan (si sigue existiendo) y en el activo, aunque entre medias se haya cambiado de plan.
function Restore-PowerAc([string]$Sub, [string]$Setting, [int]$Value, $Bk) {
    if ($Bk -and $Bk.Custom.Scheme -and $Bk.Custom.Scheme -ne (Get-ActiveSchemeGuid)) {
        powercfg /query $Bk.Custom.Scheme $Sub $Setting *> $null
        if ($LASTEXITCODE -eq 0) { Set-PowerAc $Sub $Setting $Value $Bk.Custom.Scheme }
    }
    Set-PowerAc $Sub $Setting $Value
}
# al cambiar de plan (Ultimate), los ajustes de energía que estaban aplicados se copian al plan nuevo
function Sync-PowerTweaks {
    foreach ($tw in $Tweaks) {
        if ($tw.Custom -and $tw.Custom.PowerSub -and (Get-Backup $tw.Id)) {
            try { Set-PowerAc $tw.Custom.PowerSub $tw.Custom.PowerSetting $tw.Custom.PowerValue } catch {}
        }
    }
}
function New-PowerCustom([string]$Sub, [string]$Setting, [int]$Value, [int]$Default) {
    @{
        PowerSub = $Sub; PowerSetting = $Setting; PowerValue = $Value
        Backup = [scriptblock]::Create("@{ Prev = (Get-PowerAc '$Sub' '$Setting'); Scheme = (Get-ActiveSchemeGuid) }")
        Test   = [scriptblock]::Create("param(`$bk) `$v = Get-PowerAc '$Sub' '$Setting'; if (`$null -eq `$v) { `$null } else { `$v -eq $Value }")
        Apply  = [scriptblock]::Create("param(`$bk) Set-PowerAc '$Sub' '$Setting' $Value")
        Revert = [scriptblock]::Create("param(`$bk) `$p = $Default; if (`$bk -and `$null -ne `$bk.Custom.Prev) { `$p = [int]`$bk.Custom.Prev }; Restore-PowerAc '$Sub' '$Setting' `$p `$bk")
        Diff   = [scriptblock]::Create("param(`$bk, `$rev) `$c = Get-PowerAc '$Sub' '$Setting'; `$a = if (`$rev) { if (`$bk -and `$null -ne `$bk.Custom.Prev) { `$bk.Custom.Prev } else { $Default } } else { $Value }; New-DiffLine 'power' 'powercfg AC $($Sub.Substring(0,8))/$($Setting.Substring(0,8))' `"`$c`" `"`$a`"")
    }
}
# Claves de red y de GPU que dependen del equipo
function Get-NicKeys {
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -ErrorAction SilentlyContinue | Where-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        ($p.DhcpIPAddress -and $p.DhcpIPAddress -ne '0.0.0.0') -or ($p.IPAddress -and "$($p.IPAddress)" -ne '0.0.0.0')
    } | ForEach-Object { $_.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE', 'HKLM:' }
}
function Get-GpuMsiKeys {
    # Win32_VideoController en vez de Get-PnpDevice: cargar el módulo PnpDevice tarda más de un segundo
    if ($null -eq $script:GpuPnpIds) {
        $script:GpuPnpIds = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object PNPDeviceID | Where-Object { $_ -like 'PCI\*' })
    }
    foreach ($id in $script:GpuPnpIds) { "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" }
}
function New-DynRegCustom([string]$KeysFn, [string[]]$Names, [int]$Value) {
    # varios valores DWORD en claves que se descubren en el momento (con $KeysFn); guarda y restaura cada uno.
    # Los bloques se generan como texto para que vean las funciones del script (un closure no las ve).
    $ns = '@(' + (($Names | ForEach-Object { "'$_'" }) -join ',') + ')'
    @{
        Backup = [scriptblock]::Create("`$out = @(); foreach (`$k in @($KeysFn)) { foreach (`$n in $ns) { `$out += Get-RegState @{ Path = `$k; Name = `$n } } }; @{ States = `$out }")
        Test   = [scriptblock]::Create("param(`$bk) `$ks = @($KeysFn); if (-not `$ks) { return `$null }; foreach (`$k in `$ks) { foreach (`$n in $ns) { if (-not (Test-Reg @{ Path = `$k; Name = `$n; Value = $Value })) { return `$false } } }; `$true")
        Apply  = [scriptblock]::Create("param(`$bk) foreach (`$k in @($KeysFn)) { foreach (`$n in $ns) { Set-RegValue `$k `$n $Value 'DWord' } }")
        Diff   = [scriptblock]::Create("param(`$bk, `$rev) foreach (`$k in @($KeysFn)) { foreach (`$n in $ns) { `$s = Get-RegState @{ Path = `$k; Name = `$n }; `$o = if (`$bk) { @(`$bk.Custom.States) | Where-Object { `$_.Path -eq `$k -and `$_.Name -eq `$n } | Select-Object -First 1 }; `$a = if (`$rev) { Format-RegState `$o } else { '$Value (DWord)' }; New-DiffLine 'reg' ((Get-ShortKey `$k) + '\' + `$n) (Format-RegState `$s) `$a } }")
        Revert = [scriptblock]::Create("param(`$bk) if (`$bk -and `$bk.Custom.States) { foreach (`$s in `$bk.Custom.States) { if (`$s.Exists) { Set-RegValue `$s.Path `$s.Name `$s.Value `$s.Kind } else { Remove-RegValue `$s.Path `$s.Name } } } else { foreach (`$k in @($KeysFn)) { foreach (`$n in $ns) { Remove-RegValue `$k `$n } } }")
    }
}

$Tweaks += @(
    @{ Id = 'lat-priosep'; Cat = 'Latencia'; Risk = 'Moderado'; Presets = @('A')
       Name = 'Prioridad fuerte para la ventana activa'
       Desc = 'Win32PrioritySeparation a 0x26: turnos de CPU cortos y con ventaja para el programa en primer plano, que es el juego.'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38 'DWord' 2) ) }
    @{ Id = 'lat-usb'; Cat = 'Latencia'; Risk = 'Moderado'; Presets = @('A')
       Name = 'Sin suspensión selectiva de USB'
       Desc = 'Windows deja de dormir los puertos USB para ahorrar energía: ratón, teclado y mando sin microcortes. Solo enchufado.'
       Custom = (New-PowerCustom '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 1) }
    @{ Id = 'lat-pcie'; Cat = 'Latencia'; Risk = 'Moderado'; Presets = @('A')
       Name = 'PCI Express sin ahorro de energía'
       Desc = 'Desactiva la administración de energía del enlace PCIe: la GPU y el SSD no bajan de estado entre fotogramas. Solo enchufado.'
       Custom = (New-PowerCustom '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5' 0 1) }
    @{ Id = 'lat-cores'; Cat = 'Latencia'; Risk = 'Avanzado'; Presets = @()
       Name = 'Sin aparcamiento de núcleos'
       Desc = 'Todos los núcleos de la CPU quedan despiertos enchufado. Menos latencia al empezar una carga, más consumo y temperatura.'
       Custom = (New-PowerCustom '54533251-82be-4824-96c1-47b60b740d00' '0cc5b647-c1df-4637-891a-dec35c318583' 100 10) }
    @{ Id = 'lat-nagle'; Cat = 'Latencia'; Risk = 'Avanzado'; Presets = @(); Reboot = $true
       Name = 'Desactivar el algoritmo de Nagle'
       Desc = 'TCP envía cada paquete al momento en vez de agruparlos. Solo ayuda en juegos que usan TCP (MMO, MOBA antiguos); los shooters usan UDP.'
       Custom = (New-DynRegCustom 'Get-NicKeys' @('TcpAckFrequency', 'TCPNoDelay') 1) }
    @{ Id = 'lat-msi'; Cat = 'Latencia'; Risk = 'Avanzado'; Presets = @(); Reboot = $true
       Name = 'Modo MSI para la tarjeta gráfica'
       Desc = 'La GPU avisa a la CPU con interrupciones por mensaje en vez de por línea. Los drivers recientes de AMD y NVIDIA ya suelen venir así.'
       Custom = (New-DynRegCustom 'Get-GpuMsiKeys' @('MSISupported') 1) }
    @{ Id = 'lat-memcomp'; Cat = 'Latencia'; Risk = 'Moderado'; Presets = @('A'); Reboot = $true
       Name = 'Sin compresión de memoria'
       Desc = 'Con 16 GB o más, comprimir la RAM gasta CPU sin necesidad. Con poca memoria es mejor dejarla activada.'
       Custom = @{
           Test   = { param($bk) try { -not (Get-MMAgent -ErrorAction Stop).MemoryCompression } catch { $null } }
           Apply  = { param($bk) Disable-MMAgent -MemoryCompression -ErrorAction Stop }
           Revert = { param($bk) Enable-MMAgent -MemoryCompression -ErrorAction Stop }
       } }
)

# ---------- más basura de Windows 11 (lo que quitan los optimizadores conocidos)
function Get-EdgeSetup {
    Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe", "$env:ProgramFiles\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
}
$EdgePol = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$XboxApps = @('Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxGameCallableUI')
$PhoneApps = @('Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice')
# componentes opcionales antiguos: nombre de la capacidad y el archivo que delata si sigue instalada
$OldCapabilities = @(
    @{ Cap = 'App.StepsRecorder*';             File = "$env:SystemRoot\System32\psr.exe" }
    @{ Cap = 'Microsoft.Windows.WordPad*';     File = "$env:ProgramFiles\Windows NT\Accessories\wordpad.exe" }
    @{ Cap = 'Media.WindowsMediaPlayer*';      File = "$env:ProgramFiles\Windows Media Player\wmplayer.exe" }
    @{ Cap = 'MathRecognizer*';                File = "$env:CommonProgramFiles\Microsoft Shared\Ink\mip.exe" }
)

$Tweaks += @(
    # ---------------- Privacidad (más)
    @{ Id = 'priv-input'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Escritura y voz sin enviar datos'
       Desc = 'Windows deja de aprender de lo que escribes y dibujas, de leer tus contactos para el teclado y de mandar la voz a Microsoft.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1),
                 (RegV 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1),
                 (RegV 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0),
                 (RegV 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0),
                 (RegV 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0) ) }
                 # TailoredExperiencesWithDiagnosticDataEnabled ya lo pone priv-ads: dos ajustes sobre el mismo valor se pisan las copias
    @{ Id = 'priv-feedback'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Sin encuestas de opinión'
       Desc = 'Windows no te vuelve a preguntar "¿qué te parece...?" ni manda la respuesta.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0), (RegV 'HKCU:\Software\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0) ) }
    @{ Id = 'priv-edge'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Microsoft Edge sin segundo plano ni telemetría'
       Desc = 'Edge deja de quedarse abierto al cerrarlo y de precargarse al encender (son 6 a 10 procesos y unos 300 MB de RAM), sin barra de Copilot, sin compras ni recomendaciones. Edge dirá "administrado por tu organización".'
       Reg  = @( (RegV $EdgePol 'StartupBoostEnabled' 0), (RegV $EdgePol 'BackgroundModeEnabled' 0), (RegV $EdgePol 'HubsSidebarEnabled' 0),
                 (RegV $EdgePol 'PersonalizationReportingEnabled' 0), (RegV $EdgePol 'ShowRecommendationsEnabled' 0), (RegV $EdgePol 'DiagnosticData' 0),
                 (RegV $EdgePol 'EdgeShoppingAssistantEnabled' 0), (RegV $EdgePol 'UserFeedbackAllowed' 0), (RegV $EdgePol 'ConfigureDoNotTrack' 1),
                 (RegV $EdgePol 'SpotlightExperiencesAndRecommendationsEnabled' 0), (RegV $EdgePol 'EdgeCollectionsEnabled' 0) ) }
    @{ Id = 'priv-office'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Office sin telemetría'
       Desc = 'Word, Excel y compañía dejan de enviar datos de uso y de pedir opinión. Si no tienes Office, no hace nada.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\ClientTelemetry' 'DisableTelemetry' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\ClientTelemetry' 'SendTelemetry' 3),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\Feedback' 'Enabled' 0),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Office\Common\ClientTelemetry' 'SendTelemetry' 3) ) }
    @{ Id = 'priv-devtools'; Cat = 'Privacidad'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'PowerShell y .NET sin telemetría'
       Desc = 'Variables de entorno oficiales para que PowerShell 7 y las herramientas de .NET no envíen datos de uso.'
       Reg  = @( (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'POWERSHELL_TELEMETRY_OPTOUT' '1' 'String'),
                 (RegV 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' 'DOTNET_CLI_TELEMETRY_OPTOUT' '1' 'String') ) }
    @{ Id = 'priv-findmy'; Cat = 'Privacidad'; Risk = 'Moderado'; Presets = @()
       Name = 'Sin "Encontrar mi dispositivo"'
       Desc = 'Windows deja de guardar la ubicación del equipo en tu cuenta. En un portátil es lo que te ayuda si te lo roban.'
       Reg  = @( (RegV 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0) ) }

    # ---------------- Servicios (más)
    @{ Id = 'svc-manual'; Cat = 'Servicios'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Servicios bajo demanda'
       Desc = 'Pasan a manual: arrancan solo cuando algo los necesita, como hace WinUtil. Seguimiento de accesos directos, Asistente de compatibilidad, uso de datos, dispositivos conectados, salud de Windows, escáneres y los actualizadores de Edge y Google.'
       Svc  = @( (SvcV 'TrkWks' 'Manual' 'Auto'), (SvcV 'PcaSvc' 'Manual' 'Delayed'), (SvcV 'DusmSvc' 'Manual' 'Auto'), (SvcV 'CDPSvc' 'Manual' 'Delayed'),
                 (SvcV 'whesvc' 'Manual' 'Delayed'), (SvcV 'StiSvc' 'Manual' 'Auto'), (SvcV 'edgeupdate' 'Manual' 'Delayed'), (SvcV 'edgeupdatem' 'Manual' 'Delayed'),
                 (SvcV 'gupdate' 'Manual' 'Delayed'), (SvcV 'gupdatem' 'Manual' 'Manual') ) }
    @{ Id = 'svc-diag'; Cat = 'Servicios'; Risk = 'Avanzado'; Presets = @('A')
       Name = 'Diagnóstico y solucionadores de Windows'
       Desc = 'Desactiva el servicio de directivas de diagnóstico y sus anfitriones. Dejan de funcionar los solucionadores de problemas y el uso de red por app del Administrador de tareas.'
       Svc  = @( (SvcV 'DPS' 'Disabled' 'Auto'), (SvcV 'WdiServiceHost' 'Disabled' 'Manual'), (SvcV 'WdiSystemHost' 'Disabled' 'Manual'),
                 (SvcV 'TroubleshootingSvc' 'Disabled' 'Manual') ) }
    @{ Id = 'svc-netdisc'; Cat = 'Servicios'; Risk = 'Moderado'; Presets = @('A')
       Name = 'Descubrimiento de dispositivos en la red'
       Desc = 'SSDP y el host UPnP buscan televisores, impresoras y NAS en tu red sin parar. Si no compartes nada en la red de casa, sobran. El UPnP de los juegos (abrir puertos del router) no depende de ellos.'
       Svc  = @( (SvcV 'SSDPSRV' 'Disabled' 'Manual'), (SvcV 'upnphost' 'Disabled' 'Manual'), (SvcV 'FDResPub' 'Disabled' 'Manual') ) }
    @{ Id = 'svc-iphelper'; Cat = 'Servicios'; Risk = 'Avanzado'; Presets = @()
       Name = 'Asistente de IP (túneles IPv6)'
       Desc = 'Quita Teredo y los túneles IPv6. Algunas VPN y el chat de grupo de Xbox lo usan; si no, es un proceso menos.'
       Svc  = @( (SvcV 'iphlpsvc' 'Disabled' 'Auto') ) }

    # ---------------- Rendimiento (más)
    @{ Id = 'perf-hibernate'; Cat = 'Rendimiento'; Risk = 'Moderado'; Presets = @()
       Name = 'Desactivar la hibernación'
       Desc = 'Borra hiberfil.sys (entre el 40 % y el 100 % de tu RAM, varios GB de disco). Mientras esté apagada tampoco hay inicio rápido; al volver a activarla, el inicio rápido queda como diga "Desactivar Inicio rápido". En un portátil, con la batería agotada se apagará en vez de hibernar.'
       Custom = @{
           Test   = { param($bk) try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction Stop).HibernateEnabled -eq 0 } catch { $false } }
           Apply  = { param($bk) powercfg /hibernate off | Out-Null }
           Revert = { param($bk) powercfg /hibernate on | Out-Null }
       } }

    # ---------------- Interfaz (más)
    @{ Id = 'ui-spotlight'; Cat = 'Interfaz'; Risk = 'Seguro'; Presets = 'R', 'A'
       Name = 'Sin Windows Spotlight'
       Desc = 'Quita las fotos e "información" que Windows descarga para la pantalla de bloqueo y el escritorio. Pones tu fondo y ya.'
       Reg  = @( (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1),
                 (RegV 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableSpotlightCollectionOnDesktop' 1) ) }
    @{ Id = 'ui-taskbar'; Cat = 'Interfaz'; Risk = 'Seguro'; Presets = @('A')
       Name = 'Barra de tareas limpia'
       Desc = 'Quita el botón de Vista de tareas y deja la búsqueda solo como icono. Win+Tab y Win+S siguen funcionando.'
       Reg  = @( (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' 0),
                 (RegV 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1) ) }

    # ---------------- Apps (más)
    @{ Id = 'app-phonelink'; Cat = 'Apps'; Risk = 'Moderado'; Presets = @('A'); Irreversible = $true
       Name = 'Quitar Enlace móvil'
       Desc = 'La app que conecta el móvil con el PC y se queda en segundo plano (PhoneExperienceHost, unos 150 MB aquí). Se puede reinstalar desde la Store.'
       Custom = @{
           Test   = { param($bk) -not (Get-DebloatPresent $PhoneApps) }
           Apply  = { param($bk) Stop-Process -Name PhoneExperienceHost -Force -ErrorAction SilentlyContinue; Remove-AppList $PhoneApps }
           Revert = { param($bk) Write-Log 'Enlace móvil no se reinstala solo: búscalo en Microsoft Store.' 'WARN' }
       } }
    @{ Id = 'app-capabilities'; Cat = 'Apps'; Risk = 'Moderado'; Presets = @('A'); Irreversible = $true; Reboot = $true
       Name = 'Quitar componentes antiguos de Windows'
       Desc = 'Grabación de acciones de usuario, WordPad, Windows Media Player clásico y el panel de expresiones matemáticas. Se pueden volver a añadir en Configuración > Sistema > Características opcionales.'
       Custom = @{
           # los archivos pueden seguir ahí hasta reiniciar: la marca evita que se vuelva a lanzar DISM para nada
           Test   = { param($bk) (Test-Path (Join-Path $script:Secure 'capabilities.done')) -or -not ($OldCapabilities | Where-Object { Test-Path $_.File }) }
           Apply  = { param($bk)
               $caps = @(Get-WindowsCapability -Online -ErrorAction Stop | Where-Object State -eq 'Installed')
               foreach ($oc in $OldCapabilities) {
                   foreach ($c in $caps | Where-Object Name -like $oc.Cap) {
                       try { Remove-WindowsCapability -Online -Name $c.Name -ErrorAction Stop | Out-Null; Write-Log "  quitado: $($c.Name)" }
                       catch { Write-Log "  no se pudo quitar $($c.Name): $($_.Exception.Message)" 'WARN' }
                   }
               }
               Set-Content -LiteralPath (Join-Path $script:Secure 'capabilities.done') -Value (Get-Date).ToString('s') }
           Revert = { param($bk) Write-Log 'Los componentes se vuelven a añadir en Configuración > Sistema > Características opcionales.' 'WARN' }
       } }
    @{ Id = 'app-xbox'; Cat = 'Apps'; Risk = 'Avanzado'; Presets = @(); Irreversible = $true
       Name = 'Quitar las apps de Xbox'
       Desc = 'App Xbox, Game Bar y sus complementos. NO lo hagas si usas Game Pass, juegos de la Store, Win+G o el chat de Xbox. Steam, Epic y los juegos normales no se ven afectados.'
       Custom = @{
           Test   = { param($bk) -not (Get-DebloatPresent $XboxApps) }
           Apply  = { param($bk) Remove-AppList $XboxApps }
           Revert = { param($bk) Write-Log 'Las apps de Xbox se reinstalan desde Microsoft Store (Xbox y Xbox Game Bar).' 'WARN' }
       } }
    @{ Id = 'app-edge'; Cat = 'Apps'; Risk = 'Avanzado'; Presets = @(); Irreversible = $true
       Name = 'Desinstalar Microsoft Edge'
       Desc = 'Quita el navegador Edge y evita que Windows Update lo reinstale. WebView2, que usan muchos launchers, se queda. Instala otro navegador antes. Windows solo lo permite del todo en Europa; si no, puede negarse.'
       Custom = @{
           Test   = { param($bk) -not ((Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") -or (Test-Path "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")) }
           Apply  = { param($bk)
               $setup = Get-EdgeSetup
               if (-not $setup) { throw 'No encuentro el desinstalador de Edge (setup.exe).' }
               Set-RegValue 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1 'DWord'
               Stop-Process -Name msedge -Force -ErrorAction SilentlyContinue
               $p = Start-Process $setup.FullName -ArgumentList '--uninstall --system-level --verbose-logging --force-uninstall' -Wait -PassThru
               if (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") { throw "Windows no ha dejado desinstalar Edge (código $($p.ExitCode)). Desde Configuración > Aplicaciones puedes intentarlo si estás en la UE." } }
           Revert = { param($bk) Remove-RegValue 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium'; Write-Log 'Edge se reinstala desde microsoft.com/edge o con "winget install Microsoft.Edge".' 'WARN' }
       } }
)

# icono de cada ajuste (nombres de assets\icons.json)
$TweakIcons = @{
    'priv-telemetry' = 'broadcast'; 'priv-ads' = 'megaphone'; 'priv-ai' = 'eye-slash'; 'priv-activity' = 'clock-counter-clockwise'; 'priv-bing' = 'magnifying-glass'; 'priv-widgets' = 'newspaper'
    'svc-telemetry' = 'bug'; 'svc-misc' = 'gear-six'; 'svc-sysmain' = 'hard-drives'; 'svc-search' = 'files'; 'svc-print' = 'printer'; 'svc-geo' = 'map-pin'; 'svc-xbox' = 'headset'
    'perf-powermode' = 'gauge'; 'perf-ultimate' = 'fire'; 'perf-mmcss' = 'speaker-high'; 'perf-netthrottle' = 'arrows-down-up'; 'perf-bgapps' = 'app-window'
    'perf-faststartup' = 'power'; 'perf-visual' = 'magic-wand'; 'perf-vbs' = 'shield-slash'; 'perf-startupdelay' = 'timer'
    'game-mode' = 'game-controller'; 'game-hags' = 'graphics-card'; 'game-dvr' = 'record'; 'game-mouse' = 'mouse'; 'game-sticky' = 'keyboard'
    'wu-noreboot' = 'arrows-clockwise'; 'wu-delivery' = 'share-network'; 'wu-drivers' = 'circuitry'; 'wu-feature' = 'calendar-x'
    'ui-ext' = 'file-text'; 'ui-context' = 'list-dashes'; 'ui-endtask' = 'x-square'
    'app-debloat' = 'trash'; 'app-onedrive' = 'cloud-slash'
    'priv-input' = 'microphone-slash'; 'priv-feedback' = 'chat-circle-dots'; 'priv-edge' = 'browser'; 'priv-office' = 'microsoft-word-logo'
    'priv-devtools' = 'terminal-window'; 'priv-findmy' = 'crosshair'; 'svc-manual' = 'toggle-left'; 'svc-diag' = 'stethoscope'; 'svc-netdisc' = 'devices'
    'svc-iphelper' = 'globe-simple'; 'perf-hibernate' = 'moon-stars'; 'ui-spotlight' = 'sun-horizon'; 'ui-taskbar' = 'layout'
    'app-phonelink' = 'device-mobile'; 'app-capabilities' = 'puzzle-piece'; 'app-xbox' = 'game-controller'; 'app-edge' = 'x-circle'
    'lat-priosep' = 'ranking'; 'lat-usb' = 'usb'; 'lat-pcie' = 'plugs-connected'; 'lat-cores' = 'cpu'; 'lat-nagle' = 'network'; 'lat-msi' = 'lightning'; 'lat-memcomp' = 'arrows-in'
}

# ---------- perfiles (exportar / importar la selección)
function Export-Profile([string]$Path, [string[]]$Ids) {
    [pscustomobject]@{ app = 'OptiEleven'; version = 1; creado = (Get-Date).ToString('s'); ajustes = @($Ids) } |
        ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Import-Profile([string]$Path) {
    $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $j.ajustes) { throw 'El archivo no es un perfil de OptiEleven.' }
    $known = @($Tweaks | ForEach-Object { $_.Id })
    @($j.ajustes | Where-Object { $known -contains $_ })
}

# ============================================================ motor
function Test-Tweak($t) {
    $bk = Get-Backup $t.Id
    $checks = New-Object System.Collections.Generic.List[bool]
    foreach ($r in @($t.Reg))  { if ($r) { $checks.Add([bool](Test-Reg $r)) } }
    foreach ($s in @($t.Svc))  { if ($s) { $st = Get-SvcState $s.Name; if ($st) { $checks.Add([bool]($st.Start -eq (Get-StartCode $s.Start))) } } }
    foreach ($x in @($t.Task)) { if ($x) { $st = Get-TaskState $x; if ($st) { $checks.Add([bool](-not $st.Enabled)) } } }
    if ($t.Custom -and $t.Custom.Test) { $checks.Add([bool](& $t.Custom.Test $bk)) }
    if ($checks.Count -eq 0) { return $null }
    return -not ($checks -contains $false)
}

function Invoke-ApplyTweak($t) {
    $bk = Get-Backup $t.Id
    if (-not $bk) {
        $regs = @(); $svcs = @(); $tasks = @()
        foreach ($r in @($t.Reg))  { if ($r) { $regs += Get-RegState $r } }
        foreach ($s in @($t.Svc))  { if ($s) { $st = Get-SvcState $s.Name; if ($st) { $svcs += $st } } }
        foreach ($x in @($t.Task)) { if ($x) { $st = Get-TaskState $x; if ($st) { $tasks += $st } } }
        $custom = $null
        if ($t.Custom -and $t.Custom.Backup) { $custom = & $t.Custom.Backup }
        $bk = [pscustomobject]@{ Time = (Get-Date).ToString('s'); Reg = $regs; Svc = $svcs; Task = $tasks; Custom = $custom }
        if (-not $t.Irreversible) { Save-Backup $t.Id $bk }
    }
    foreach ($r in @($t.Reg))  { if ($r) { Set-RegValue $r.Path $r.Name $r.Value $r.Kind } }
    foreach ($s in @($t.Svc))  { if ($s) { Set-SvcStart $s.Name (Get-StartCode $s.Start) ($s.Start -eq 'Delayed') } }
    foreach ($x in @($t.Task)) { if ($x) { Set-TaskEnabled $x $false } }
    if ($t.Custom -and $t.Custom.Apply) {
        & $t.Custom.Apply $bk
        if (-not $t.Irreversible) { Save-Backup $t.Id $bk }   # el Apply puede haber guardado datos (p. ej. el GUID creado)
    }
}

function Invoke-RevertTweak($t) {
    $bk = Get-Backup $t.Id
    if ($t.Custom -and $t.Custom.Revert) { & $t.Custom.Revert $bk }
    if ($bk) {
        foreach ($s in @($bk.Reg))  { if ($s) { if ($s.Exists) { Set-RegValue $s.Path $s.Name $s.Value $s.Kind } else { Remove-RegValue $s.Path $s.Name } } }
        foreach ($s in @($bk.Svc))  { if ($s) { Set-SvcStart $s.Name ([int]$s.Start) ([bool]$s.Delayed) } }
        foreach ($s in @($bk.Task)) { if ($s -and $s.Enabled) { Set-TaskEnabled $s.Task $true } }
        Remove-Backup $t.Id
    }
    else {
        # sin copia (aplicado fuera del panel): volver a los valores por defecto de Windows
        foreach ($r in @($t.Reg))  { if ($r) { if ($null -ne $r.Default) { Set-RegValue $r.Path $r.Name $r.Default $r.Kind } else { Remove-RegValue $r.Path $r.Name } } }
        foreach ($s in @($t.Svc))  { if ($s) { Set-SvcStart $s.Name (Get-StartCode $s.Default) ($s.Default -eq 'Delayed') } }
        foreach ($x in @($t.Task)) { if ($x) { Set-TaskEnabled $x $true } }
    }
}

function New-RestorePoint {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        $old = (Get-ItemProperty $k -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        Set-ItemProperty $k -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord
        Write-Log 'Creando punto de restauración (puede tardar un minuto)...'
        Checkpoint-Computer -Description 'OptiEleven' -RestorePointType MODIFY_SETTINGS
        if ($null -eq $old) { Remove-ItemProperty $k -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
        else { Set-ItemProperty $k -Name SystemRestorePointCreationFrequency -Value $old -Type DWord }
        Write-Log 'Punto de restauración creado.' 'OK'
        return $true
    }
    catch { Write-Log "No se pudo crear el punto de restauración: $($_.Exception.Message)" 'ERROR'; return $false }
}

function Invoke-Tweaks($List, [string]$Mode) {
    $reboot = $false; $ok = 0; $fail = 0
    foreach ($t in $List) {
        try {
            if ($Mode -eq 'Apply') {
                if ((Test-Tweak $t) -eq $true) { Write-Log "Ya aplicado: $($t.Name)"; continue }
                Write-Log "Aplicando: $($t.Name)"
                Invoke-ApplyTweak $t
            }
            else {
                Write-Log "Revirtiendo: $($t.Name)"
                Invoke-RevertTweak $t
            }
            $ok++; if ($t.Reboot) { $reboot = $true }
        }
        catch { $fail++; Write-Log "$($t.Name): $($_.Exception.Message)" 'ERROR' }
    }
    Write-Log ("Terminado: {0} correctos, {1} con error." -f $ok, $fail) 'OK'
    return $reboot
}

# ============================================================ diff: qué toca exactamente cada ajuste
$StartNames = @{ 2 = 'auto'; 3 = 'manual'; 4 = 'disabled' }
function Format-RegState($s) { if (-not $s -or -not $s.Exists) { '(no existe)' } else { "$($s.Value) ($($s.Kind))" } }
function Format-SvcState($s) { if (-not $s) { '(no existe)' } elseif ($s.Start -eq 2 -and $s.Delayed) { 'auto (retrasado)' } else { $StartNames[[int]$s.Start] } }
function Get-ShortKey([string]$p) {
    $p -replace '^HKLM:\\SOFTWARE\\Policies\\Microsoft\\', 'HKLM\Policies\' -replace '^HKCU:\\Software\\Policies\\Microsoft\\', 'HKCU\Policies\' `
       -replace '^HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\', 'HKLM\...\CurrentVersion\' -replace '^HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\', 'HKCU\...\CurrentVersion\' `
       -replace '^HKLM:\\SYSTEM\\CurrentControlSet\\', 'HKLM\SYSTEM\CCS\' -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU'
}
function New-DiffLine([string]$Kind, [string]$Target, [string]$Before, [string]$After) {
    [pscustomobject]@{ Kind = $Kind; Target = $Target; Before = $Before; After = $After; Same = ($Before -eq $After) }
}
# $Revert: $true = enseñar lo que pasará al revertir (desde la copia o los valores de Windows)
function Get-TweakDiff($t, [bool]$Revert) {
    $bk = Get-Backup $t.Id
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($r in @($t.Reg)) {
        if (-not $r) { continue }
        $now = Format-RegState (Get-RegState $r)
        if ($Revert) {
            $orig = if ($bk) { @($bk.Reg) | Where-Object { $_.Path -eq $r.Path -and $_.Name -eq $r.Name } | Select-Object -First 1 }
            $then = if ($orig) { Format-RegState $orig } elseif ($null -ne $r.Default) { "$($r.Default) ($($r.Kind))" } else { '(no existe)' }
        }
        else { $then = "$($r.Value) ($($r.Kind))" }
        $out.Add((New-DiffLine 'reg' "$(Get-ShortKey $r.Path)\$($r.Name)" $now $then))
    }
    foreach ($s in @($t.Svc)) {
        if (-not $s) { continue }
        $cur = Get-SvcState $s.Name
        if (-not $cur) { continue }   # el servicio no existe en esta versión de Windows
        $now = Format-SvcState $cur
        if ($Revert) {
            $orig = if ($bk) { @($bk.Svc) | Where-Object { $_.Name -eq $s.Name } | Select-Object -First 1 }
            $then = if ($orig) { Format-SvcState $orig } else { @{ Auto = 'auto'; Delayed = 'auto (retrasado)'; Manual = 'manual'; Disabled = 'disabled' }[$s.Default] }
        }
        else { $then = $StartNames[(Get-StartCode $s.Start)] }
        $out.Add((New-DiffLine 'svc' "servicio $($s.Name)" $now $then))
    }
    foreach ($x in @($t.Task)) {
        if (-not $x) { continue }
        $cur = Get-TaskState $x
        if (-not $cur) { continue }
        $now = if ($cur.Enabled) { 'activa' } else { 'desactivada' }
        $then = if ($Revert) { if ($bk) { $o = @($bk.Task) | Where-Object { $_.Task -eq $x } | Select-Object -First 1; if ($o -and -not $o.Enabled) { 'desactivada' } else { 'activa' } } else { 'activa' } } else { 'desactivada' }
        $out.Add((New-DiffLine 'task' "tarea $($x -replace '^\\Microsoft\\Windows\\', '')" $now $then))
    }
    if ($t.Custom) {
        $fn = $CustomDiff[$t.Id]
        if (-not $fn -and $t.Custom.Diff) { $fn = $t.Custom.Diff }
        if ($fn) { foreach ($l in @(& $fn $bk $Revert)) { if ($l) { $out.Add($l) } } }
        else { $out.Add((New-DiffLine 'custom' 'acción a medida' '' 'ver la descripción')) }
    }
    $arr = New-Object object[] $out.Count   # array normal: @() sobre List[object] falla en PowerShell 5.1
    for ($i = 0; $i -lt $out.Count; $i++) { $arr[$i] = $out[$i] }
    , $arr
}
# diffs de los ajustes a medida
$OverlayNames = @{ 'ded574b5-45a0-4f42-8737-46345c09c238' = 'máximo rendimiento'; '00000000-0000-0000-0000-000000000000' = 'equilibrado'; '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'máxima eficiencia' }
function Get-AppDiff([string[]]$List, [bool]$Revert) {
    $present = Get-DebloatPresent $List
    if (-not $present) { return , (New-DiffLine 'app' "$($List.Count) paquetes de la lista" 'ninguno instalado' 'ninguno instalado') }
    foreach ($n in $present) { New-DiffLine 'app' "appx $n" 'instalada' $(if ($Revert) { 'instalada (sin cambios)' } else { 'eliminada' }) }
}
$CustomDiff = @{
    'perf-powermode' = { param($bk, $rev) $g = Get-OverlayGuid; $n = $OverlayNames[$g]; if (-not $n) { $n = $g }
                         New-DiffLine 'power' 'modo de energía (powrprof overlay)' $n $(if ($rev) { if ($bk -and $bk.Custom.Prev) { $OverlayNames[$bk.Custom.Prev] } else { 'equilibrado' } } else { 'máximo rendimiento' }) }
    'perf-ultimate'  = { param($bk, $rev) $now = if ((powercfg /getactivescheme) -match '\((.+)\)') { $Matches[1] } else { '?' }
                         New-DiffLine 'power' 'plan de energía activo' $now $(if ($rev) { 'el plan anterior' } else { 'Rendimiento máximo (copia de e9a42b02...)' }) }
    'ui-context'     = { param($bk, $rev) $e = Test-Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
                         New-DiffLine 'reg' 'HKCU\Software\Classes\CLSID\{86ca1aa0...}\InprocServer32' $(if ($e) { "'' (REG_SZ)" } else { '(no existe)' }) $(if ($rev) { '(no existe)' } else { "'' (REG_SZ)" }) }
    'app-debloat'    = { param($bk, $rev) Get-AppDiff $DebloatApps $rev }
    'app-phonelink'  = { param($bk, $rev) Get-AppDiff $PhoneApps $rev }
    'app-xbox'       = { param($bk, $rev) Get-AppDiff $XboxApps $rev }
    'app-onedrive'   = { param($bk, $rev) $e = (Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe")
                         New-DiffLine 'app' 'winget Microsoft.OneDrive' $(if ($e) { 'instalado' } else { 'no instalado' }) $(if ($rev) { $(if ($e) { 'instalado' } else { 'no instalado' }) } else { 'desinstalado' }) }
    'app-edge'       = { param($bk, $rev) $e = Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
                         New-DiffLine 'app' 'msedge.exe' $(if ($e) { 'instalado' } else { 'no instalado' }) $(if ($rev) { $(if ($e) { 'instalado' } else { 'no instalado' }) } else { 'desinstalado' })
                         New-DiffLine 'reg' 'HKLM\SOFTWARE\Microsoft\EdgeUpdate\DoNotUpdateToEdgeWithChromium' (Format-RegState (Get-RegState @{ Path = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'; Name = 'DoNotUpdateToEdgeWithChromium' })) $(if ($rev) { '(no existe)' } else { '1 (DWord)' }) }
    'app-capabilities' = { param($bk, $rev) foreach ($oc in $OldCapabilities) { $e = Test-Path $oc.File
                         New-DiffLine 'cap' "capacidad $($oc.Cap.TrimEnd('*'))" $(if ($e) { 'instalada' } else { 'no instalada' }) $(if ($rev -or -not $e) { $(if ($e) { 'instalada' } else { 'no instalada' }) } else { 'eliminada' }) } }
    'lat-memcomp'    = { param($bk, $rev) $on = try { [bool](Get-MMAgent -ErrorAction Stop).MemoryCompression } catch { $null }
                         New-DiffLine 'mm' 'MMAgent MemoryCompression' $(if ($null -eq $on) { '?' } elseif ($on) { 'activada' } else { 'desactivada' }) $(if ($rev) { 'activada' } else { 'desactivada' }) }
    'perf-hibernate' = { param($bk, $rev) $v = try { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction Stop).HibernateEnabled } catch { '?' }
                         New-DiffLine 'power' 'powercfg /hibernate (HibernateEnabled)' "$v" $(if ($rev) { '1' } else { '0' }) }
}

# ============================================================ modos sin interfaz
if ($Status) {
    $Tweaks | ForEach-Object {
        $s = try { Test-Tweak $_ } catch { 'error' }
        $row = [ordered]@{}
        $row[(T 'Categoría')] = T $_.Cat; $row[(T 'Ajuste')] = T $_.Name; $row[(T 'Riesgo')] = T $_.Risk
        $row['Presets'] = ($_.Presets -join ','); $row[(T 'Aplicado')] = T $(if ($s -eq $true) { 'sí' } elseif ($s -eq $false) { 'no' } else { [string]$s })
        [pscustomobject]$row
    } | Format-Table -AutoSize
    return
}
if ($NoGui) {
    if (-not $script:IsAdmin) { Write-Log 'Hay que ejecutarlo como administrador.' 'ERROR'; exit 1 }
    if ($Config) {
        $ids = Import-Profile $Config
        $list = @($Tweaks | Where-Object { $ids -contains $_.Id })
        Write-Log "Perfil ${Config}: $($list.Count) ajustes."
    }
    elseif ($Preset) {
        $code = if ($Preset -eq 'Recomendado') { 'R' } else { 'A' }   # 'Competitivo' se acepta como el antiguo nombre de Avanzado
        $list = @($Tweaks | Where-Object { $_.Presets -contains $code })
    }
    else { Write-Log 'Indica -Preset Recomendado|Avanzado o -Config perfil.json.' 'ERROR'; exit 1 }
    [void](New-RestorePoint)
    $r = Invoke-Tweaks $list 'Apply'
    if ($r) { Write-Log 'Reinicia el equipo para completar los cambios.' 'WARN' }
    exit 0
}

# ============================================================ interfaz
# Hallmark v2 · app screen · theme: Furrow (dealt 3/3, seed herramienta-cnica-escritorio-para-90c4·4a1a5fcc·2026-11-22·r0), v2 compacta
# Material: papel manila, tinta casi negra en filetes, cifras en mono, un naranja de señal (siempre relleno con tinta encima)
# y un verde para lo aplicado. Cada categoría lleva un tono propio solo en su icono; las marcas, su color real.
# Firma: la hoja de cambios (libreta cuadriculada con cabecera de tinta) bajo el diff del ajuste seleccionado.
# Color: cada categoría y apartado tiene su tono, en el icono, en su pozo teñido y en el filete de su grupo.
# Crítica: con más color el riesgo es el confeti; nunca en textos largos ni en fondos grandes.
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing
if (-not ('GP.Dwm' -as [type])) {
    Add-Type -Namespace GP -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);'
}

$Themes = @{
    Furrow      = @{ Dark = $false; Paper = '#f5f1ea'; Paper2 = '#fffdfa'; Paper3 = '#e9e4d9'; Side = '#eee9df'; Ink = '#14110f'; Ink2 = '#2c2825'; Muted = '#5e5751'
                     Rule = '#dbd7ce'; RuleStrong = '#bcb7ad'; Accent = '#fc6b33'; AccentInk = '#14110f'; AccentSoft = '#fed8c4'; AccentEdge = '#c94c18'
                     Green = '#0b5d2a'; GreenSoft = '#cfeacf'; Amber = '#6e4600'; AmberSoft = '#f7e3b8'; Red = '#9c2123'; RedSoft = '#fdd9d5'
                     Grid = '#e2ddd4'; Track = '#cfcac0'; KeyLight = '#ccffffff'; Wash = '#fed8c4'
                     'Cat-Privacidad' = '#1f5fa8'; 'Cat-Servicios' = '#0f8a74'; 'Cat-Rendimiento' = '#d9480f'; 'Cat-Latencia' = '#b06d00'
                     'Cat-Juegos' = '#23893a'; 'Cat-Actualizaciones' = '#2a5bd7'; 'Cat-Interfaz' = '#c2255c'; 'Cat-Apps' = '#a0522d'; 'Cat-Tools' = '#2c2825' }
    FurrowNoche = @{ Dark = $true; Paper = '#110f0b'; Paper2 = '#1a1813'; Paper3 = '#23201b'; Side = '#0c0a06'; Ink = '#eeebe5'; Ink2 = '#d0cdc8'; Muted = '#a8a49c'
                     Rule = '#2e2b26'; RuleStrong = '#45423b'; Accent = '#ff7643'; AccentInk = '#14110f'; AccentSoft = '#4c2817'; AccentEdge = '#d35d31'
                     Green = '#86d897'; GreenSoft = '#1a3520'; Amber = '#efc173'; AmberSoft = '#3e2d10'; Red = '#f69a92'; RedSoft = '#4a2321'
                     Grid = '#24211c'; Track = '#3b3831'; KeyLight = '#14ffffff'; Wash = '#4c2817'
                     'Cat-Privacidad' = '#6ea8ff'; 'Cat-Servicios' = '#3fd6b8'; 'Cat-Rendimiento' = '#ff8a4c'; 'Cat-Latencia' = '#ffc53d'
                     'Cat-Juegos' = '#5fd47a'; 'Cat-Actualizaciones' = '#7c9cff'; 'Cat-Interfaz' = '#ff6fae'; 'Cat-Apps' = '#f0a070'; 'Cat-Tools' = '#d0cdc8' }
}
# color real de cada marca (Simple Icons); en el tema oscuro, las marcas negras pasan a la tinta clara
$BrandColors = @{
    'brand-steam' = '#000000'; 'brand-epicgames' = '#313131'; 'brand-gogdotcom' = '#86328a'; 'brand-ea' = '#000000'; 'brand-ubisoft' = '#000000'
    'brand-battledotnet' = '#148eff'; 'brand-discord' = '#5865f2'; 'brand-obsstudio' = '#302e31'; 'brand-msi' = '#ff0000'; 'brand-7zip' = '#000000'
    'brand-vlcmediaplayer' = '#ff8800'; 'brand-firefoxbrowser' = '#ff7139'; 'brand-brave' = '#fb542b'; 'brand-dotnet' = '#512bd4'
    'brand-cloudflare' = '#f38020'; 'brand-google' = '#4285f4'; 'brand-docker' = '#2496ed'; 'brand-spotify' = '#1db954'
    'brand-adobecreativecloud' = '#da1f26'; 'brand-amd' = '#ed1c24'; 'brand-nvidia' = '#76b900'; 'brand-steamdeck' = '#1a9fff'
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OptiEleven" Width="1360" Height="860" MinWidth="1100" MinHeight="660"
        WindowStartupLocation="CenterScreen" UseLayoutRounding="True" SnapsToDevicePixels="True"
        Background="{DynamicResource Paper}" Foreground="{DynamicResource Ink}"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14">
  <Window.Resources>
    <SolidColorBrush x:Key="Paper" Color="#f5f1ea"/>
    <FontFamily x:Key="Display">Segoe UI Variable Display, Segoe UI</FontFamily>
    <FontFamily x:Key="Mono">Cascadia Mono, Consolas</FontFamily>
    <FontFamily x:Key="Icons">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>

    <!-- botón secundario: relleno suave, brillo arriba, se ilumina el borde al pasar y se encoge un poco al pulsar -->
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource Paper3}"/>
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Rule}"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="MinHeight" Value="36"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid x:Name="root" RenderTransformOrigin="0.5,0.5">
              <Border x:Name="ring" CornerRadius="12" Margin="-3" BorderThickness="2" BorderBrush="{DynamicResource Accent}" Opacity="0"/>
              <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="9"/>
              <Border x:Name="sheen" CornerRadius="9" Margin="1" IsHitTestVisible="False">
                <Border.Background>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#1AFFFFFF" Offset="0"/><GradientStop Color="#00FFFFFF" Offset="0.6"/>
                  </LinearGradientBrush>
                </Border.Background>
              </Border>
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Paper2}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="root" Property="RenderTransform"><Setter.Value><ScaleTransform ScaleX="0.97" ScaleY="0.97"/></Setter.Value></Setter>
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Rule}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ring" Property="Opacity" Value="1"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="root" Property="Opacity" Value="0.45"/>
                <Setter TargetName="sheen" Property="Visibility" Value="Hidden"/>
                <Setter Property="Cursor" Value="No"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- botón principal: naranja con brillo arriba y sombra abajo; al pasar, un halo naranja; desactivado, gris limpio -->
    <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="{DynamicResource Accent}"/>
      <Setter Property="Foreground" Value="{DynamicResource AccentInk}"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid x:Name="root" RenderTransformOrigin="0.5,0.5">
              <Border x:Name="ring" CornerRadius="12" Margin="-3" BorderThickness="2" BorderBrush="{DynamicResource Ink}" Opacity="0"/>
              <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="9"/>
              <Border x:Name="sheen" CornerRadius="9" IsHitTestVisible="False">
                <Border.Background>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#40FFFFFF" Offset="0"/><GradientStop Color="#08FFFFFF" Offset="0.5"/>
                    <GradientStop Color="#00000000" Offset="0.55"/><GradientStop Color="#26000000" Offset="1"/>
                  </LinearGradientBrush>
                </Border.Background>
              </Border>
              <Border x:Name="edge" CornerRadius="9" BorderThickness="1" IsHitTestVisible="False">
                <Border.BorderBrush>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                    <GradientStop Color="#66FFFFFF" Offset="0"/><GradientStop Color="#33000000" Offset="1"/>
                  </LinearGradientBrush>
                </Border.BorderBrush>
              </Border>
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Effect"><Setter.Value><DropShadowEffect Color="#FF7643" BlurRadius="20" ShadowDepth="0" Opacity="0.6"/></Setter.Value></Setter>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="root" Property="RenderTransform"><Setter.Value><ScaleTransform ScaleX="0.97" ScaleY="0.97"/></Setter.Value></Setter>
                <Setter TargetName="sheen" Property="Opacity" Value="0.4"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ring" Property="Opacity" Value="1"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Paper3}"/>
                <Setter TargetName="b" Property="Effect" Value="{x:Null}"/>
                <Setter TargetName="sheen" Property="Visibility" Value="Hidden"/>
                <Setter TargetName="edge" Property="BorderBrush" Value="{DynamicResource Rule}"/>
                <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
                <Setter Property="Cursor" Value="No"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- interruptor: relleno naranja con tinta encima -->
    <Style x:Key="Switch" TargetType="ToggleButton">
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="22"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid x:Name="root" Background="Transparent">
              <Border x:Name="track" CornerRadius="11" Background="{DynamicResource Track}" BorderBrush="{DynamicResource RuleStrong}" BorderThickness="1"/>
              <Ellipse x:Name="thumb" Width="16" Height="16" HorizontalAlignment="Left" Margin="3,0,0,0" Fill="{DynamicResource Paper2}">
                <Ellipse.RenderTransform><TranslateTransform x:Name="tt" X="0"/></Ellipse.RenderTransform>
              </Ellipse>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="{DynamicResource Accent}"/>
                <Setter TargetName="track" Property="BorderBrush" Value="{DynamicResource AccentEdge}"/>
                <Setter TargetName="thumb" Property="Fill" Value="{DynamicResource AccentInk}"/>
                <Trigger.EnterActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="tt" Storyboard.TargetProperty="X" To="18" Duration="0:0:0.14"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                </Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="tt" Storyboard.TargetProperty="X" To="0" Duration="0:0:0.14"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                </Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="track" Property="BorderBrush" Value="{DynamicResource Ink}"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="track" Property="BorderBrush" Value="{DynamicResource AccentEdge}"/><Setter TargetName="track" Property="BorderThickness" Value="2"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="root" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- pestaña: la seleccionada es relleno naranja con tinta -->
    <Style x:Key="TabToggle" TargetType="ToggleButton">
      <Setter Property="Foreground" Value="{DynamicResource Ink2}"/>
      <Setter Property="FontWeight" Value="Medium"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,1,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="b" Background="Transparent" CornerRadius="6" Padding="8,0" MinHeight="30" BorderThickness="2" BorderBrush="Transparent">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Paper3}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Accent}"/>
                <Setter Property="Foreground" Value="{DynamicResource AccentInk}"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource AccentEdge}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- filas con filete -->
    <Style x:Key="RuleRow" TargetType="Border">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Rule}"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
      <Setter Property="Padding" Value="0,10,10,10"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource Paper2}"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Tile" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource Paper2}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Rule}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="16,14"/>
    </Style>
    <Style x:Key="Row" TargetType="Border" BasedOn="{StaticResource Tile}">
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="BorderBrush" Value="{DynamicResource Ink}"/></Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="ListBoxItem">
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,0,1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="b" Background="Transparent" CornerRadius="6" Padding="10,6">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Paper3}"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Accent}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{DynamicResource Ink}"/>
      <Setter Property="Foreground" Value="{DynamicResource Paper2}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,6"/>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb><Thumb.Template><ControlTemplate TargetType="Thumb">
                  <Border CornerRadius="4" Background="{DynamicResource RuleStrong}" Margin="1,0"/>
                </ControlTemplate></Thumb.Template></Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="228"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>

    <!-- barra lateral -->
    <Border Background="{DynamicResource Side}" BorderBrush="{DynamicResource Rule}" BorderThickness="0,0,1,0">
      <DockPanel Margin="12,18,12,12">
        <Grid DockPanel.Dock="Top" Margin="10,0,0,16">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal">
            <Border Width="30" Height="30" CornerRadius="7" Background="{DynamicResource Ink}">
              <ContentControl x:Name="BrandMark" Focusable="False" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock Text="OptiEleven" FontFamily="{StaticResource Display}" FontSize="17" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <Button x:Name="BtnLang" Grid.Column="1" Style="{StaticResource Btn}" Padding="8,0" MinHeight="30" ToolTip="Idioma" AutomationProperties.Name="Idioma">
            <StackPanel Orientation="Horizontal">
              <ContentControl x:Name="LangIcon" Focusable="False" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBlock x:Name="LangCode" FontFamily="{StaticResource Mono}" FontSize="12.5" FontWeight="SemiBold" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
        </Grid>
        <Grid DockPanel.Dock="Bottom" Margin="0,10,0,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <Border x:Name="AdminChip" CornerRadius="6" Padding="10,0" Margin="0,0,8,0" Background="{DynamicResource Paper3}" MinHeight="36">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <ContentControl x:Name="AdminIcon" Focusable="False" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock x:Name="AdminTitle" FontWeight="Medium" FontSize="13" VerticalAlignment="Center"/>
            </StackPanel>
          </Border>
          <Button x:Name="BtnTheme" Grid.Column="1" Style="{StaticResource Btn}" Padding="10,0" AutomationProperties.Name="Cambiar tema">
            <ContentControl x:Name="ThemeIcon" Focusable="False"/>
          </Button>
        </Grid>
        <Border x:Name="ProRow" DockPanel.Dock="Bottom" CornerRadius="8" Padding="10,8" Margin="0,10,0,0" Background="{DynamicResource Paper3}" Cursor="Hand"
                ToolTip="Muestra las claves del registro, servicios y tareas que toca cada ajuste, y el registro de actividad.">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <ContentControl x:Name="ProIcon" Focusable="False" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <StackPanel Grid.Column="1" VerticalAlignment="Center">
              <TextBlock Text="Vista Pro" FontWeight="SemiBold" FontSize="13"/>
              <TextBlock Text="Detalles técnicos" FontSize="11.5" Foreground="{DynamicResource Muted}"/>
            </StackPanel>
            <ToggleButton x:Name="ProSwitch" Grid.Column="2" Style="{StaticResource Switch}" VerticalAlignment="Center" AutomationProperties.Name="Vista Pro"/>
          </Grid>
        </Border>
        <ListBox x:Name="Nav" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
      </DockPanel>
    </Border>

    <!-- contenido -->
    <Grid Grid.Column="1">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Grid Margin="30,22,26,12">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="PageTitle" FontFamily="{StaticResource Display}" FontSize="28" FontWeight="SemiBold"/>
          <TextBlock x:Name="PageDesc" Foreground="{DynamicResource Muted}" FontSize="14.5" Margin="0,3,0,0" TextWrapping="Wrap" MaxWidth="560" HorizontalAlignment="Left"/>
        </StackPanel>
        <StackPanel x:Name="PresetBar" Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Bottom" Margin="20,0,0,0">
          <TextBlock Text="Preset" Foreground="{DynamicResource Muted}" FontSize="13" VerticalAlignment="Center" Margin="0,0,10,0"/>
          <Button x:Name="BtnRec" Style="{StaticResource BtnPrimary}" Margin="0,0,10,0" MinHeight="46" Padding="20,0" FontSize="15" FontWeight="Bold"
                  ToolTip="Seguro para casi todos los equipos. Quita casi todo lo que no sirve."/>
          <Button x:Name="BtnComp" Style="{StaticResource BtnPrimary}" MinHeight="46" Padding="20,0" FontSize="15" FontWeight="Bold"
                  ToolTip="Más agresivo: puede quitar funciones que uses. Lee cada ajuste antes de aplicar."/>
        </StackPanel>
      </Grid>
      <ScrollViewer x:Name="TabScroll" Grid.Row="1" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Disabled" Margin="30,0,26,10">
        <StackPanel x:Name="Tabs" Orientation="Horizontal"/>
      </ScrollViewer>
      <ScrollViewer x:Name="TweakPage" Grid.Row="2" VerticalScrollBarVisibility="Visible" Padding="30,0,16,20">
        <StackPanel x:Name="TweakList"/>
      </ScrollViewer>
      <ScrollViewer x:Name="ToolsPage" Grid.Row="2" VerticalScrollBarVisibility="Visible" Padding="30,0,16,20" Visibility="Collapsed">
        <StackPanel x:Name="ToolGrid"/>
      </ScrollViewer>
      <Border x:Name="LogPage" Grid.Row="2" Visibility="Collapsed" Margin="30,0,26,20" Background="{DynamicResource Paper2}"
              BorderBrush="{DynamicResource Rule}" BorderThickness="0,1,0,0">
        <TextBox x:Name="Log" IsReadOnly="True" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource Ink2}"
                 FontFamily="{StaticResource Mono}" FontSize="12.5" Padding="0,12" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
      </Border>
      <ScrollViewer x:Name="ModulePage" Grid.Row="2" VerticalScrollBarVisibility="Visible" Padding="30,0,16,20" Visibility="Collapsed">
        <ContentControl x:Name="ModuleHost" Focusable="False"/>
      </ScrollViewer>
    </Grid>

    <!-- carril: detalle con diff + hoja de cambios -->
    <Border x:Name="Rail" Grid.Column="2" Width="322" Background="{DynamicResource Paper}" BorderBrush="{DynamicResource Rule}" BorderThickness="1,0,0,0">
      <DockPanel>
        <Border x:Name="Ledger" DockPanel.Dock="Bottom" Margin="16,8,16,16" CornerRadius="12" BorderBrush="{DynamicResource Ink}" BorderThickness="1" Background="{DynamicResource Paper2}">
          <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="8" Direction="270" Opacity="0.2" Color="#14110f"/></Border.Effect>
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Border Background="{DynamicResource Ink}" CornerRadius="11,11,0,0" Padding="14,9">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Hoja de cambios" FontWeight="SemiBold" Foreground="{DynamicResource Paper2}"/>
                  <TextBlock x:Name="LedgerSub" FontSize="12.5" Foreground="{DynamicResource Track}" Margin="0,1,0,0"/>
                </StackPanel>
                <TextBlock x:Name="LedgerCount" Grid.Column="1" Text="0" FontFamily="{StaticResource Mono}" FontSize="28" Foreground="{DynamicResource Paper2}" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <Grid x:Name="LedgerStats" Grid.Row="1">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Border BorderBrush="{DynamicResource Ink}" BorderThickness="0,0,1,1" Padding="10,6">
                <StackPanel><TextBlock Text="Aplicar" FontSize="12" Foreground="{DynamicResource Muted}"/><TextBlock x:Name="LedgerApply" Text="0" FontFamily="{StaticResource Mono}" FontSize="16"/></StackPanel>
              </Border>
              <Border Grid.Column="1" BorderBrush="{DynamicResource Ink}" BorderThickness="0,0,1,1" Padding="10,6">
                <StackPanel><TextBlock Text="Revertir" FontSize="12" Foreground="{DynamicResource Muted}"/><TextBlock x:Name="LedgerRevert" Text="0" FontFamily="{StaticResource Mono}" FontSize="16"/></StackPanel>
              </Border>
              <Border Grid.Column="2" BorderBrush="{DynamicResource Ink}" BorderThickness="0,0,0,1" Padding="10,6">
                <StackPanel><TextBlock Text="Reinicio" FontSize="12" Foreground="{DynamicResource Muted}"/><TextBlock x:Name="LedgerReboot" Text="no" FontSize="14" FontWeight="Medium" Margin="0,1,0,0"/></StackPanel>
              </Border>
            </Grid>
            <Border x:Name="LedgerGrid" Grid.Row="2" MaxHeight="150">
              <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="LedgerList" Margin="12,8,12,6"/></ScrollViewer>
            </Border>
            <Grid Grid.Row="3" Margin="12,4,12,12">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Button x:Name="BtnDiscard" Style="{StaticResource Btn}" Content="Descartar" MinHeight="40" Margin="0,0,8,0"/>
              <Button x:Name="BtnApply" Grid.Column="1" Style="{StaticResource BtnPrimary}" Content="Aplicar cambios" MinHeight="40"/>
            </Grid>
          </Grid>
        </Border>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Focusable="False">
          <StackPanel x:Name="Detail" Margin="20,22,20,8"/>
        </ScrollViewer>
      </DockPanel>
    </Border>

    <!-- barra de estado -->
    <Border Grid.Row="1" Grid.ColumnSpan="3" Background="{DynamicResource Side}" BorderBrush="{DynamicResource Rule}" BorderThickness="0,1,0,0" Padding="16,0">
      <Grid MinHeight="32">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel x:Name="StatList" Orientation="Horizontal" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="Cola" Foreground="{DynamicResource Muted}" FontSize="12.5" Margin="0,0,6,0" VerticalAlignment="Center"/>
          <Border x:Name="QueuePill" CornerRadius="6" Padding="8,1" Background="{DynamicResource Paper3}">
            <TextBlock x:Name="QueueText" Text="0" FontFamily="{StaticResource Mono}" FontSize="12.5" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$Pages = [ordered]@{
    'all'             = @{ Label = 'Ajustes'; Icon = 'sliders-horizontal'; Tab = 'Todos'; Title = 'Ajustes'; Desc = 'Elige un ajuste para ver qué cambia. Los cambios se apuntan en la hoja y se aplican juntos.' }
    'Privacidad'      = @{ Tab = 'Privacidad';  Icon = 'lock-simple';      Title = 'Privacidad';      Desc = 'Telemetría, publicidad, IA y lo que Windows envía sin pedirlo.' }
    'Servicios'       = @{ Tab = 'Servicios';   Icon = 'gear-six';         Title = 'Servicios';       Desc = 'Servicios que arrancan con Windows y no hacen falta para jugar.' }
    'Rendimiento'     = @{ Tab = 'Rendimiento'; Icon = 'gauge';            Title = 'Rendimiento';     Desc = 'Energía, prioridades y lo que compite con el juego por la CPU.' }
    'Latencia'        = @{ Tab = 'Latencia';    Icon = 'timer';            Title = 'Latencia';        Desc = 'Energía de USB y PCIe, núcleos, red e interrupciones. Pruébalos de uno en uno.' }
    'Juegos'          = @{ Tab = 'Juegos';      Icon = 'game-controller';  Title = 'Juegos';          Desc = 'GPU, ratón, teclado y grabación.' }
    'Actualizaciones' = @{ Tab = 'Updates';     Icon = 'arrows-clockwise'; Title = 'Windows Update';  Desc = 'Que las actualizaciones lleguen cuando tú quieras, sin reinicios ni drivers cambiados.' }
    'Interfaz'        = @{ Tab = 'Interfaz';    Icon = 'magic-wand';       Title = 'Interfaz';        Desc = 'Escritorio y barra de tareas. No cambian los FPS.' }
    'Apps'            = @{ Tab = 'Apps';        Icon = 'app-window';       Title = 'Apps';            Desc = 'Apps de serie, patrocinadas y componentes antiguos.' }
    'h-jugar'         = @{ Header = 'Para jugar' }
    'm-boost'         = @{ Label = 'Game Booster';  Icon = 'rocket-launch';   Module = 'New-BoosterPage';  Title = 'Game Booster';        Desc = 'Antes de jugar, cierra lo que sobra y pausa servicios. Al terminar, todo vuelve a como estaba.' }
    'm-games'         = @{ Label = 'Mis juegos';    Icon = 'joystick';        Module = 'New-GamesPage';    Title = 'Mis juegos';          Desc = 'Tus juegos de Steam, Epic y GOG, con ajustes de Windows para cada uno.' }
    'h-tools'         = @{ Header = 'Herramientas' }
    'm-apps'          = @{ Label = 'Instalar apps'; Icon = 'download-simple'; Module = 'New-AppsPage';     Title = 'Instalar apps';       Desc = 'Launchers, Discord, monitorización y librerías para juegos, con winget.' }
    'm-startup'       = @{ Label = 'Inicio';        Icon = 'sign-in';         Module = 'New-StartupPage';  Title = 'Programas de inicio'; Desc = 'Lo que arranca con Windows y se queda en segundo plano mientras juegas.' }
    'm-clean'         = @{ Label = 'Limpieza';      Icon = 'broom';           Module = 'New-CleanerPage';  Title = 'Limpieza';            Desc = 'Temporales, cachés y restos de actualizaciones. Primero ves cuánto ocupa cada cosa.' }
    'm-net'           = @{ Label = 'Red';           Icon = 'wifi-high';       Module = 'New-NetworkPage';  Title = 'Red y DNS';           Desc = 'Tu conexión, la latencia al router y a los DNS públicos, y con cuál quedarte.' }
    'm-repair'        = @{ Label = 'Reparar';       Icon = 'wrench';          Module = 'New-RepairPage';   Title = 'Reparar Windows';     Desc = 'Las reparaciones de siempre, cada una en su ventana para que veas lo que hace.' }
    'm-hw'            = @{ Label = 'Equipo';        Icon = 'laptop';          Module = 'New-HardwarePage'; Title = 'Tu equipo';           Desc = 'Procesador, gráfica, memoria, discos y el estado de Windows que afecta a los juegos.' }
    'tools'           = @{ Label = 'Sistema';       Icon = 'floppy-disk';     Title = 'Sistema';  Desc = 'Copias de seguridad, perfiles para otros equipos y el Explorador.' }
    'log'             = @{ Label = 'Actividad';     Icon = 'scroll';          Title = 'Actividad'; Desc = 'Todo lo que ha hecho el panel en esta sesión.' }
}

$ToolDefs = @(
    @{ Icon = 'clock-counter-clockwise'; Name = 'Punto de restauración'; Desc = 'Una copia del sistema a la que volver si algo sale mal.'; Button = 'Crear punto'; Admin = $true
       Action = { [void](New-RestorePoint) } }
    @{ Icon = 'export'; Name = 'Exportar perfil'; Desc = 'Los ajustes que tienes activados, en un .json para otro PC o una instalación nueva.'; Button = 'Exportar'; Admin = $false
       Action = {
           $dlg = New-Object Microsoft.Win32.SaveFileDialog
           $dlg.FileName = 'optieleven-profile.json'; $dlg.Filter = T 'Perfil de OptiEleven (*.json)|*.json'
           if ($dlg.ShowDialog($window)) {
               $ids = @($script:Rows.Values | Where-Object { $_.Switch.IsChecked } | ForEach-Object { $_.Tweak.Id })
               Export-Profile $dlg.FileName $ids
               Write-Log "Perfil exportado con $($ids.Count) ajustes: $($dlg.FileName)" 'OK'
           } } }
    @{ Icon = 'tray-arrow-down'; Name = 'Importar perfil'; Desc = 'Deja los interruptores como en el perfil. Revisa la hoja de cambios y aplica.'; Button = 'Importar'; Admin = $false
       Action = {
           $dlg = New-Object Microsoft.Win32.OpenFileDialog
           $dlg.Filter = T 'Perfil de OptiEleven (*.json)|*.json'
           if ($dlg.ShowDialog($window)) {
               $ids = Import-Profile $dlg.FileName
               foreach ($row in $script:Rows.Values) { if ($null -ne $row.Applied) { $row.Switch.IsChecked = $ids -contains $row.Tweak.Id } }
               Update-Pending
               Write-Log "Perfil cargado ($($ids.Count) ajustes). Revisa la hoja de cambios y pulsa Aplicar." 'OK'
               Select-NavKey 'all'
           } } }
    @{ Icon = 'folder-open'; Name = 'Explorador de Windows'; Desc = 'Reinicia la barra de tareas y el escritorio para ver los cambios de interfaz.'; Button = 'Reiniciar'; Admin = $false
       Action = {
           Write-Log 'Reiniciando el Explorador...'
           Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
           # Windows lo vuelve a abrir solo; arrancarlo desde aquí (elevado) daría un escritorio con permisos de administrador
           for ($i = 0; $i -lt 40 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 250; Update-Ui }
           if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { runas /trustlevel:0x20000 explorer.exe } } }
    @{ Icon = 'archive'; Name = 'Copias de seguridad'; Desc = 'La carpeta con el estado original de cada ajuste y el registro del panel.'; Button = 'Abrir carpeta'; Admin = $false
       Action = { Start-Process explorer.exe $script:Root } }
)

try {
    # textos fijos de la ventana: se traducen en el XAML antes de cargarlo (los x:Name no se tocan)
    foreach ($node in $xaml.SelectNodes('//*')) {
        foreach ($a in @($node.Attributes)) {
            if ($a.LocalName -in 'Text', 'Content', 'ToolTip', 'Title', 'Header', 'AutomationProperties.Name' -and $a.NamespaceURI -eq '' -and $a.Value -and -not $a.Value.StartsWith('{')) { $a.Value = T $a.Value }
        }
    }
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    $wa = [System.Windows.SystemParameters]::WorkArea
    $window.Height = [math]::Min($window.Height, $wa.Height - 24)
    $window.Width  = [math]::Min($window.Width, $wa.Width - 24)
    $ui = @{}
    foreach ($n in 'Nav', 'BrandMark', 'BtnLang', 'LangIcon', 'LangCode', 'ProRow', 'ProIcon', 'ProSwitch', 'LedgerStats','AdminChip', 'AdminIcon', 'AdminTitle', 'BtnTheme', 'ThemeIcon', 'PageTitle', 'PageDesc', 'PresetBar', 'BtnRec', 'BtnComp',
                   'Tabs', 'TabScroll', 'TweakPage', 'TweakList', 'ToolsPage', 'ToolGrid', 'LogPage', 'Log', 'ModulePage', 'ModuleHost', 'Rail', 'Detail',
                   'Ledger', 'LedgerSub', 'LedgerCount', 'LedgerApply', 'LedgerRevert', 'LedgerReboot', 'LedgerGrid', 'LedgerList', 'BtnDiscard', 'BtnApply',
                   'StatList', 'QueuePill', 'QueueText') {
        $ui[$n] = $window.FindName($n)
    }
    $script:LogBox = $ui.Log
    # Vista Pro: claves, servicios, tareas y rutas. Sin ella, el panel enseña solo lo que hace falta para decidir.
    $script:ProFile = Join-Path $script:Root 'pro.txt'
    $script:Pro = Test-Path -LiteralPath $script:ProFile
    $script:ProOnly = @()
    $FgProp = [Windows.Controls.TextBlock]::ForegroundProperty
    $BgProp = [Windows.Controls.Border]::BackgroundProperty
    $FillProp = [Windows.Shapes.Shape]::FillProperty

    # ---------- piezas comunes (también las usan los módulos)
    function New-Text([string]$Text, [double]$Size = 14, [string]$Brush = 'Ink', [string]$Weight = 'Normal') {
        $tb = [Windows.Controls.TextBlock]::new()
        $tb.Text = (T $Text); $tb.FontSize = $Size; $tb.FontWeight = $Weight; $tb.TextWrapping = 'Wrap'
        $tb.SetResourceReference($FgProp, $Brush)
        $tb
    }
    function New-Mono([string]$Text, [double]$Size = 13, [string]$Brush = 'Ink') {
        $tb = New-Text $Text $Size $Brush; $tb.FontFamily = $window.FindResource('Mono'); $tb.TextWrapping = 'NoWrap'; $tb
    }
    # Iconos: Phosphor Icons (MIT) para funciones y Simple Icons (CC0) para marcas, en assets\icons.json.
    # Las marcas toman su color real (recurso Brand-<nombre>) salvo que se pida otro color.
    $script:IconData = $null; $script:GeoCache = @{}
    try { $script:IconData = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assets\icons.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    function New-Icon($Code, [double]$Size = 18, [string]$Brush = 'Ink2') {
        if ($Code -is [string] -and $script:IconData -and $script:IconData.PSObject.Properties[$Code]) {
            $ic = $script:IconData.$Code
            if (-not $script:GeoCache.ContainsKey($Code)) { $geo = [Windows.Media.Geometry]::Parse($ic.d); $geo.Freeze(); $script:GeoCache[$Code] = $geo }
            $p = [Windows.Shapes.Path]::new(); $p.Data = $script:GeoCache[$Code]
            if ($BrandColors.ContainsKey($Code) -and $Brush -eq 'Ink2') { $Brush = "Brand-$Code" }
            $p.SetResourceReference($FillProp, $Brush)
            $c = [Windows.Controls.Canvas]::new(); $c.Width = $ic.vb; $c.Height = $ic.vb; [void]$c.Children.Add($p)
            $v = [Windows.Controls.Viewbox]::new(); $v.Width = $Size; $v.Height = $Size; $v.Child = $c; $v.VerticalAlignment = 'Center'
            return $v
        }
        if ($Code -is [string]) { $Code = 0xE713 }
        $tb = [Windows.Controls.TextBlock]::new()
        $tb.Text = [string][char]$Code; $tb.FontSize = $Size; $tb.FontFamily = $window.FindResource('Icons'); $tb.VerticalAlignment = 'Center'
        $tb.SetResourceReference($FgProp, $Brush)
        $tb
    }
    function New-BtnIcon($Code, [double]$Size = 18) {
        # icono que toma el color del texto del botón (así se apaga igual que el texto cuando el botón está desactivado)
        $ic = New-Icon $Code $Size 'Ink'
        $bd = [Windows.Data.Binding]::new('Foreground'); $bd.RelativeSource = [Windows.Data.RelativeSource]::new([Windows.Data.RelativeSourceMode]::FindAncestor, [Windows.Controls.Button], 1)
        if ($ic -is [Windows.Controls.Viewbox]) { [void]$ic.Child.Children[0].SetBinding($FillProp, $bd) } else { [void]$ic.SetBinding($FgProp, $bd) }
        $ic
    }
    function Set-IconBrush($Icon, [string]$Brush) {
        if ($Icon -is [Windows.Controls.Viewbox]) { $Icon.Child.Children[0].SetResourceReference($FillProp, $Brush) }
        else { $Icon.SetResourceReference($FgProp, $Brush) }
    }
    function New-IconWell($Code, [double]$Box = 38, [string]$Brush = 'Ink2') {
        $w = [Windows.Controls.Border]::new(); $w.Width = $Box; $w.Height = $Box; $w.CornerRadius = 8; $w.VerticalAlignment = 'Center'
        # sin color pedido, cada icono toma uno fijo de la paleta (el mismo icono, siempre el mismo color); las marcas, el suyo
        if ($Brush -eq 'Ink2' -and $Code -is [string] -and $Code -notlike 'brand-*') {
            $pal = 'Cat-Privacidad', 'Cat-Servicios', 'Cat-Rendimiento', 'Cat-Latencia', 'Cat-Juegos', 'Cat-Actualizaciones', 'Cat-Interfaz', 'Cat-Apps'
            $h = 0; foreach ($ch in $Code.ToCharArray()) { $h = ($h * 31 + [int]$ch) % 9973 }
            $Brush = $pal[$h % $pal.Count]
        }
        # los iconos de color llevan su fondo teñido del mismo tono
        $w.SetResourceReference($BgProp, $(if ($Brush -like 'Cat-*') { "Soft$Brush" } else { 'Paper3' }))
        $ic = New-Icon $Code ([math]::Round($Box * 0.55)) $Brush; $ic.HorizontalAlignment = 'Center'; $w.Child = $ic
        $w
    }
    function New-Chip([string]$Text, [string]$Bg = 'Paper3', [string]$Fg = 'Ink2') {
        $c = [Windows.Controls.Border]::new(); $c.CornerRadius = 6; $c.Padding = '7,1,7,2'; $c.Margin = '0,0,6,0'; $c.VerticalAlignment = 'Center'
        $c.SetResourceReference($BgProp, $Bg)
        $t = New-Text $Text 12.5 $Fg 'SemiBold'; $t.TextWrapping = 'NoWrap'; $c.Child = $t
        $c
    }
    function Set-Chip($Chip, [string]$Text, [string]$Bg, [string]$Fg) {
        if (-not $Text) { $Chip.Visibility = 'Collapsed'; return }
        $Chip.Visibility = 'Visible'; $Chip.Child.Text = (T $Text)
        $Chip.SetResourceReference($BgProp, $Bg); $Chip.Child.SetResourceReference($FgProp, $Fg)
    }
    function New-Btn([string]$Text, [switch]$Primary) {
        $b = [Windows.Controls.Button]::new()
        $b.Style = $window.FindResource($(if ($Primary) { 'BtnPrimary' } else { 'Btn' })); $b.Content = (T $Text)
        $b
    }
    function New-Card { $b = [Windows.Controls.Border]::new(); $b.Style = $window.FindResource('Tile'); $b.Margin = '0,0,0,10'; $b }
    function New-Section([string]$Text) { $t = New-Text $Text 18 'Ink' 'SemiBold'; $t.FontFamily = $window.FindResource('Display'); $t.Margin = '0,22,0,8'; $t }
    function New-Ruled { $s = [Windows.Controls.Border]::new(); $s.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Ink'); $s.BorderThickness = '0,1,0,0'; $s }
    function New-Cols([string[]]$Widths) {
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in $Widths) {
            $cd = [Windows.Controls.ColumnDefinition]::new()
            if ($w -eq '*') { $cd.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star) }
            elseif ($w -eq 'Auto') { $cd.Width = [Windows.GridLength]::Auto }
            else { $cd.Width = [Windows.GridLength]::new([double]$w) }
            $g.ColumnDefinitions.Add($cd)
        }
        $g
    }
    function Add-At($Grid, $El, [int]$Col) { [Windows.Controls.Grid]::SetColumn($El, $Col); [void]$Grid.Children.Add($El); $El }
    function New-Switch { $s = [Windows.Controls.Primitives.ToggleButton]::new(); $s.Style = $window.FindResource('Switch'); $s.VerticalAlignment = 'Center'; $s }
    function Format-Size([double]$Bytes) {
        if ($Bytes -ge 1GB) { '{0:N1} GB' -f ($Bytes / 1GB) } elseif ($Bytes -ge 1MB) { '{0:N0} MB' -f ($Bytes / 1MB) }
        elseif ($Bytes -gt 0) { '{0:N0} KB' -f ($Bytes / 1KB) } else { '0 MB' }
    }
    function New-Timer([double]$Seconds, [scriptblock]$Tick) {
        $t = New-Object System.Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds($Seconds); $t.Add_Tick($Tick); $t
    }
    function New-ActionRow($Icon, [string]$Title, [string]$Desc, $Action) {
        $row = [Windows.Controls.Border]::new(); $row.Style = $window.FindResource('RuleRow')
        $g = New-Cols @('54', '*', 'Auto')
        [void](Add-At $g (New-IconWell $Icon) 0)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
        [void]$sp.Children.Add((New-Text $Title 14.5 'Ink' 'SemiBold'))
        if ($Desc) { $d = New-Text $Desc 13.5 'Muted'; $d.Margin = '0,2,0,0'; [void]$sp.Children.Add($d) }
        [void](Add-At $g $sp 1)
        if ($Action) { $Action.Margin = '16,0,0,0'; $Action.VerticalAlignment = 'Center'; [void](Add-At $g $Action 2) }
        $row.Child = $g
        $row
    }
    function Get-ExeIcon([string]$Path, [int]$Size = 24) {
        try {
            $exe = ($Path -replace '^"([^"]+)".*$', '$1') -replace '\s+--?.*$', ''
            if (-not (Test-Path -LiteralPath $exe)) { return $null }
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($exe)
            try { $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ico.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromWidthAndHeight($Size, $Size)); $src.Freeze() }
            finally { $ico.Dispose() }   # libera el HICON: el BitmapSource ya tiene su propia copia
            $img = [Windows.Controls.Image]::new(); $img.Source = $src; $img.Width = $Size; $img.Height = $Size
            $img
        }
        catch { $null }
    }
    function Start-FadeIn($El) {
        $a = New-Object Windows.Media.Animation.DoubleAnimation 0, 1, ([Windows.Duration][TimeSpan]::FromMilliseconds(160))
        $El.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
    }
    foreach ($m in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'modules') -Filter *.ps1 -ErrorAction SilentlyContinue) { . $m.FullName }

    # ---------- tema
    function Get-Luma([string]$Hex) { $c = [Windows.Media.ColorConverter]::ConvertFromString($Hex); (0.2126 * $c.R + 0.7152 * $c.G + 0.0722 * $c.B) / 255 }
    function Set-Theme([string]$Name) {
        $th = $Themes[$Name]; $script:ThemeName = $Name
        # Todos los colores van en un diccionario nuevo que sustituye al anterior de una vez: cambiar los recursos
        # uno a uno obliga a WPF a recorrer toda la ventana por cada color (con ~100 colores, varios segundos).
        $rd = [Windows.ResourceDictionary]::new()
        foreach ($k in $th.Keys) {
            if ($k -eq 'Dark') { continue }
            $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($th[$k])); $b.Freeze(); $rd[$k] = $b
            if ($k -like 'Cat-*') {   # fondo suave de cada color, para los pozos de icono
                $c = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($th[$k]); $c.A = $(if ($th.Dark) { 0x30 } else { 0x24 })
                $sb = [Windows.Media.SolidColorBrush]::new($c); $sb.Freeze(); $rd["Soft$k"] = $sb
            }
        }
        foreach ($bk in $BrandColors.Keys) {
            $hex = $BrandColors[$bk]; if ($th.Dark -and (Get-Luma $hex) -lt 0.3) { $hex = $th.Ink }
            $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex)); $b.Freeze(); $rd["Brand-$bk"] = $b
        }
        if (-not $script:ThemeDict) { foreach ($k in @($rd.Keys)) { if ($window.Resources.Contains($k)) { $window.Resources.Remove($k) } } }   # los colores por defecto del XAML
        $oldRd = $script:ThemeDict
        $window.Resources.MergedDictionaries.Add($rd); $script:ThemeDict = $rd
        if ($oldRd) { [void]$window.Resources.MergedDictionaries.Remove($oldRd) }
        $pen = [Windows.Media.Pen]::new($window.Resources['Grid'], 1)
        $dr = [Windows.Media.GeometryDrawing]::new($null, $pen, [Windows.Media.Geometry]::Parse('M0,0 L8,0 M0,0 L0,8'))
        $nb = [Windows.Media.DrawingBrush]::new($dr); $nb.TileMode = 'Tile'; $nb.Viewport = [Windows.Rect]::new(0, 0, 8, 8); $nb.ViewportUnits = 'Absolute'
        $ui.LedgerGrid.Background = $nb
        $h = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
        if ($h -ne [IntPtr]::Zero) { $v = [int]$th.Dark; [void][GP.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4) }
        $ui.ThemeIcon.Content = if ($th.Dark) { New-Icon 'sun' 18 'Ink' } else { New-Icon 'moon' 18 'Ink' }
        $ui.BtnTheme.ToolTip = T $(if ($th.Dark) { 'Tema claro' } else { 'Tema oscuro' })
        try { Set-Content -LiteralPath (Join-Path $script:Root 'theme.txt') -Value $Name } catch {}
    }
    $startTheme = 'FurrowNoche'   # el oscuro con naranja es el tema principal
    try { $saved = (Get-Content -LiteralPath (Join-Path $script:Root 'theme.txt') -ErrorAction Stop | Select-Object -First 1).Trim(); if ($Themes.ContainsKey($saved)) { $startTheme = $saved } } catch {}
    Set-Theme $startTheme
    # ---------- logo: anillo abierto (el "O" de Opti, como un botón de encendido) con el 11 dentro
    $logo = [Windows.Controls.Canvas]::new(); $logo.Width = 64; $logo.Height = 64
    foreach ($p in @(@('M 47.56 18.44 A 22 22 0 1 1 16.44 18.44', 'Paper2'), @('M 23.5 12.5 L 27.5 8.5 L 27.5 31 M 36.5 12.5 L 40.5 8.5 L 40.5 31', 'Accent'))) {
        $path = [Windows.Shapes.Path]::new(); $path.Data = [Windows.Media.Geometry]::Parse($p[0]); $path.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, $p[1])
        $path.StrokeThickness = 6.5; $path.StrokeStartLineCap = 'Round'; $path.StrokeEndLineCap = 'Round'; $path.StrokeLineJoin = 'Round'
        [void]$logo.Children.Add($path)
    }
    $vb = [Windows.Controls.Viewbox]::new(); $vb.Width = 23; $vb.Height = 23; $vb.Child = $logo; $vb.Margin = '0,1,0,0'
    $ui.BrandMark.Content = $vb
    try { $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri](Join-Path $PSScriptRoot 'assets\optieleven.ico')) } catch {}

    # ---------- idioma (arriba del todo, junto al nombre)
    $ui.LangIcon.Content = (New-Icon 'globe-simple' 16 'Ink2')
    $ui.LangCode.Text = $script:LangCode.ToUpper()
    $langMenu = [Windows.Controls.ContextMenu]::new()
    $langMenu.PlacementTarget = $ui.BtnLang; $langMenu.Placement = 'Bottom'
    foreach ($l in @(Get-Languages)) {
        $mi = [Windows.Controls.MenuItem]::new()
        $mi.Header = "$($l.Name)"; $mi.Tag = $l.Code; $mi.IsCheckable = $false
        if ($l.Code -eq $script:LangCode) { $mi.Icon = (New-Icon 'check' 14 'Accent'); $mi.FontWeight = 'SemiBold' }
        $mi.Add_Click({
            param($sender)
            $code = [string]$sender.Tag
            if ($code -eq $script:LangCode) { return }
            if (@(Get-Pending).Count -and [Windows.MessageBox]::Show($window, (T 'Para cambiar de idioma, OptiEleven se vuelve a abrir. Los cambios sin aplicar de la hoja se pierden.'), 'OptiEleven', 'OKCancel', 'Question') -ne 'OK') { return }
            try { Set-Content -LiteralPath $script:LangFile -Value $code -Encoding ASCII } catch { Write-Log "No se pudo guardar el idioma: $($_.Exception.Message)" 'ERROR'; return }
            $script:Relaunch = if ($script:CurrentPage) { $script:CurrentPage } else { 'all' }
            $window.Close()
        })
        [void]$langMenu.Items.Add($mi)
    }
    $ui.BtnLang.ContextMenu = $langMenu
    $ui.BtnLang.Add_Click({ $ui.BtnLang.ContextMenu.IsOpen = $true })

    # ---------- botones de preset: grandes, con icono, como el de Boost FPS
    foreach ($pb in @(@($ui.BtnRec, 'shield-check', 'Recomendado'), @($ui.BtnComp, 'lightning', 'Avanzado'))) {
        $c = [Windows.Controls.StackPanel]::new(); $c.Orientation = 'Horizontal'
        $i = New-BtnIcon $pb[1] 19; $i.Margin = '0,0,9,0'
        $l = [Windows.Controls.TextBlock]::new(); $l.Text = T $pb[2]; $l.VerticalAlignment = 'Center'
        [void]$c.Children.Add($i); [void]$c.Children.Add($l); $pb[0].Content = $c
    }

    # ---------- aviso al abrir
    $script:WarnFile = Join-Path $script:Root 'warning.ok'
    function Show-StartWarning {
        $ov = [Windows.Controls.Grid]::new()
        [Windows.Controls.Grid]::SetRowSpan($ov, 10); [Windows.Controls.Grid]::SetColumnSpan($ov, 10); [Windows.Controls.Panel]::SetZIndex($ov, 100)
        $ov.Background = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromArgb(0xC0, 0x05, 0x04, 0x02))
        $card = [Windows.Controls.Border]::new(); $card.CornerRadius = 14; $card.Padding = '30,26,30,24'; $card.MaxWidth = 580; $card.Margin = '24'
        $card.HorizontalAlignment = 'Center'; $card.VerticalAlignment = 'Center'; $card.BorderThickness = 1.5
        $card.SetResourceReference($BgProp, 'Paper2'); $card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Accent')
        $sp = [Windows.Controls.StackPanel]::new()
        $hd = New-Cols @('Auto', '*')
        $well = [Windows.Controls.Border]::new(); $well.Width = 48; $well.Height = 48; $well.CornerRadius = 11; $well.SetResourceReference($BgProp, 'Accent')
        $wi = New-Icon 'warning-octagon' 26 'AccentInk'; $wi.HorizontalAlignment = 'Center'; $well.Child = $wi
        [void](Add-At $hd $well 0)
        $ht = New-Text 'Antes de empezar' 24 'Ink' 'Bold'; $ht.FontFamily = $window.FindResource('Display'); $ht.VerticalAlignment = 'Center'; $ht.Margin = '16,0,0,0'
        [void](Add-At $hd $ht 1)
        [void]$sp.Children.Add($hd)
        $lines = @(
            @('arrow-counter-clockwise', 'OptiEleven cambia ajustes de Windows. Casi todo se puede revertir desde el panel; lo que no, va marcado como "Sin vuelta atrás".'),
            @('shield-check', 'El preset Recomendado es seguro para casi todos los equipos.'),
            @('lightning', 'Avanzado y los ajustes marcados como Moderado o Avanzado pueden quitar funciones que uses (Xbox, impresoras, búsqueda...). Lee la descripción de cada uno y aplícalos con cuidado, mejor de uno en uno.'),
            @('clock-counter-clockwise', 'Crea un punto de restauración antes del primer cambio: Sistema > Punto de restauración.'))
        foreach ($ln in $lines) {
            $r = New-Cols @('Auto', '*'); $r.Margin = '0,16,0,0'
            $ic = New-Icon $ln[0] 20 'Accent'; $ic.VerticalAlignment = 'Top'; $ic.Margin = '2,1,14,0'
            [void](Add-At $r $ic 0); [void](Add-At $r (New-Text $ln[1] 14.5 'Ink2') 1)
            [void]$sp.Children.Add($r)
        }
        $fine = New-Text 'Usas OptiEleven bajo tu responsabilidad.' 13 'Muted'; $fine.Margin = '36,16,0,0'
        [void]$sp.Children.Add($fine)
        $ft = New-Cols @('*', 'Auto'); $ft.Margin = '0,22,0,0'
        $chk = [Windows.Controls.StackPanel]::new(); $chk.Orientation = 'Horizontal'; $chk.VerticalAlignment = 'Center'
        $sw = New-Switch; $sw.Margin = '0,0,10,0'
        $swl = New-Text 'No volver a mostrar' 13.5 'Ink2'; $swl.VerticalAlignment = 'Center'
        [Windows.Automation.AutomationProperties]::SetName($sw, (T 'No volver a mostrar'))
        [void]$chk.Children.Add($sw); [void]$chk.Children.Add($swl)
        [void](Add-At $ft $chk 0)
        $ok = New-Btn 'Entendido' -Primary; $ok.MinHeight = 44; $ok.Padding = '28,0'; $ok.FontSize = 15; $ok.FontWeight = 'Bold'; $ok.IsDefault = $true; $ok.IsCancel = $true
        $ok.Tag = @{ Overlay = $ov; Switch = $sw }
        $ok.Add_Click({
            param($src)
            if ($src.Tag.Switch.IsChecked) { try { Set-Content -LiteralPath $script:WarnFile -Value (Get-Date -Format s) } catch {} }
            [void]$window.Content.Children.Remove($src.Tag.Overlay)
        })
        [void](Add-At $ft $ok 1)
        [void]$sp.Children.Add($ft)
        $card.Child = $sp
        [void]$ov.Children.Add($card)
        [void]$window.Content.Children.Add($ov)
        $window.Add_ContentRendered({ $ok.Focus() }.GetNewClosure())
    }
    if (-not (Test-Path -LiteralPath $script:WarnFile)) { Show-StartWarning }
    # al tener ventana real solo falta la barra de título oscura; los colores ya están puestos
    $window.Add_SourceInitialized({ $h = (New-Object Windows.Interop.WindowInteropHelper $window).Handle; $v = [int]$Themes[$script:ThemeName].Dark; [void][GP.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4) })
    $ui.BtnTheme.Add_Click({ if ($script:ThemeName -eq 'Furrow') { Set-Theme 'FurrowNoche' } else { Set-Theme 'Furrow' } })

    if ($script:IsAdmin) { $ui.AdminIcon.Content = (New-Icon 'shield-check' 18 'Green'); $ui.AdminTitle.Text = (T 'Administrador'); $ui.AdminChip.ToolTip = (T 'Puedes aplicar y revertir ajustes.') }
    else { $ui.AdminIcon.Content = (New-Icon 'lock-simple' 18 'Ink2'); $ui.AdminTitle.Text = (T 'Solo lectura'); $ui.AdminChip.ToolTip = (T 'Ábrelo con OptiEleven.cmd para aplicar cambios.') }

    # ---------- navegación: cada apartado con su color
    $NavColors = @{ 'all' = 'Accent'; 'm-boost' = 'Cat-Rendimiento'; 'm-games' = 'Cat-Juegos'; 'm-apps' = 'Cat-Actualizaciones'; 'm-startup' = 'Cat-Servicios'
                    'm-clean' = 'Cat-Interfaz'; 'm-net' = 'Cat-Privacidad'; 'm-repair' = 'Cat-Latencia'; 'm-hw' = 'Cat-Apps'; 'tools' = 'Cat-Servicios'; 'log' = 'Ink2' }
    $script:NavParts = @{}
    foreach ($key in $Pages.Keys) {
        $pg = $Pages[$key]
        if ($pg.Tab -and $key -ne 'all') { continue }
        if ($pg.Header) {
            $hi = [Windows.Controls.ListBoxItem]::new(); $hi.IsEnabled = $false; $hi.Focusable = $false
            $hi.Content = (New-Text $pg.Header 12.5 'Muted' 'SemiBold'); $hi.Margin = '0,14,0,2'
            [void]$ui.Nav.Items.Add($hi)
            continue
        }
        $g = New-Cols @('Auto', '*', 'Auto'); $g.Tag = $key
        $ic = New-Icon $pg.Icon 19 $NavColors[$key]; $ic.Margin = '0,0,11,0'
        [void](Add-At $g $ic 0)
        $lb = New-Text $pg.Label 14 'Ink'; $lb.VerticalAlignment = 'Center'; $lb.TextWrapping = 'NoWrap'
        [void](Add-At $g $lb 1)
        $cn = $null
        if ($key -eq 'all') { $cn = New-Text "$($Tweaks.Count)" 12.5 'Muted'; $cn.VerticalAlignment = 'Center'; [void](Add-At $g $cn 2) }
        [void]$ui.Nav.Items.Add($g)
        $script:NavParts[$key] = @{ Icon = $ic; Label = $lb; Count = $cn }
    }
    function Update-NavColors {
        foreach ($k in $script:NavParts.Keys) {
            $sel = $ui.Nav.SelectedItem -and $ui.Nav.SelectedItem.Tag -eq $k
            $np = $script:NavParts[$k]
            Set-IconBrush $np.Icon $(if ($sel) { 'AccentInk' } else { $NavColors[$k] })
            $np.Label.SetResourceReference($FgProp, $(if ($sel) { 'AccentInk' } else { 'Ink' }))
            $np.Label.FontWeight = $(if ($sel) { 'SemiBold' } else { 'Normal' })
            if ($np.Count) { $np.Count.SetResourceReference($FgProp, $(if ($sel) { 'AccentInk' } else { 'Muted' })) }
        }
    }
    $script:TabParts = [ordered]@{}
    foreach ($key in $Pages.Keys) {
        $pg = $Pages[$key]; if (-not $pg.Tab) { continue }
        $tb = [Windows.Controls.Primitives.ToggleButton]::new(); $tb.Style = $window.FindResource('TabToggle'); $tb.Tag = $key
        $n = if ($key -eq 'all') { $Tweaks.Count } else { @($Tweaks | Where-Object Cat -eq $key).Count }
        $tc = [Windows.Controls.StackPanel]::new(); $tc.Orientation = 'Horizontal'
        if ($key -ne 'all') {   # punto del color de la categoría
            $dot = [Windows.Shapes.Ellipse]::new(); $dot.Width = 8; $dot.Height = 8; $dot.Margin = '0,0,7,0'; $dot.VerticalAlignment = 'Center'
            $dot.SetResourceReference($FillProp, "Cat-$key"); [void]$tc.Children.Add($dot)
        }
        $tl = [Windows.Controls.TextBlock]::new(); $tl.Text = T $pg.Tab; $tl.VerticalAlignment = 'Center'; [void]$tc.Children.Add($tl)
        $tb.Content = $tc; $tb.ToolTip = (T "$n ajustes")
        $tb.Add_Click({ param($src, $e) Show-Page $src.Tag })
        [void]$ui.Tabs.Children.Add($tb)
        $script:TabParts[$key] = $tb
    }
    $ui.TabScroll.Add_PreviewMouseWheel({ param($src, $e) $src.ScrollToHorizontalOffset($src.HorizontalOffset - $e.Delta / 2); $e.Handled = $true })
    function Update-Tabs([string]$Key) { foreach ($k in $script:TabParts.Keys) { $script:TabParts[$k].IsChecked = ($k -eq $Key) } }

    # ---------- filas de ajustes: compactas, agrupadas por categoría
    $script:Rows = [ordered]@{}
    $script:GroupHeads = @{}
    $script:Selected = $null
    $riskChip = @{ Seguro = @('Seguro', 'GreenSoft', 'Green'); Moderado = @('Moderado', 'AmberSoft', 'Amber'); Avanzado = @('Avanzado', 'RedSoft', 'Red') }
    $cats = @($Pages.Keys | Where-Object { $Pages[$_].Tab -and $_ -ne 'all' })
    function Add-CategoryRows([string]$cat) {
        $list = @($Tweaks | Where-Object Cat -eq $cat | Sort-Object @{ e = { $_.Name } })
        if (-not $list) { return }
        $head = New-Cols @('30', '*', 'Auto'); $head.Margin = '0,20,0,6'
        $hi = New-Icon $Pages[$cat].Icon 20 "Cat-$cat"; [void](Add-At $head $hi 0)
        $ht = New-Text $Pages[$cat].Title 18 'Ink' 'SemiBold'; $ht.FontFamily = $window.FindResource('Display'); [void](Add-At $head $ht 1)
        $hc = New-Text "$($list.Count)" 13 'Muted'; $hc.FontFamily = $window.FindResource('Mono'); $hc.VerticalAlignment = 'Bottom'; [void](Add-At $head $hc 2)
        [void]$ui.TweakList.Children.Add($head)
        $rule = [Windows.Controls.Border]::new(); $rule.Height = 2; $rule.CornerRadius = 1; $rule.SetResourceReference($BgProp, "Cat-$cat")
        [void]$ui.TweakList.Children.Add($rule)
        $script:GroupHeads[$cat] = @($head, $rule)

        foreach ($t in $list) {
            $border = [Windows.Controls.Border]::new(); $border.Style = $window.FindResource('RuleRow'); $border.Padding = '0,7,8,7'; $border.Cursor = 'Hand'; $border.Tag = $t.Id
            $outer = New-Cols @('3', '*')
            $mark = [Windows.Controls.Border]::new(); $mark.SetResourceReference($BgProp, 'Accent'); $mark.Visibility = 'Hidden'; $mark.Margin = '0,-7,0,-7'
            [void](Add-At $outer $mark 0)
            $grid = New-Cols @('50', '*', 'Auto', 'Auto'); $grid.Margin = '7,0,0,0'
            $icon = if ($TweakIcons.ContainsKey($t.Id)) { $TweakIcons[$t.Id] } else { 'gear-six' }
            [void](Add-At $grid (New-IconWell $icon 38 "Cat-$cat") 0)
            $left = [Windows.Controls.StackPanel]::new(); $left.VerticalAlignment = 'Center'
            $nm = New-Text $t.Name 14.5 'Ink' 'SemiBold'; $nm.TextWrapping = 'NoWrap'; $nm.TextTrimming = 'CharacterEllipsis'
            $ds = New-Text $t.Desc 13 'Muted'; $ds.TextWrapping = 'NoWrap'; $ds.TextTrimming = 'CharacterEllipsis'; $ds.Margin = '0,1,0,0'
            if (-not $script:Pro) { $ds.Visibility = 'Collapsed' }
            [void]$left.Children.Add($nm); [void]$left.Children.Add($ds)
            [void](Add-At $grid $left 1)
            $chips = [Windows.Controls.StackPanel]::new(); $chips.Orientation = 'Horizontal'; $chips.Margin = '14,0,0,0'
            $rc = $riskChip[$t.Risk]
            if ($t.Risk -ne 'Seguro') { [void]$chips.Children.Add((New-Chip $rc[0] $rc[1] $rc[2])) }
            $state = New-Chip '...' 'Paper3' 'Muted'; [void]$chips.Children.Add($state)
            [void](Add-At $grid $chips 2)
            $sw = New-Switch; $sw.Margin = '10,0,0,0'; $sw.IsEnabled = $false; $sw.Tag = $t.Id
            [Windows.Automation.AutomationProperties]::SetName($sw, $t.Name)
            $sw.Add_Click({ param($src, $e) Update-Pending; Select-Row $script:Rows[$src.Tag] })
            [void](Add-At $grid $sw 3)
            [void](Add-At $outer $grid 1)
            $border.Child = $outer
            $border.Add_MouseLeftButtonUp({
                param($src, $e)
                $row = $script:Rows[$src.Tag]
                Select-Row $row
            })
            $border.Add_MouseLeftButtonDown({
                param($src, $e)
                if ($e.ClickCount -eq 2) { $row = $script:Rows[$src.Tag]; if ($row.Switch.IsEnabled -and -not $script:Busy) { $row.Switch.IsChecked = -not [bool]$row.Switch.IsChecked; Update-Pending; Select-Row $row } }
            })
            [void]$ui.TweakList.Children.Add($border)
            $script:Rows[$t.Id] = @{ Tweak = $t; Switch = $sw; Border = $border; State = $state; Mark = $mark; Applied = $null; Desc = $ds }
        }
    }
    # Solo las dos primeras categorías antes de enseñar la ventana (lo que se ve al abrir); el resto justo después
    # del primer pintado, para que la ventana aparezca antes. Este evento se registra antes que la comprobación de
    # estado, así que cuando esa empieza ya están todas las filas.
    foreach ($cat in @($cats | Select-Object -First 2)) { Add-CategoryRows $cat }
    $window.Add_ContentRendered({
        foreach ($cat in @($cats | Select-Object -Skip 2)) { Add-CategoryRows $cat }
        if ($script:CurrentPage -and $script:CurrentPage -ne 'all' -and $Pages[$script:CurrentPage].Tab) { Show-Page $script:CurrentPage }
    })

    # ---------- detalle: qué cambia exactamente
    function Select-Row($row) {
        if ($script:Selected -and $script:Selected -ne $row) { $script:Selected.Border.ClearValue($BgProp) }
        $script:Selected = $row
        if ($row) { $row.Border.SetResourceReference($BgProp, 'Paper2') }
        Show-Detail $row
    }
    function Show-Detail($row) {
        $d = $ui.Detail; $d.Children.Clear()
        if (-not $row) {
            $well = [Windows.Controls.Border]::new(); $well.Width = 52; $well.Height = 52; $well.CornerRadius = 14; $well.HorizontalAlignment = 'Left'
            $well.SetResourceReference($BgProp, 'AccentSoft')
            $wi = New-Icon 'sliders-horizontal' 26 'Accent'; $wi.HorizontalAlignment = 'Center'; $well.Child = $wi
            [void]$d.Children.Add($well)
            $et = New-Text 'Elige un ajuste' 20 'Ink' 'SemiBold'; $et.FontFamily = $window.FindResource('Display'); $et.Margin = '0,16,0,6'
            [void]$d.Children.Add($et)
            [void]$d.Children.Add((New-Text $(if ($script:Pro) { 'Toca cualquier fila para ver qué claves, servicios y tareas cambia, con el valor de ahora y el de después.' } else { 'Toca cualquier fila para ver qué hace y si es seguro. O pulsa Recomendado para marcar de una vez lo que conviene a casi todos.' }) 14 'Muted'))
            return
        }
        $t = $row.Tweak
        $hd = New-Cols @('52', '*')
        [void](Add-At $hd (New-IconWell $(if ($TweakIcons.ContainsKey($t.Id)) { $TweakIcons[$t.Id] } else { 'gear-six' }) 42 "Cat-$($t.Cat)") 0)
        $tt = New-Text $t.Name 18 'Ink' 'SemiBold'; $tt.FontFamily = $window.FindResource('Display'); $tt.VerticalAlignment = 'Center'
        [void](Add-At $hd $tt 1)
        [void]$d.Children.Add($hd)
        $ds = New-Text $t.Desc 13.5 'Ink2'; $ds.Margin = '0,10,0,10'; [void]$d.Children.Add($ds)

        $chips = [Windows.Controls.WrapPanel]::new()
        $rc = $riskChip[$t.Risk]; [void]$chips.Children.Add((New-Chip $rc[0] $rc[1] $rc[2]))
        [void]$chips.Children.Add((New-Chip $(if ($t.Presets -contains 'R') { 'En Recomendado' } elseif ($t.Presets -contains 'A') { 'En Avanzado' } else { 'Solo a mano' }) 'Paper3' 'Ink2'))
        if ($t.Reboot) { [void]$chips.Children.Add((New-Chip 'Reinicio' 'Paper3' 'Ink2')) }
        if ($t.Irreversible) { [void]$chips.Children.Add((New-Chip 'Sin vuelta atrás' 'Paper3' 'Ink2')) }
        [void]$d.Children.Add($chips)
        $revert = [bool]$row.Applied
        $diff = try { @(Get-TweakDiff $t $revert) } catch { @() }
        $changes = @($diff | Where-Object { -not $_.Same }).Count
        if (-not $script:Pro) {
            # vista sencilla: sin claves ni valores, solo si cambia algo y cómo verlo
            $n = $changes
            $box = [Windows.Controls.Border]::new(); $box.CornerRadius = 10; $box.Padding = '14,12'; $box.Margin = '0,16,0,0'
            $box.SetResourceReference($BgProp, "SoftCat-$($t.Cat)")
            $bg = New-Cols @('Auto', '*')
            $bi = New-Icon $(if ($revert -or $n) { 'arrow-counter-clockwise' } else { 'check' }) 20 "Cat-$($t.Cat)"; $bi.Margin = '0,0,12,0'; $bi.VerticalAlignment = 'Top'
            [void](Add-At $bg $bi 0)
            $msg = if ($t.Irreversible -and -not $revert) { 'Este no se puede deshacer desde el panel. Lee bien la descripción.' }
                   elseif ($revert) { 'Está aplicado. Si lo desactivas, Windows vuelve a como estaba.' }
                   elseif ($n) { 'Al aplicarlo se guarda cómo estaba, para poder revertirlo cuando quieras.' }
                   else { 'En este equipo ya está así.' }
            [void](Add-At $bg (New-Text $msg 13.5 'Ink') 1)
            $box.Child = $bg
            [void]$d.Children.Add($box)
            $pro = New-Text 'Activa la Vista Pro para ver qué claves, servicios y tareas cambia.' 12.5 'Muted'; $pro.Margin = '0,12,0,0'
            [void]$d.Children.Add($pro)
            Start-FadeIn $d
            return
        }
        $bk = Get-Backup $t.Id
        $bkt = New-Text $(if ($bk) { "Copia de seguridad del $($bk.Time -replace 'T', ' a las ')" } else { 'Sin copia todavía: se guarda al aplicar.' }) 12.5 'Muted'
        $bkt.Margin = '0,10,0,0'; [void]$d.Children.Add($bkt)

        $h2 = New-Cols @('*', 'Auto'); $h2.Margin = '0,18,0,6'
        $h2t = New-Text $(if ($revert) { 'Qué vuelve al revertir' } else { 'Qué cambia al aplicar' }) 15 'Ink' 'SemiBold'; $h2t.FontFamily = $window.FindResource('Display')
        [void](Add-At $h2 $h2t 0)
        $h2c = New-Mono "$changes de $($diff.Count)" 12.5 'Muted'; $h2c.VerticalAlignment = 'Bottom'; [void](Add-At $h2 $h2c 1)
        [void]$d.Children.Add($h2)
        [void]$d.Children.Add((New-Ruled))
        $shown = 0
        foreach ($l in $diff) {
            if ($shown -ge 30) { $more = New-Text "y $($diff.Count - 30) más" 12.5 'Muted'; $more.Margin = '0,8,0,0'; [void]$d.Children.Add($more); break }
            $li = [Windows.Controls.Border]::new(); $li.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Rule'); $li.BorderThickness = '0,0,0,1'; $li.Padding = '0,7'
            $sp = [Windows.Controls.StackPanel]::new()
            $tg = New-Mono $l.Target 12 'Ink2'; $tg.TextWrapping = 'Wrap'
            [void]$sp.Children.Add($tg)
            $vg = [Windows.Controls.WrapPanel]::new(); $vg.Margin = '0,3,0,0'
            if ($l.Same) { [void]$vg.Children.Add((New-Text "sin cambios: $($l.Before)" 12.5 'Muted')) }
            else {
                $b4 = New-Text $l.Before 12.5 'Muted'; $b4.TextDecorations = 'Strikethrough'
                $ar = New-Text '  →  ' 12.5 'Muted'
                $af = New-Text $l.After 12.5 $(if ($revert) { 'Ink' } else { 'Green' }) 'SemiBold'
                foreach ($x in $b4, $ar, $af) { [void]$vg.Children.Add($x) }
            }
            [void]$sp.Children.Add($vg)
            $li.Child = $sp
            [void]$d.Children.Add($li); $shown++
        }
        if (-not $diff) { [void]$d.Children.Add((New-Text 'Nada que cambiar en este equipo.' 13 'Muted')) }
        Start-FadeIn $d
    }

    # ---------- Sistema
    [void]$ui.ToolGrid.Children.Add((New-Ruled))
    for ($k = 0; $k -lt $ToolDefs.Count; $k++) {
        $td = $ToolDefs[$k]
        $btn = New-Btn $td.Button; $btn.Tag = $k
        if ($td.Admin -and -not $script:IsAdmin) { $btn.IsEnabled = $false; $btn.ToolTip = T 'Necesita permisos de administrador' }
        $btn.Add_Click({
            param($src, $e)
            $def = $ToolDefs[[int]$src.Tag]
            Set-Busy $true
            try { & $def.Action } catch { Write-Log "$($def.Name): $($_.Exception.Message)" 'ERROR' } finally { Set-Busy $false }
        })
        [void]$ui.ToolGrid.Children.Add((New-ActionRow $td.Icon $td.Name $td.Desc $btn))
    }

    # ---------- monitor en vivo (en segundo plano para no congelar la ventana)
    $script:Telemetry = [hashtable]::Synchronized(@{ Stop = $false })
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open(); $rs.SessionStateProxy.SetVariable('T', $script:Telemetry)
    $script:TelePs = [powershell]::Create(); $script:TelePs.Runspace = $rs
    [void]$script:TelePs.AddScript({
        while (-not $T.Stop) {
            try {
                $o = Get-CimInstance Win32_OperatingSystem
                $T.RamTotal = $o.TotalVisibleMemorySize * 1KB; $T.RamUsed = ($o.TotalVisibleMemorySize - $o.FreePhysicalMemory) * 1KB
                $T.Cpu = [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
                $g = (Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue |
                      Where-Object Name -like '*engtype_3D' | Measure-Object UtilizationPercentage -Sum).Sum
                $T.Gpu = [math]::Min(100, [double]$g)
                $T.Proc = (Get-Process).Count
                $T.Svc = @(Get-Service -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running').Count
                $tz = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | Select-Object -First 1
                $T.Temp = if ($tz) { [math]::Round($tz.CurrentTemperature / 10 - 273.15) } else { $null }
                $T.Ready = $true
            }
            catch {}
            Start-Sleep -Milliseconds 1500
        }
    })
    [void]$script:TelePs.BeginInvoke()
    $window.Add_Closed({ $script:Telemetry.Stop = $true })
    # no cerrar con el booster activo sin avisar: los servicios pausados se quedarían así
    $window.Add_Closing({
        param($src, $e)
        # al cambiar de idioma no se pregunta: el booster sigue activo y la ventana nueva lo lee de boost.json
        if (-not $script:Relaunch -and $script:BoostFile -and (Test-Path $script:BoostFile) -and $script:IsAdmin) {
            $r = [Windows.MessageBox]::Show($window, (T "El Game Booster sigue activo: hay servicios pausados y apps cerradas.`n`n¿Restaurarlo todo antes de salir?"), 'OptiEleven', 'YesNoCancel', 'Warning')
            if ($r -eq 'Cancel') { $e.Cancel = $true }
            elseif ($r -eq 'Yes') { try { Stop-Boost } catch { Write-Log "Booster: $($_.Exception.Message)" 'ERROR' } }
        }
    })

    $script:Stats = [ordered]@{}
    $StatColors = @{ Cpu = 'Cat-Privacidad'; Gpu = 'Cat-Juegos'; Ram = 'Cat-Latencia'; Temp = 'Cat-Rendimiento'; Proc = 'Ink'; Svc = 'Ink'; Tweaks = 'Accent' }
    foreach ($s in @(@('Cpu', 'CPU'), @('Gpu', 'GPU'), @('Ram', 'RAM'), @('Temp', 'Temperatura'), @('Proc', 'Procesos'), @('Svc', 'Servicios'), @('Tweaks', 'Ajustes aplicados'))) {
        $l = New-Text $s[1] 12.5 'Muted'; $l.Margin = '0,0,6,0'; $l.VerticalAlignment = 'Center'
        $v = New-Mono '--' 13 $StatColors[$s[0]]; $v.FontWeight = 'SemiBold'; $v.Margin = '0,0,22,0'; $v.VerticalAlignment = 'Center'
        [void]$ui.StatList.Children.Add($l); [void]$ui.StatList.Children.Add($v)
        $script:Stats[$s[0]] = $v
        if ($s[0] -in 'Proc', 'Svc') { $script:ProOnly += $l, $v }   # en la vista sencilla sobran
    }
    $script:Stats.Temp.ToolTip = T 'Windows solo da la temperatura con permisos de administrador, y no en todos los equipos.'
    $updateStats = {
        $T = $script:Telemetry
        if (-not $T.Ready) { return }
        $script:Stats.Cpu.Text = (T '{0:N0} %') -f $T.Cpu
        $script:Stats.Gpu.Text = (T '{0:N0} %') -f $T.Gpu
        $script:Stats.Ram.Text = (T '{0:N1} / {1:N0} GB') -f ($T.RamUsed / 1GB), ($T.RamTotal / 1GB)
        $script:Stats.Temp.Text = if ($null -ne $T.Temp) { "$($T.Temp) °C" } else { T 'n/d' }
        $script:Stats.Proc.Text = (T "$($T.Proc)")
        $script:Stats.Svc.Text = (T "$($T.Svc)")
    }
    $timer = New-Timer 1.5 $updateStats

    # ---------- estado y hoja de cambios
    $script:Busy = $false
    function Get-Pending { @($script:Rows.Values | Where-Object { $null -ne $_.Applied -and ([bool]$_.Switch.IsChecked -ne $_.Applied) }) }
    function Update-Pending {
        $applied = 0
        foreach ($row in $script:Rows.Values) {
            if ($null -eq $row.Applied) { Set-Chip $row.State 'No disponible' 'Paper3' 'Muted'; $row.Mark.Visibility = 'Hidden'; continue }
            if ($row.Applied) { $applied++ }
            $want = [bool]$row.Switch.IsChecked
            if ($want -ne $row.Applied) {
                Set-Chip $row.State $(if ($want) { 'Se aplicará' } else { 'Se revertirá' }) 'Accent' 'AccentInk'
                $row.Mark.Visibility = 'Visible'
            }
            else {
                if ($row.Applied) { Set-Chip $row.State 'Aplicado' 'GreenSoft' 'Green' } else { Set-Chip $row.State $null $null $null }
                $row.Mark.Visibility = 'Hidden'
            }
        }
        $script:Stats.Tweaks.Text = T "$applied de $($script:Rows.Count)"
        $pend = Get-Pending
        $na = @($pend | Where-Object { $_.Switch.IsChecked }).Count; $nr = $pend.Count - $na
        $ui.LedgerCount.Text = (T "$($pend.Count)"); $ui.LedgerApply.Text = (T "$na"); $ui.LedgerRevert.Text = (T "$nr")
        $ui.LedgerReboot.Text = T $(if ($pend | Where-Object { $_.Tweak.Reboot }) { 'sí' } else { 'no' })
        $ui.QueueText.Text = (T "$($pend.Count)")
        $ui.QueuePill.SetResourceReference($BgProp, $(if ($pend.Count) { 'Accent' } else { 'Paper3' }))
        $ui.QueueText.SetResourceReference($FgProp, $(if ($pend.Count) { 'AccentInk' } else { 'Ink2' }))
        $ui.LedgerList.Children.Clear()
        if ($pend.Count -eq 0) {
            $ui.LedgerSub.Text = T 'Nada pendiente'
            $e = New-Text 'Mueve un interruptor o elige un preset.' 13 'Muted'; $e.Margin = '2,2,2,0'
            [void]$ui.LedgerList.Children.Add($e)
        }
        else {
            $ui.LedgerSub.Text = T $(if ($pend.Count -eq 1) { '1 cambio por aplicar' } else { "$($pend.Count) cambios por aplicar" })
            foreach ($row in $pend) {
                $li = New-Cols @('22', '*'); $li.Margin = '0,0,0,4'
                $sym = New-Icon $(if ($row.Switch.IsChecked) { 'plus' } else { 'arrow-counter-clockwise' }) 13 'Ink'; $sym.VerticalAlignment = 'Top'; $sym.Margin = '0,3,0,0'
                [void](Add-At $li $sym 0)
                $nm = New-Text $row.Tweak.Name 13 'Ink'; $nm.TextTrimming = 'CharacterEllipsis'; $nm.TextWrapping = 'NoWrap'
                [void](Add-At $li $nm 1)
                [void]$ui.LedgerList.Children.Add($li)
            }
        }
        if (-not $script:IsAdmin) { $ui.LedgerSub.Text = T 'Solo lectura' }
        $ui.BtnApply.IsEnabled = $script:IsAdmin -and $pend.Count -gt 0 -and -not $script:Busy
        $ui.BtnDiscard.IsEnabled = $pend.Count -gt 0 -and -not $script:Busy
    }
    function Update-Status {
        $ui.LedgerSub.Text = T 'Comprobando el estado...'; Update-Ui
        $script:AppxNames = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object Name)
        $i = 0
        foreach ($row in @($script:Rows.Values)) {
            $row.Applied = try { Test-Tweak $row.Tweak } catch { $null }
            if ((++$i % 4) -eq 0) { Update-Ui }   # la ventana sigue respondiendo mientras comprueba
            if ($null -eq $row.Applied) { $row.Switch.IsEnabled = $false }
            else { $row.Switch.IsEnabled = -not $script:Busy; $row.Switch.IsChecked = [bool]$row.Applied }
        }
        Update-Pending
        Show-Detail $script:Selected
    }
    function Set-Busy([bool]$Busy) {
        $script:Busy = $Busy
        foreach ($b in $ui.BtnRec, $ui.BtnComp) { $b.IsEnabled = -not $Busy }
        foreach ($row in $script:Rows.Values) { $row.Switch.IsEnabled = (-not $Busy) -and ($null -ne $row.Applied) }
        $ui.ModuleHost.IsEnabled = -not $Busy
        $ui.ToolGrid.IsEnabled = -not $Busy
        $window.Cursor = if ($Busy) { [Windows.Input.Cursors]::Wait } else { $null }
        if ($Busy) { $ui.LedgerSub.Text = T 'Trabajando...'; $ui.BtnApply.IsEnabled = $false; $ui.BtnDiscard.IsEnabled = $false }
        else { Update-Pending }
        Update-Ui
    }

    # ---------- páginas
    $script:ModuleCache = @{}
    function Select-NavKey([string]$Key) {
        if ($Pages.Contains($Key) -and $Pages[$Key].Tab -and $Key -ne 'all') { Select-NavKey 'all'; Show-Page $Key; return }
        foreach ($it in $ui.Nav.Items) { if ($it -is [Windows.Controls.Grid] -and $it.Tag -eq $Key) { $ui.Nav.SelectedItem = $it; return } }
    }
    function Show-Page([string]$Key) {
        $pg = $Pages[$Key]; $script:CurrentPage = $Key
        $ui.PageTitle.Text = (T $pg.Title); $ui.PageDesc.Text = (T $pg.Desc)
        $isModule = [bool]$pg.Module
        $isTweaks = [bool]$pg.Tab
        $ui.TweakPage.Visibility  = if ($isTweaks) { 'Visible' } else { 'Collapsed' }
        $ui.ToolsPage.Visibility  = if ($Key -eq 'tools') { 'Visible' } else { 'Collapsed' }
        $ui.LogPage.Visibility    = if ($Key -eq 'log') { 'Visible' } else { 'Collapsed' }
        $ui.ModulePage.Visibility = if ($isModule) { 'Visible' } else { 'Collapsed' }
        $ui.PresetBar.Visibility  = if ($isTweaks) { 'Visible' } else { 'Collapsed' }
        $ui.TabScroll.Visibility  = if ($isTweaks) { 'Visible' } else { 'Collapsed' }
        $ui.Rail.Visibility       = if ($isTweaks) { 'Visible' } else { 'Collapsed' }
        if ($isTweaks) {
            Update-Tabs $Key
            foreach ($cat in $script:GroupHeads.Keys) {
                $vis = if ($Key -eq 'all') { 'Visible' } else { 'Collapsed' }
                $script:GroupHeads[$cat][0].Visibility = $vis
                $script:GroupHeads[$cat][1].Visibility = if ($Key -eq 'all' -or $cat -eq $Key) { 'Visible' } else { 'Collapsed' }
            }
            foreach ($row in $script:Rows.Values) { $row.Border.Visibility = if ($Key -eq 'all' -or $row.Tweak.Cat -eq $Key) { 'Visible' } else { 'Collapsed' } }
            $ui.TweakPage.ScrollToTop()
            # no se elige nada solo: el panel derecho explica qué hacer hasta que tocas un ajuste
            if ($script:Selected -and $script:Selected.Border.Visibility -ne 'Visible') { Select-Row $null }
        }
        if ($isModule) {
            if (-not $script:ModuleCache.ContainsKey($Key)) {
                $ui.ModuleHost.Content = (New-Text 'Cargando...' 14 'Muted'); Update-Ui
                try { $script:ModuleCache[$Key] = & $pg.Module }
                catch {
                    Write-Log "$($pg.Title): $($_.Exception.Message) (línea $($_.InvocationInfo.ScriptLineNumber))" 'ERROR'
                    $script:ModuleCache[$Key] = New-Text "No se pudo cargar este apartado: $($_.Exception.Message)" 14 'Red'
                }
            }
            $ui.ModuleHost.Content = $script:ModuleCache[$Key]
            $ui.ModulePage.ScrollToTop()
            Start-FadeIn $ui.ModuleHost
            if ($Key -eq 'm-clean' -and $script:CleanFirstScan) {
                $script:CleanFirstScan = $false
                # el análisis bloquea unos segundos: si el panel aún está arrancando, se hace al terminar de comprobar los ajustes
                if ($script:StatusReady) { [void]$window.Dispatcher.BeginInvoke([Action] { Invoke-CleanScan }, [System.Windows.Threading.DispatcherPriority]::Background) }
                else { $script:CleanPending = $true }
            }
        }
    }
    $ui.Nav.Add_SelectionChanged({ Update-NavColors; if ($ui.Nav.SelectedItem) { Show-Page $ui.Nav.SelectedItem.Tag } })

    function Select-Preset([string]$Code, [string]$Label) {
        $n = 0
        foreach ($row in $script:Rows.Values) {
            if ($null -ne $row.Applied -and $row.Tweak.Presets -contains $Code -and -not $row.Switch.IsChecked) { $row.Switch.IsChecked = $true; $n++ }
        }
        Select-NavKey 'all'; Show-Page 'all'
        Update-Pending
        Write-Log "Preset ${Label}: $n ajuste(s) nuevos en la hoja de cambios."
    }
    $ui.BtnRec.Add_Click({ Select-Preset 'R' 'Recomendado' })
    $ui.BtnComp.Add_Click({ Select-Preset 'A' 'Avanzado' })
    $ui.BtnDiscard.Add_Click({ foreach ($row in $script:Rows.Values) { if ($null -ne $row.Applied) { $row.Switch.IsChecked = $row.Applied } }; Update-Pending })

    $ui.BtnApply.Add_Click({
        $pend = Get-Pending
        if (-not $pend) { return }
        $toApply = @($pend | Where-Object { $_.Switch.IsChecked } | ForEach-Object { $_.Tweak })
        $toRevert = @($pend | Where-Object { -not $_.Switch.IsChecked } | ForEach-Object { $_.Tweak })
        $msg = "Se van a aplicar $($toApply.Count) ajuste(s) y revertir $($toRevert.Count)."
        $irr = @($toApply | Where-Object Irreversible)
        if ($irr) { $msg += "`n`nSin vuelta atrás desde el panel: " + (($irr | ForEach-Object { T $_.Name }) -join ', ') + '.' }
        $msg += "`n`n¿Crear antes un punto de restauración? (recomendado)"
        $ans = [Windows.MessageBox]::Show($window, (T $msg), 'OptiEleven', 'YesNoCancel', 'Question')
        if ($ans -eq 'Cancel') { return }
        Set-Busy $true
        $reboot = $false
        try {
            if ($ans -eq 'Yes') { [void](New-RestorePoint) }
            if ($toApply)  { if (Invoke-Tweaks $toApply 'Apply')  { $reboot = $true } }
            if ($toRevert) { if (Invoke-Tweaks $toRevert 'Revert') { $reboot = $true } }
        }
        finally { Set-Busy $false; Update-Status }
        if ($reboot) { [void][Windows.MessageBox]::Show($window, (T 'Algunos cambios necesitan reiniciar el equipo.'), 'OptiEleven', 'OK', 'Information') }
    })

    # ---------- Vista Pro
    function Update-ProNav {
        # la Actividad es para la Vista Pro; se oculta el contenedor del ListBox, no solo su contenido
        foreach ($it in $ui.Nav.Items) {
            if ($it -is [Windows.Controls.Grid] -and $it.Tag -eq 'log') {
                $v = if ($script:Pro) { 'Visible' } else { 'Collapsed' }
                $it.Visibility = $v
                $c = $ui.Nav.ItemContainerGenerator.ContainerFromItem($it); if ($c) { $c.Visibility = $v }
            }
        }
    }    function Set-ProView([bool]$On) {
        $script:Pro = $On
        try { if ($On) { Set-Content -LiteralPath $script:ProFile -Value 'on' } else { Remove-Item -LiteralPath $script:ProFile -ErrorAction SilentlyContinue } } catch {}
        $vis = if ($On) { 'Visible' } else { 'Collapsed' }
        foreach ($row in $script:Rows.Values) { $row.Desc.Visibility = $vis }
        foreach ($el in $script:ProOnly) { $el.Visibility = $vis }
        $ui.LedgerStats.Visibility = $vis
        Update-ProNav
        Set-IconBrush $ui.ProIcon.Content $(if ($On) { 'Accent' } else { 'Ink2' })
        if ($ui.ProSwitch.IsChecked -ne $On) { $ui.ProSwitch.IsChecked = $On }
        # los apartados se vuelven a montar con o sin detalles
        $script:ModuleCache = @{}
        if (-not $On -and $script:CurrentPage -eq 'log') { Select-NavKey 'all'; return }
        if ($script:CurrentPage) { Show-Page $script:CurrentPage }
        Show-Detail $script:Selected
    }
    $ui.ProIcon.Content = (New-Icon 'brackets-curly' 18 'Ink2')
    $ui.ProSwitch.Add_Click({ Set-ProView ([bool]$ui.ProSwitch.IsChecked) })
    $ui.ProRow.Add_MouseLeftButtonUp({ param($src, $e) if ($e.OriginalSource -isnot [Windows.Controls.Primitives.ToggleButton] -and -not ($e.OriginalSource -is [Windows.FrameworkElement] -and $e.OriginalSource.TemplatedParent -is [Windows.Controls.Primitives.ToggleButton])) { Set-ProView (-not $script:Pro) } })
    $ui.ProSwitch.IsChecked = $script:Pro
    $vis0 = if ($script:Pro) { 'Visible' } else { 'Collapsed' }
    foreach ($el in $script:ProOnly) { $el.Visibility = $vis0 }
    $ui.LedgerStats.Visibility = $vis0
    $window.Add_ContentRendered({ Update-ProNav })
    if ($script:Pro) { Set-IconBrush $ui.ProIcon.Content 'Accent' }

    # ---------- arranque
    $ui.BtnApply.IsEnabled = $false; $ui.BtnDiscard.IsEnabled = $false
    Update-Pending
    Select-NavKey $Page
    if (-not $ui.Nav.SelectedItem) { Select-NavKey 'all' }

    $window.Add_ContentRendered({
        $timer.Start(); & $updateStats
        Update-Status
        $script:StatusReady = $true
        if ($script:CleanPending) { $script:CleanPending = $false; Invoke-CleanScan }
        Write-Log ("Panel listo. {0} ajustes. Copias de seguridad en {1}" -f $Tweaks.Count, $script:Root)
        if (-not $script:IsAdmin) { Write-Log 'Sin permisos de administrador: solo se muestra el estado.' 'WARN' }
    })
    [void]$window.ShowDialog()
    $script:Telemetry.Stop = $true
    # cambio de idioma: se abre de nuevo en el mismo apartado (si el cierre se canceló, la ventana sigue abierta y no se llega aquí)
    if ($script:Relaunch) { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-Page', $script:Relaunch) }
}
catch {
    $script:LogBox = $null
    Write-Log "Error al iniciar el panel: $($_.Exception.Message) | $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim()) | $($_.ScriptStackTrace -replace "`r?`n", ' <- ')" 'ERROR'
    [void][System.Windows.MessageBox]::Show((T 'Error al iniciar el panel:') + "`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)", 'OptiEleven', 'OK', 'Error')
}
