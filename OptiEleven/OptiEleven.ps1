#Requires -Version 5.1
<#
  OptiEleven - reversible optimizations for Windows 11
  - Each tweak saves the original state the first time it is applied
    (%ProgramData%\OptiEleven\secure\backup.json) and "Revert" restores it.
  - Usage:
      .\OptiEleven.ps1                          -> opens the panel
      .\OptiEleven.ps1 -Page cleanup            -> opens a section directly (the id in its tool.json: install, startup, cleanup, network, hardware, tools...)
      .\OptiEleven.ps1 -Status                  -> shows the state of each tweak (changes nothing)
      .\OptiEleven.ps1 -Preset Recomendado -NoGui  -> applies a preset without the UI (needs admin)
      .\OptiEleven.ps1 -Config profile.json -NoGui -> applies a profile exported from the panel (needs admin)
#>
param(
    [ValidateSet('Recomendado', 'Avanzado', 'Competitivo')] [string]$Preset,
    [string]$Config,
    [string]$Page = 'home',
    [switch]$NoGui,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
$script:Root       = Join-Path $env:ProgramData 'OptiEleven'
# What the elevated panel reads and uses to change the system (backups, booster state) goes in a folder that
# only Administrators and SYSTEM can write; otherwise an unprivileged program could edit it and get
# the panel to write whatever it wants to the registry on "revert".
$script:Secure     = Join-Path $script:Root 'secure'
$script:BackupFile = Join-Path $script:Secure 'backup.json'
$script:LogFile    = Join-Path $script:Root 'panel.log'
$script:IsAdmin    = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$script:LogBox     = $null
try { if (-not (Test-Path $script:Root)) { New-Item -ItemType Directory -Path $script:Root -Force | Out-Null } } catch {}
function Protect-Folder([string]$Path) {
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)   # no permissions inherited from ProgramData
    $inh = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [System.Security.AccessControl.PropagationFlags]::None
    foreach ($r in @(@('S-1-5-32-544', 'FullControl'), @('S-1-5-18', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
        $sid = New-Object System.Security.Principal.SecurityIdentifier $r[0]
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $sid, $r[1], $inh, $none, 'Allow'))
    }
    $acl.SetOwner((New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
    Set-Acl -LiteralPath $Path -AclObject $acl
}
# data from when the panel was called Gaming Panel: theme, added games and (with admin) the backups
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
        # backups from older versions of the panel, which were in the open folder
        $oldBk = Join-Path $script:Root 'backup.json'
        if ((Test-Path $oldBk) -and -not (Test-Path $script:BackupFile)) { Move-Item -LiteralPath $oldBk -Destination $script:BackupFile }
    }
    catch {}
}

# Native calls (power, dark title bar, memory). Compiling C# with Add-Type costs ~300 ms every time,
# so it is compiled once to a DLL and later runs only load it. With administrator rights the
# DLL lives in the secure folder (in a user folder, another program could change it and the elevated panel
# would load it); without them, in the user's folder, which grants no more rights than the user already has.
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
    public static class Shell {
        // own taskbar identity: without it, Windows groups the window with PowerShell and shows its icon
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    }
    // Disk space (like WinDirStat): full folder tree with sizes, the large files in each folder and a
    // summary by extension. FindFirstFileEx with "large fetch" (the same as WinDirStat) and one top-level
    // folder per core in parallel. The window reads the counters live.
    public class DNode {
        public string Name; public string Path; public long Size; public long Files; public long LastWrite;
        public bool IsFile; public bool IsRest; public DNode Parent;
        public System.Collections.Generic.List<DNode> Kids;
    }
    public class DExt { public string Ext; public long Size; public long Count; }
    public static class DiskScan {
        public static long Files, Bytes; public static string Current = ""; public static volatile bool Cancel;
        const int KeepFiles = 40;   // files kept per folder; the rest are added up in a single row

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 4)]
        struct FindData {
            public uint Attr; public long Created, Accessed, Written; public uint SizeHigh, SizeLow, R0, R1;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string Alt;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr FindFirstFileExW(string name, int level, out FindData data, int op, IntPtr filter, int flags);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool FindNextFileW(IntPtr h, out FindData data);
        [DllImport("kernel32.dll")] static extern bool FindClose(IntPtr h);

        class Ctx { public System.Collections.Generic.Dictionary<string, long[]> Ext = new System.Collections.Generic.Dictionary<string, long[]>(System.StringComparer.OrdinalIgnoreCase); }

        static void Walk(DNode dir, Ctx ctx) {
            if (Cancel) return;
            Current = dir.Path;
            var files = new System.Collections.Generic.List<DNode>();
            FindData fd; long dirBytes = 0, dirFiles = 0;
            string pattern = (dir.Path.StartsWith(@"\\") ? dir.Path : @"\\?\" + dir.Path).TrimEnd('\\') + @"\*";
            IntPtr h = FindFirstFileExW(pattern, 1, out fd, 0, IntPtr.Zero, 2);
            if (h != new IntPtr(-1)) {
                try {
                    do {
                        if (fd.Name == "." || fd.Name == "..") continue;
                        if ((fd.Attr & 0x10) != 0) {
                            if ((fd.Attr & 0x400) != 0) continue;   // junctions and links: don't count twice
                            var sub = new DNode { Name = fd.Name, Path = dir.Path.TrimEnd('\\') + "\\" + fd.Name, LastWrite = fd.Written, Parent = dir, Kids = new System.Collections.Generic.List<DNode>() };
                            dir.Kids.Add(sub);
                        } else {
                            long len = ((long)fd.SizeHigh << 32) | fd.SizeLow;
                            files.Add(new DNode { Name = fd.Name, Size = len, Files = 1, LastWrite = fd.Written, IsFile = true, Parent = dir });
                            dirBytes += len; dirFiles++;
                            int dot = fd.Name.LastIndexOf('.'); string ext = dot > 0 ? fd.Name.Substring(dot).ToLowerInvariant() : "";
                            long[] e; if (!ctx.Ext.TryGetValue(ext, out e)) { e = new long[2]; ctx.Ext[ext] = e; } e[0] += len; e[1]++;
                        }
                    } while (FindNextFileW(h, out fd));
                } finally { FindClose(h); }
            }
            System.Threading.Interlocked.Add(ref Files, dirFiles); System.Threading.Interlocked.Add(ref Bytes, dirBytes);
            foreach (var sub in dir.Kids) { if (Cancel) return; Walk(sub, ctx); dirBytes += sub.Size; dirFiles += sub.Files; }
            // only the large files of each folder get rows; the rest are added up in one ("and 1,234 more files")
            files.Sort((a, b) => b.Size.CompareTo(a.Size));
            if (files.Count > KeepFiles) {
                long rs = 0; for (int i = KeepFiles; i < files.Count; i++) rs += files[i].Size;
                var rest = new DNode { Name = "", Size = rs, Files = files.Count - KeepFiles, IsFile = true, IsRest = true, Parent = dir };
                files.RemoveRange(KeepFiles, files.Count - KeepFiles); files.Add(rest);
            }
            dir.Kids.AddRange(files);
            dir.Kids.Sort((a, b) => b.Size.CompareTo(a.Size));
            dir.Size = dirBytes; dir.Files = dirFiles;
        }

        // returns { DNode root, DExt[] extensions from largest to smallest }
        public static object[] Scan(string root) {
            Files = 0; Bytes = 0; Cancel = false;
            var top = new DNode { Name = root, Path = root.TrimEnd('\\') + (root.EndsWith(":\\") || root.EndsWith(":") ? "\\" : ""), Kids = new System.Collections.Generic.List<DNode>() };
            if (top.Path.EndsWith(":\\") == false) top.Path = root.TrimEnd('\\');
            // top level in series; each top-level folder on its own thread
            var main = new Ctx();
            FindData fd; var dirs = new System.Collections.Generic.List<DNode>(); var looseFiles = new System.Collections.Generic.List<DNode>(); long lb = 0, lf = 0;
            IntPtr h = FindFirstFileExW((top.Path.StartsWith(@"\\") ? top.Path : @"\\?\" + top.Path).TrimEnd('\\') + @"\*", 1, out fd, 0, IntPtr.Zero, 2);
            if (h != new IntPtr(-1)) {
                try {
                    do {
                        if (fd.Name == "." || fd.Name == "..") continue;
                        if ((fd.Attr & 0x10) != 0) { if ((fd.Attr & 0x400) == 0) dirs.Add(new DNode { Name = fd.Name, Path = top.Path.TrimEnd('\\') + "\\" + fd.Name, LastWrite = fd.Written, Parent = top, Kids = new System.Collections.Generic.List<DNode>() }); }
                        else {
                            long len = ((long)fd.SizeHigh << 32) | fd.SizeLow; lb += len; lf++;
                            looseFiles.Add(new DNode { Name = fd.Name, Size = len, Files = 1, LastWrite = fd.Written, IsFile = true, Parent = top });
                            int dot = fd.Name.LastIndexOf('.'); string ext = dot > 0 ? fd.Name.Substring(dot).ToLowerInvariant() : "";
                            long[] e; if (!main.Ext.TryGetValue(ext, out e)) { e = new long[2]; main.Ext[ext] = e; } e[0] += len; e[1]++;
                        }
                    } while (FindNextFileW(h, out fd));
                } finally { FindClose(h); }
            }
            System.Threading.Interlocked.Add(ref Files, lf); System.Threading.Interlocked.Add(ref Bytes, lb);
            var ctxs = new System.Collections.Concurrent.ConcurrentBag<Ctx>();
            System.Threading.Tasks.Parallel.ForEach(dirs, new System.Threading.Tasks.ParallelOptions { MaxDegreeOfParallelism = System.Math.Max(2, System.Environment.ProcessorCount) },
                () => new Ctx(), (d, state, ctx) => { Walk(d, ctx); return ctx; }, ctx => ctxs.Add(ctx));
            top.Kids.AddRange(dirs); top.Kids.AddRange(looseFiles);
            long total = lb, count = lf; foreach (var d in dirs) { total += d.Size; count += d.Files; }
            top.Kids.Sort((a, b) => b.Size.CompareTo(a.Size));
            top.Size = total; top.Files = count;
            // extensions from all threads merged
            foreach (var c in ctxs) foreach (var kv in c.Ext) { long[] e; if (!main.Ext.TryGetValue(kv.Key, out e)) { e = new long[2]; main.Ext[kv.Key] = e; } e[0] += kv.Value[0]; e[1] += kv.Value[1]; }
            var exts = new System.Collections.Generic.List<DExt>();
            foreach (var kv in main.Ext) exts.Add(new DExt { Ext = kv.Key, Size = kv.Value[0], Count = kv.Value[1] });
            exts.Sort((a, b) => b.Size.CompareTo(a.Size));
            return new object[] { top, exts.ToArray() };
        }
    }    public static class Ws {
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
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($GpSource))[0..5] | ForEach-Object { $_.ToString('x2') })
    # release build: the DLL comes precompiled (build\Build.ps1) next to the scripts, in a folder with the same
    # permissions as them. Its "Comments" holds the hash of $GpSource; if it doesn't match (code edited by hand), it is compiled.
    $shipped = Join-Path $PSScriptRoot 'native\OptiEleven.Native.dll'
    if ((Test-Path -LiteralPath $shipped) -and [Diagnostics.FileVersionInfo]::GetVersionInfo($shipped).Comments -eq $hash) {
        try { Add-Type -LiteralPath $shipped; $loaded = $true } catch {}
    }
    if (-not $loaded) { try {
        $cacheDir = if ($script:IsAdmin) { $script:Secure } else { Join-Path $env:LOCALAPPDATA 'OptiEleven\cache' }
        $dll = Join-Path $cacheDir "native-$hash.dll"
        if (-not (Test-Path -LiteralPath $dll)) {
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
            Add-Type -TypeDefinition $GpSource -OutputAssembly $dll -OutputType Library
        }
        Add-Type -LiteralPath $dll; $loaded = $true
    }
    catch {} }
    if (-not $loaded -and -not ('GP.PowerOverlay' -as [type])) { Add-Type -TypeDefinition $GpSource }
}

# ============================================================ utilities
function Update-Ui {
    if (-not $script:LogBox) { return }
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; $null }, $frame)
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

# ---------- languages
# The panel's texts are written in Spanish; lang\<code>.json provides the translation:
#   "strings":  exact text -> translation
#   "patterns": [regex, replacement]; in the replacement $1 copies the group as is and @1 translates it too.
# To add a language, copy en.json under another code (fr.json...) and translate the values.
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
    # JavaScriptSerializer is case-sensitive ("Instalada" and "instalada" are separate entries), PS 5.1's ConvertFrom-Json is not
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

# ---------- registry
function RegV([string]$Path, [string]$Name, $Value, [string]$Kind = 'DWord', $Default = $null) {
    # Default: Windows value to revert to when there is no backup (if not given, the value is deleted)
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

# ---------- services
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
        # some services reject sc.exe: try through the registry
        try { Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name Start -Value $Start -Type DWord }
        catch { throw "No se pudo cambiar el servicio $Name ($out)" }
    }
    if ($Start -eq 4) { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
}

# ---------- scheduled tasks
function Split-TaskPath([string]$Full) { $i = $Full.LastIndexOf('\'); @($Full.Substring(0, $i + 1), $Full.Substring($i + 1)) }
function Get-TaskState([string]$Full) {
    # Task Scheduler COM API: ~1 ms per task (Get-ScheduledTask takes ~650 ms)
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

# ---------- power
function Get-OverlayGuid { $g = [guid]::Empty; [void][GP.PowerOverlay]::PowerGetEffectiveOverlayScheme([ref]$g); $g.ToString() }
function Set-OverlayGuid([string]$g) {
    $r = [GP.PowerOverlay]::PowerSetActiveOverlayScheme([guid]$g)
    if ($r -ne 0) { throw "PowerSetActiveOverlayScheme devolvió $r" }
}
function Get-ActiveSchemeGuid { if ((powercfg /getactivescheme) -match '([0-9a-f]{8}-[0-9a-f-]{27})') { $Matches[1] } }

# ---------- backups
function Read-Store {
    if (Test-Path $script:BackupFile) { try { return (Get-Content $script:BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {} }
    [pscustomobject]@{}
}
$script:Store = Read-Store

# ---------- history: one JSON line per change (what, when, before and after). Shown by the History tool.
# It goes in the open folder because it is informational only: undo uses backup.json, which is in the secure one.
$script:HistoryFile = Join-Path $script:Root 'history.jsonl'
function Add-History([string]$Source, [string]$Action, [string]$Text = '', [string]$Id = '', [bool]$Ok = $true, $Changes = $null, [string]$Err = '', [string]$Time = '') {
    $e = [ordered]@{ time = $(if ($Time) { $Time } else { (Get-Date).ToString('s') }); source = $Source; action = $Action; id = $Id; text = $Text; ok = $Ok }
    if ($Err) { $e.error = $Err }
    if ($Changes) { $e.changes = @($Changes) }
    try { Add-Content -LiteralPath $script:HistoryFile -Value ($e | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8 } catch {}   # without write permission nothing is logged, but nothing stops
}
function Get-History {
    if (-not (Test-Path -LiteralPath $script:HistoryFile)) { return @() }
    @(Get-Content -LiteralPath $script:HistoryFile -Encoding UTF8 | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
}
function Write-Store { $script:Store | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:BackupFile -Encoding UTF8 }
function Get-Backup([string]$Id) { $p = $script:Store.PSObject.Properties[$Id]; if ($p) { $p.Value } else { $null } }
function Save-Backup([string]$Id, $Bk) { $script:Store | Add-Member -NotePropertyName $Id -NotePropertyValue $Bk -Force; Write-Store }
function Remove-Backup([string]$Id) { $script:Store.PSObject.Properties.Remove($Id); Write-Store }

# reopens the panel: with OptiEleven.exe if it is next to it (the release), otherwise with powershell.exe (git checkout)
function Start-Panel([string]$Page, [switch]$Admin) {
    $exe = Join-Path $PSScriptRoot 'OptiEleven.exe'
    $verb = @{}; if ($Admin) { $verb.Verb = 'RunAs' }
    if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe -ArgumentList @('-Page', $Page) @verb -ErrorAction Stop }
    else { Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"", '-Page', $Page) @verb -ErrorAction Stop }
}
function Get-ToolText($Value) {
    # manifest texts: { "es": "...", "en": "..." } (or a plain string); if the language is missing, Spanish
    if ($null -eq $Value -or $Value -is [string]) { return [string]$Value }
    $x = $Value.$($script:LangCode); if (-not $x) { $x = $Value.es }
    [string]$x
}
# ============================================================ tweak catalog
# Risk: Seguro (safe) / Moderado (moderate) / Avanzado (advanced)
# Presets: R = Recomendado (removes almost all the junk, without breaking anything used daily)
#          A = Avanzado (Recomendado + things worth understanding first). No preset: manual only.
# Ideas cross-checked with WinUtil (Chris Titus), Win11Debloat (Raphire), Optimizer (hellzerg) and Atlas OS.
$P   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$MM  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'

$DebloatApps = @(
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.WindowsFeedbackHub', 'Clipchamp.Clipchamp', 'Microsoft.Todos',
    'Microsoft.PowerAutomateDesktop', 'MSTeams', 'Microsoft.Copilot', 'Microsoft.MicrosoftOfficeHub',
    'Microsoft.OutlookForWindows', 'Microsoft.WindowsMaps', 'Microsoft.549981C3F5F10', 'Microsoft.People',
    'Microsoft.ZuneVideo', 'MicrosoftCorporationII.QuickAssist', 'Microsoft.Windows.DevHome',
    # more Microsoft apps that come preinstalled or arrive with updates
    'Microsoft.WindowsCommunicationsApps', 'Microsoft.SkypeApp', 'Microsoft.MixedReality.Portal', 'Microsoft.Microsoft3DViewer',
    'Microsoft.Print3D', 'Microsoft.MSPaint', 'Microsoft.Office.OneNote', 'Microsoft.Wallet', 'Microsoft.Messaging', 'Microsoft.OneConnect',
    'Microsoft.BingFinance', 'Microsoft.BingSports', 'Microsoft.BingTranslator', 'Microsoft.BingFoodAndDrink', 'Microsoft.BingHealthAndFitness',
    'Microsoft.BingTravel', 'Microsoft.News', 'MicrosoftCorporationII.MicrosoftFamily', 'Microsoft.Windows.Ai.Copilot.Provider',
    'MicrosoftWindows.Client.WebExperience', 'Microsoft.StartExperiencesApp', 'Microsoft.Edge.GameAssist',
    # sponsored apps Windows installs on its own (wildcards allowed)
    '*CandyCrush*', '*BubbleWitch*', '*FarmHeroes*', '*MarchofEmpires*', '*Facebook*', '*Instagram*', '*TikTok*', '*Twitter*',
    '*LinkedIn*', '*Disney*', '*Duolingo*', '*PicsArt*', '*Royal Revolt*', '*HiddenCity*', '*AdobePhotoshopExpress*', '*EclipseManager*'
)
function Get-DebloatPresent([string[]]$List) {
    # names from the list that are still installed (with wildcards)
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



# ---------- Advanced latency (ideas from Hone, Atlas and the latency forums)
# Single-value tweaks on the current power plan (plugged in / AC only). Reads the value with powercfg /query:
# the last two 0x... numbers in the output are the AC and DC index, in any language.
function Get-PowerAc([string]$Sub, [string]$Setting) {
    $hex = [regex]::Matches((powercfg /query SCHEME_CURRENT $Sub $Setting | Out-String), '0x([0-9a-fA-F]{8})')
    if ($hex.Count -ge 2) { return [Convert]::ToInt32($hex[$hex.Count - 2].Groups[1].Value, 16) }
    # hidden setting: powercfg doesn't show it; read it from the active plan or, if untouched, from the plan's default
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
# Power tweaks go to the active plan, but the backup remembers which plan they were made on: on revert they are
# restored on that plan (if it still exists) and on the active one, even if the plan changed in between.
function Restore-PowerAc([string]$Sub, [string]$Setting, [int]$Value, $Bk) {
    if ($Bk -and $Bk.Custom.Scheme -and $Bk.Custom.Scheme -ne (Get-ActiveSchemeGuid)) {
        powercfg /query $Bk.Custom.Scheme $Sub $Setting *> $null
        if ($LASTEXITCODE -eq 0) { Set-PowerAc $Sub $Setting $Value $Bk.Custom.Scheme }
    }
    Set-PowerAc $Sub $Setting $Value
}
# when switching plans (Ultimate), the applied power tweaks are copied to the new plan
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
# Network and GPU keys that depend on the machine
function Get-NicKeys {
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -ErrorAction SilentlyContinue | Where-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        ($p.DhcpIPAddress -and $p.DhcpIPAddress -ne '0.0.0.0') -or ($p.IPAddress -and "$($p.IPAddress)" -ne '0.0.0.0')
    } | ForEach-Object { $_.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE', 'HKLM:' }
}
function Get-GpuMsiKeys {
    # Win32_VideoController instead of Get-PnpDevice: loading the PnpDevice module takes over a second
    if ($null -eq $script:GpuPnpIds) {
        $script:GpuPnpIds = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object PNPDeviceID | Where-Object { $_ -like 'PCI\*' })
    }
    foreach ($id in $script:GpuPnpIds) { "HKLM:\SYSTEM\CurrentControlSet\Enum\$id\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" }
}
function New-DynRegCustom([string]$KeysFn, [string[]]$Names, [int]$Value) {
    # several DWORD values in keys found at run time (with $KeysFn); saves and restores each one.
    # The blocks are built as text so they can see the script's functions (a closure can't).
    $ns = '@(' + (($Names | ForEach-Object { "'$_'" }) -join ',') + ')'
    @{
        Backup = [scriptblock]::Create("`$out = @(); foreach (`$k in @($KeysFn)) { foreach (`$n in $ns) { `$out += Get-RegState @{ Path = `$k; Name = `$n } } }; @{ States = `$out }")
        Test   = [scriptblock]::Create("param(`$bk) `$ks = @($KeysFn); if (-not `$ks) { return `$null }; foreach (`$k in `$ks) { foreach (`$n in $ns) { if (-not (Test-Reg @{ Path = `$k; Name = `$n; Value = $Value })) { return `$false } } }; `$true")
        Apply  = [scriptblock]::Create("param(`$bk) foreach (`$k in @($KeysFn)) { foreach (`$n in $ns) { Set-RegValue `$k `$n $Value 'DWord' } }")
        Diff   = [scriptblock]::Create("param(`$bk, `$rev) foreach (`$k in @($KeysFn)) { foreach (`$n in $ns) { `$s = Get-RegState @{ Path = `$k; Name = `$n }; `$o = if (`$bk) { @(`$bk.Custom.States) | Where-Object { `$_.Path -eq `$k -and `$_.Name -eq `$n } | Select-Object -First 1 }; `$a = if (`$rev) { Format-RegState `$o } else { '$Value (DWord)' }; New-DiffLine 'reg' ((Get-ShortKey `$k) + '\' + `$n) (Format-RegState `$s) `$a } }")
        Revert = [scriptblock]::Create("param(`$bk) if (`$bk -and `$bk.Custom.States) { foreach (`$s in `$bk.Custom.States) { if (`$s.Exists) { Set-RegValue `$s.Path `$s.Name `$s.Value `$s.Kind } else { Remove-RegValue `$s.Path `$s.Name } } } else { foreach (`$k in @($KeysFn)) { foreach (`$n in $ns) { Remove-RegValue `$k `$n } } }")
    }
}



# ---------- more Windows 11 junk (what the well-known optimizers remove)
function Get-EdgeSetup {
    Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe", "$env:ProgramFiles\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
}
$EdgePol = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$XboxApps = @('Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxGameCallableUI')
$PhoneApps = @('Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice')
# old optional components: capability name and the file that shows whether it is still installed
$OldCapabilities = @(
    @{ Cap = 'App.StepsRecorder*';             File = "$env:SystemRoot\System32\psr.exe" }
    @{ Cap = 'Microsoft.Windows.WordPad*';     File = "$env:ProgramFiles\Windows NT\Accessories\wordpad.exe" }
    @{ Cap = 'Media.WindowsMediaPlayer*';      File = "$env:ProgramFiles\Windows Media Player\wmplayer.exe" }
    @{ Cap = 'MathRecognizer*';                File = "$env:CommonProgramFiles\Microsoft Shared\Ink\mip.exe" }
)

# Each tweak is tools\tweaks\<category>\<id>.tweak.json; if it needs its own code, <id>.tweak.ps1 next to it (set by "script").
# They are converted to the shape the engine uses (Reg / Svc / Task / Custom), so apply, test and revert don't change.
$TweakRisk = @{ safe = 'Seguro'; moderate = 'Moderado'; advanced = 'Avanzado' }
$TweakPresets = @{ recommended = 'R'; advanced = 'A'; competitive = 'C' }
function Import-Tweaks([string]$Dir) {
    $seen = @{}
    $list = foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter '*.tweak.json' -Recurse -ErrorAction SilentlyContinue) {
        try {
            $j = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $miss = @('id', 'kind', 'category', 'order', 'name', 'summary', 'risk', 'presets', 'reversible', 'undo', 'actions' | Where-Object { $null -eq $j.$_ })
            if ($miss.Count) { throw "faltan $($miss -join ', ')" }
            if (-not $TweakRisk.ContainsKey([string]$j.risk)) { throw "riesgo desconocido: $($j.risk)" }
            if ($seen.ContainsKey($j.id)) { throw "id repetido: $($j.id)" }
            $seen[$j.id] = $true
            $tw = @{ Id = $j.id; Cat = $j.category; Risk = $TweakRisk[[string]$j.risk]; Name = (Get-ToolText $j.name); Desc = (Get-ToolText $j.summary)
                     Presets = @($j.presets | ForEach-Object { $TweakPresets[[string]$_] }) }
            if ($j.details) { $tw.Detail = (Get-ToolText $j.details) }   # the long text, for "More info"
            if ($j.reboot) { $tw.Reboot = $true }
            if (-not $j.reversible) { $tw.Irreversible = $true }
            $reg = @($j.actions | Where-Object { $_.registry } | ForEach-Object { RegV $_.registry $_.name $_.value $_.type $_.default })
            $svc = @($j.actions | Where-Object { $_.service } | ForEach-Object { SvcV $_.service $_.startup $_.default })
            $task = @($j.actions | Where-Object { $_.task } | ForEach-Object { [string]$_.task })
            if ($reg.Count) { $tw.Reg = $reg }
            if ($svc.Count) { $tw.Svc = $svc }
            if ($task.Count) { $tw.Task = $task }
            if ($j.script) { $tw.Custom = . (Join-Path $f.DirectoryName $j.script) }
            [pscustomobject]@{ Order = [int]$j.order; Tweak = $tw }
        } catch { Write-Log "Ajuste no cargado ($($f.Name)): $($_.Exception.Message)" 'WARN' }   # one broken tweak doesn't take down the rest
    }
    @($list | Sort-Object Order | ForEach-Object { $_.Tweak })
}
$Tweaks = Import-Tweaks (Join-Path $PSScriptRoot 'tools\tweaks')

# what was applied with v1 is already in backup.json (same file and format), so it can be undone the same way;
# the first time it is also added to the history, with the date it was applied
if ($script:Store -and -not (Test-Path -LiteralPath $script:HistoryFile)) {
    $known = @($Tweaks | ForEach-Object { $_.Id })
    foreach ($p in @($script:Store.PSObject.Properties | Where-Object { $known -contains $_.Name } | Sort-Object { [string]$_.Value.Time })) {
        Add-History 'tweak' 'apply' 'Aplicado con una versión anterior' $p.Name $true $null '' ([string]$p.Value.Time)
    }
}

# icon for each tweak (names from assets\icons.json)
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

# ---------- profiles (export / import the selection)
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

# ============================================================ engine
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
        if (-not $t.Irreversible) { Save-Backup $t.Id $bk }   # Apply may have saved data (e.g. the GUID it created)
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
        # no backup (applied outside the panel): go back to the Windows defaults
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
        $chg = $null
        try {
            if ($Mode -eq 'Apply') {
                if ((Test-Tweak $t) -eq $true) { Write-Log "Ya aplicado: $($t.Name)"; continue }
                Write-Log "Aplicando: $($t.Name)"
                $chg = Get-ChangeList $t $false
                Invoke-ApplyTweak $t
            }
            else {
                Write-Log "Revirtiendo: $($t.Name)"
                $chg = Get-ChangeList $t $true
                Invoke-RevertTweak $t
            }
            $ok++; if ($t.Reboot) { $reboot = $true }
            Add-History 'tweak' $Mode.ToLower() '' $t.Id $true $chg
        }
        catch { $fail++; Write-Log "$($t.Name): $($_.Exception.Message)" 'ERROR'; Add-History 'tweak' $Mode.ToLower() '' $t.Id $false $chg $_.Exception.Message }
    }
    Write-Log ("Terminado: {0} correctos, {1} con error." -f $ok, $fail) 'OK'
    return $reboot
}

# ============================================================ diff: exactly what each tweak touches
$StartNames = @{ 2 = 'auto'; 3 = 'manual'; 4 = 'disabled' }
function Format-RegState($s) { if (-not $s -or -not $s.Exists) { '(no existe)' } else { "$($s.Value) ($($s.Kind))" } }
function Format-SvcState($s) { if (-not $s) { '(no existe)' } elseif ($s.Start -eq 2 -and $s.Delayed) { 'auto (retrasado)' } else { $StartNames[[int]$s.Start] } }
function Get-ShortKey([string]$p) {
    $p -replace '^HKLM:\\SOFTWARE\\Policies\\Microsoft\\', 'HKLM\Policies\' -replace '^HKCU:\\Software\\Policies\\Microsoft\\', 'HKCU\Policies\' `
       -replace '^HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\', 'HKLM\...\CurrentVersion\' -replace '^HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\', 'HKCU\...\CurrentVersion\' `
       -replace '^HKLM:\\SYSTEM\\CurrentControlSet\\', 'HKLM\SYSTEM\CCS\' -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU'
}
# what will actually change, for the history (only the lines that change)
function Get-ChangeList($t, [bool]$Revert) {
    try { @(Get-TweakDiff $t $Revert | Where-Object { -not $_.Same } | ForEach-Object { [ordered]@{ what = $_.Target; before = $_.Before; after = $_.After } }) } catch { $null }
}
function New-DiffLine([string]$Kind, [string]$Target, [string]$Before, [string]$After) {
    [pscustomobject]@{ Kind = $Kind; Target = $Target; Before = $Before; After = $After; Same = ($Before -eq $After) }
}
# $Revert: $true = show what will happen on revert (from the backup or the Windows defaults)
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
        if (-not $cur) { continue }   # the service doesn't exist in this Windows version
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
    $arr = New-Object object[] $out.Count   # plain array: @() over List[object] fails in PowerShell 5.1
    for ($i = 0; $i -lt $out.Count; $i++) { $arr[$i] = $out[$i] }
    , $arr
}
# diffs of the custom tweaks
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

# ============================================================ no-UI modes
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
        $code = if ($Preset -eq 'Recomendado') { 'R' } else { 'A' }   # 'Competitivo' is accepted as the old name of Avanzado
        $list = @($Tweaks | Where-Object { $_.Presets -contains $code })
    }
    else { Write-Log 'Indica -Preset Recomendado|Avanzado o -Config perfil.json.' 'ERROR'; exit 1 }
    [void](New-RestorePoint)
    $r = Invoke-Tweaks $list 'Apply'
    if ($r) { Write-Log 'Reinicia el equipo para completar los cambios.' 'WARN' }
    exit 0
}

# ============================================================ UI
# Fluent design (Windows 11): Mica, Segoe UI Variable, Segoe Fluent Icons and a single teal accent, used sparingly.
# Each item's state shows in its control (toggle, chip, number); technical detail goes in "More info".
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing
if (-not ('GP.Dwm' -as [type])) {
    Add-Type -Namespace GP -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);'
}

# Fluent (Windows 11): neutral grays, a single teal accent and no gradients or glows.
# Each theme has its solid colors plus the Mica ones (translucent backgrounds), used when the window has Mica.
$Themes = @{
    Light = @{ Dark = $false; Paper = '#f3f3f3'; Side = '#f3f3f3'; Layer = '#f9f9f9'; LayerEdge = '#e5e5e5'; Paper2 = '#ffffff'; Paper3 = '#f0f0f0'
               Card = '#ffffff'; CardEdge = '#e5e5e5'; CardHover = '#f6f6f6'; Control = '#fbfbfb'; ControlEdge = '#d6d6d6'; ControlHover = '#f3f3f3'
               Subtle = '#0a000000'; Flyout = '#f9f9f9'; Disabled = '#a0a0a0'
               Ink = '#1a1a1a'; Ink2 = '#5c5c5c'; Muted = '#6e6e6e'; Rule = '#e5e5e5'; RuleStrong = '#d1d1d1'
               Accent = '#0d7a72'; AccentInk = '#ffffff'; AccentSoft = '#e1f1ef'; AccentEdge = '#0a6660'; AccentHover = '#1fffffff'; Accent2 = '#0d7a72'
               Glass = '#ffffff'; GlassEdge = '#e5e5e5'; GlassHi = '#f6f6f6'; Glow = '#00000000'; Glow2 = '#00000000'
               Green = '#0f7b0f'; GreenSoft = '#dff6dd'; Amber = '#9d5d00'; AmberSoft = '#fff4ce'; Red = '#c42b1c'; RedSoft = '#fde7e9'
               Grid = '#ededed'; Track = '#d1d1d1'; KeyLight = '#00ffffff'; Wash = '#e1f1ef'
               'Cat-Privacidad' = '#2e6bb5'; 'Cat-Servicios' = '#0d7a72'; 'Cat-Rendimiento' = '#b3541e'; 'Cat-Latencia' = '#b07d00'
               'Cat-Juegos' = '#2f8a3e'; 'Cat-Actualizaciones' = '#4f6bb0'; 'Cat-Interfaz' = '#a8466f'; 'Cat-Apps' = '#7a5a2e'; 'Cat-Tools' = '#5c5c5c'
               Mica = @{ Paper = '#00000000'; Side = '#00000000'; Layer = '#80ffffff'; LayerEdge = '#0f000000'; Card = '#b3ffffff'; CardEdge = '#0f000000'; CardHover = '#80f9f9f9'; Glass = '#b3ffffff'; GlassEdge = '#0f000000'; GlassHi = '#80f9f9f9' } }
    Dark  = @{ Dark = $true; Paper = '#202020'; Side = '#202020'; Layer = '#272727'; LayerEdge = '#1c1c1c'; Paper2 = '#2b2b2b'; Paper3 = '#383838'
               Card = '#2d2d2d'; CardEdge = '#383838'; CardHover = '#323232'; Control = '#2d2d2d'; ControlEdge = '#404040'; ControlHover = '#353535'
               Subtle = '#0fffffff'; Flyout = '#2c2c2c'; Disabled = '#6e6e6e'
               Ink = '#ffffff'; Ink2 = '#cfcfcf'; Muted = '#a3a3a3'; Rule = '#3a3a3a'; RuleStrong = '#4a4a4a'
               Accent = '#4cc3b6'; AccentInk = '#00201d'; AccentSoft = '#173a37'; AccentEdge = '#6fd6ca'; AccentHover = '#1f000000'; Accent2 = '#4cc3b6'
               Glass = '#2d2d2d'; GlassEdge = '#383838'; GlassHi = '#323232'; Glow = '#00000000'; Glow2 = '#00000000'
               Green = '#6ccb5f'; GreenSoft = '#1e3a1c'; Amber = '#f2c94c'; AmberSoft = '#3a3115'; Red = '#ff99a4'; RedSoft = '#442726'
               Grid = '#2a2a2a'; Track = '#4a4a4a'; KeyLight = '#00ffffff'; Wash = '#173a37'
               'Cat-Privacidad' = '#6ca6e8'; 'Cat-Servicios' = '#4cc3b6'; 'Cat-Rendimiento' = '#e8925a'; 'Cat-Latencia' = '#e5c04a'
               'Cat-Juegos' = '#6ccb7a'; 'Cat-Actualizaciones' = '#8fa7e8'; 'Cat-Interfaz' = '#e58ab8'; 'Cat-Apps' = '#c9a46a'; 'Cat-Tools' = '#a0a0a0'
               Mica = @{ Paper = '#00000000'; Side = '#00000000'; Layer = '#4c3a3a3a'; LayerEdge = '#19000000'; Card = '#0dffffff'; CardEdge = '#19000000'; CardHover = '#15ffffff'; Glass = '#0dffffff'; GlassEdge = '#19000000'; GlassHi = '#15ffffff' } }
}# each brand's real color (Simple Icons); in the dark theme, black brands switch to the light ink
$BrandColors = @{
    'brand-steam' = '#000000'; 'brand-epicgames' = '#313131'; 'brand-gogdotcom' = '#86328a'; 'brand-ea' = '#000000'; 'brand-ubisoft' = '#000000'
    'brand-battledotnet' = '#148eff'; 'brand-discord' = '#5865f2'; 'brand-obsstudio' = '#302e31'; 'brand-msi' = '#ff0000'; 'brand-7zip' = '#000000'
    'brand-vlcmediaplayer' = '#ff8800'; 'brand-firefoxbrowser' = '#ff7139'; 'brand-brave' = '#fb542b'; 'brand-dotnet' = '#512bd4'
    'brand-cloudflare' = '#f38020'; 'brand-google' = '#4285f4'; 'brand-docker' = '#2496ed'; 'brand-spotify' = '#1db954'
    'brand-1password' = '#3b66bc'; 'brand-anydesk' = '#ef443b'; 'brand-audacity' = '#0000cc'; 'brand-bitwarden' = '#175ddc'; 'brand-blender' = '#e87d0d'; 'brand-curseforge' = '#f16436'
    'brand-dropbox' = '#0061ff'; 'brand-filezilla' = '#bf0000'; 'brand-foobar2000' = '#000000'; 'brand-gimp' = '#5c5543'; 'brand-git' = '#f05032'; 'brand-github' = '#181717'; 'brand-googlechrome' = '#4285f4'
    'brand-googledrive' = '#4285f4'; 'brand-inkscape' = '#000000'; 'brand-kdenlive' = '#527eb2'; 'brand-keepassxc' = '#6cac4d'; 'brand-krita' = '#3babff'; 'brand-libreoffice' = '#18a303'; 'brand-malwarebytes' = '#0d3ecc'
    'brand-modrinth' = '#00af5c'; 'brand-mpv' = '#691f69'; 'brand-nodedotjs' = '#5fa04e'; 'brand-notepadplusplus' = '#90e59a'; 'brand-notion' = '#000000'; 'brand-obsidian' = '#7c3aed'; 'brand-opera' = '#ff1b2d'
    'brand-operagx' = '#ee2950'; 'brand-plex' = '#ebaf00'; 'brand-python' = '#3776ab'; 'brand-qbittorrent' = '#2f67ba'; 'brand-rustdesk' = '#024eff'; 'brand-sharex' = '#2885f1'; 'brand-signal' = '#3b45fd'
    'brand-slack' = '#4a154b'; 'brand-tailscale' = '#242424'; 'brand-teamspeak' = '#4b69b6'; 'brand-teamviewer' = '#050a52'; 'brand-telegram' = '#26a5e4'; 'brand-thunderbird' = '#0a84ff'; 'brand-vivaldi' = '#ef3939'
    'brand-wireguard' = '#88171a'; 'brand-zoom' = '#0b5cff'
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
    <SolidColorBrush x:Key="Paper" Color="#f3f3f3"/>
    <FontFamily x:Key="Display">Segoe UI Variable Display, Segoe UI</FontFamily>
    <FontFamily x:Key="Mono">Cascadia Mono, Consolas</FontFamily>
    <FontFamily x:Key="Icons">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>

    <!-- Fluent (Windows 11): radius 4 on controls and 8 on cards, a single accent, short transitions -->
    <Style TargetType="ContextMenu">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="FontFamily" Value="Segoe UI Variable Text, Segoe UI"/>
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ContextMenu">
        <Border Background="{DynamicResource Flyout}" BorderBrush="{DynamicResource RuleStrong}" BorderThickness="1" CornerRadius="8" Padding="4" MinWidth="220">
          <StackPanel IsItemsHost="True"/>
        </Border>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType="MenuItem">
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="MenuItem">
        <Border x:Name="bd" Background="Transparent" CornerRadius="4" Padding="10,7,16,7">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="28"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <ContentPresenter ContentSource="Icon" VerticalAlignment="Center"/>
            <ContentPresenter Grid.Column="1" ContentSource="Header" VerticalAlignment="Center"/>
          </Grid>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Subtle}"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="{x:Static MenuItem.SeparatorStyleKey}" TargetType="Separator">
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Separator">
        <Border Height="1" Margin="8,4" Background="{DynamicResource Rule}"/>
      </ControlTemplate></Setter.Value></Setter>
    </Style>

    <!-- standard button: control fill, thin border; slightly lighter on hover -->
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource Control}"/>
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource ControlEdge}"/>
      <Setter Property="Padding" Value="14,0"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid x:Name="root">
              <Border x:Name="ring" CornerRadius="7" Margin="-3" BorderThickness="2" BorderBrush="{DynamicResource Ink}" Opacity="0"/>
              <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4"/>
              <Border x:Name="hover" CornerRadius="4" Background="{DynamicResource ControlHover}" Opacity="0" IsHitTestVisible="False"/>
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="hover" Property="Opacity" Value="1"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="hover" Property="Opacity" Value="0.5"/><Setter Property="Foreground" Value="{DynamicResource Ink2}"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ring" Property="Opacity" Value="1"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="{DynamicResource Disabled}"/>
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Subtle}"/>
                <Setter Property="Cursor" Value="Arrow"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- primary button: the accent, flat -->
    <Style x:Key="BtnPrimary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="{DynamicResource Accent}"/>
      <Setter Property="Foreground" Value="{DynamicResource AccentInk}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid x:Name="root">
              <Border x:Name="ring" CornerRadius="7" Margin="-3" BorderThickness="2" BorderBrush="{DynamicResource Ink}" Opacity="0"/>
              <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="4"/>
              <Border x:Name="hover" CornerRadius="4" Background="{DynamicResource AccentHover}" Opacity="0" IsHitTestVisible="False"/>
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="hover" Property="Opacity" Value="1"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="root" Property="Opacity" Value="0.85"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ring" Property="Opacity" Value="1"/></Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Subtle}"/>
                <Setter Property="Foreground" Value="{DynamicResource Disabled}"/>
                <Setter Property="Cursor" Value="Arrow"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Windows 11 toggle switch: 40 x 20, thumb grows on hover -->
    <Style x:Key="Switch" TargetType="ToggleButton">
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="20"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid x:Name="root" Background="Transparent">
              <Border x:Name="ring" CornerRadius="13" Margin="-3" BorderThickness="2" BorderBrush="{DynamicResource Ink}" Opacity="0"/>
              <Border x:Name="track" CornerRadius="10" Background="{DynamicResource Control}" BorderBrush="{DynamicResource Ink2}" BorderThickness="1"/>
              <Ellipse x:Name="thumb" Width="12" Height="12" HorizontalAlignment="Left" Margin="4,0,0,0" Fill="{DynamicResource Ink2}">
                <Ellipse.RenderTransform><TranslateTransform x:Name="tt" X="0"/></Ellipse.RenderTransform>
              </Ellipse>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="{DynamicResource Accent}"/>
                <Setter TargetName="track" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter TargetName="thumb" Property="Fill" Value="{DynamicResource AccentInk}"/>
                <Trigger.EnterActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="tt" Storyboard.TargetProperty="X" To="20" Duration="0:0:0.15"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                </Storyboard></BeginStoryboard></Trigger.EnterActions>
                <Trigger.ExitActions><BeginStoryboard><Storyboard>
                  <DoubleAnimation Storyboard.TargetName="tt" Storyboard.TargetProperty="X" To="0" Duration="0:0:0.15"><DoubleAnimation.EasingFunction><CubicEase EasingMode="EaseOut"/></DoubleAnimation.EasingFunction></DoubleAnimation>
                </Storyboard></BeginStoryboard></Trigger.ExitActions>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="thumb" Property="Width" Value="14"/><Setter TargetName="thumb" Property="Height" Value="14"/><Setter TargetName="thumb" Property="Margin" Value="3,0,0,0"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ring" Property="Opacity" Value="1"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="root" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- filter: pill; the selected one uses the soft accent -->
    <Style x:Key="TabToggle" TargetType="ToggleButton">
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid>
              <Border x:Name="b" Background="{DynamicResource Control}" BorderBrush="{DynamicResource ControlEdge}" BorderThickness="1" CornerRadius="4" MinHeight="30"/>
              <ContentPresenter Margin="12,0,10,0" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource ControlHover}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="{DynamicResource AccentSoft}"/>
                <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Ink}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- tweak or action card (Windows SettingsCard): radius 4, thin border, lightens on hover -->
    <Style x:Key="RuleRow" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource Card}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource CardEdge}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="4"/>
      <Setter Property="Margin" Value="0,0,0,4"/>
      <Setter Property="Padding" Value="16,12,16,12"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource CardHover}"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Tile" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource Card}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource CardEdge}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Padding" Value="16,14"/>
    </Style>
    <Style x:Key="Row" TargetType="Border" BasedOn="{StaticResource Tile}">
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource CardHover}"/></Trigger>
      </Style.Triggers>
    </Style>

    <!-- navigation: subtle fill and a small accent bar on the left of the selected item -->
    <Style TargetType="ListBoxItem">
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,0,2"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Grid>
              <Border x:Name="b" Background="Transparent" CornerRadius="4" Padding="12,7"><ContentPresenter/></Border>
              <Border x:Name="pill" Width="3" Height="16" CornerRadius="2" HorizontalAlignment="Left" Background="{DynamicResource Accent}" Visibility="Hidden"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Subtle}"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Subtle}"/><Setter TargetName="pill" Property="Visibility" Value="Visible"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Ink}"/><Setter TargetName="b" Property="BorderThickness" Value="1"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{DynamicResource Flyout}"/>
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource RuleStrong}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="9,6"/>
      <Setter Property="FontSize" Value="12"/>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb><Thumb.Template><ControlTemplate TargetType="Thumb">
                  <Border CornerRadius="3" Background="{DynamicResource RuleStrong}" Margin="1,0"/>
                </ControlTemplate></Thumb.Template></Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- text box (search): accent bottom border while typing, like in Windows -->
    <Style x:Key="Field" TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource Control}"/>
      <Setter Property="Foreground" Value="{DynamicResource Ink}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource Ink}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource ControlEdge}"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Grid>
              <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="4"/>
              <Border x:Name="line" Height="2" VerticalAlignment="Bottom" CornerRadius="0,0,4,4" Background="{DynamicResource Accent}" Visibility="Hidden"/>
              <ScrollViewer x:Name="PART_ContentHost" Margin="32,0,8,0" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="line" Property="Visibility" Value="Visible"/><Setter TargetName="b" Property="Background" Value="{DynamicResource Card}"/></Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource ControlHover}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid x:Name="Root">
    <Grid.RowDefinitions><RowDefinition x:Name="TitleRow" Height="0"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="260"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="Auto"/>
    </Grid.ColumnDefinitions>

    <!-- custom title bar when Mica is on (Windows draws the close and minimize buttons on the right) -->
    <StackPanel Grid.ColumnSpan="3" Orientation="Horizontal" Margin="16,0,0,0" VerticalAlignment="Center">
      <Border Width="16" Height="16" CornerRadius="4" Background="{DynamicResource Accent}">
        <ContentControl x:Name="TitleMark" Focusable="False" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock Text="OptiEleven" FontSize="12" Margin="12,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource Ink2}"/>
    </StackPanel>

    <!-- navigation pane -->
    <DockPanel Grid.Row="1" Margin="8,6,8,10">
      <Grid DockPanel.Dock="Top" Margin="8,4,4,12">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal">
          <Border Width="28" Height="28" CornerRadius="6" Background="{DynamicResource Accent}">
            <ContentControl x:Name="BrandMark" Focusable="False" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock Text="OptiEleven" FontFamily="{StaticResource Display}" FontSize="16" FontWeight="SemiBold" Margin="10,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <Button x:Name="BtnLang" Grid.Column="1" Style="{StaticResource Btn}" Padding="8,0" MinHeight="28" ToolTip="Idioma" AutomationProperties.Name="Idioma">
          <StackPanel Orientation="Horizontal">
            <ContentControl x:Name="LangIcon" Focusable="False" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <TextBlock x:Name="LangCode" FontSize="12" FontWeight="SemiBold" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
      </Grid>
      <Grid DockPanel.Dock="Top" Margin="4,0,4,10">
        <TextBox x:Name="SearchBox" Style="{StaticResource Field}" Height="34" AutomationProperties.Name="Buscar"/>
        <TextBlock Text="&#xE721;" FontFamily="{StaticResource Icons}" FontSize="14" Foreground="{DynamicResource Ink2}" Margin="11,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        <TextBlock x:Name="SearchHint" Text="Buscar" Foreground="{DynamicResource Muted}" Margin="33,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        <Border HorizontalAlignment="Right" Margin="0,0,8,0" VerticalAlignment="Center" CornerRadius="3" Padding="5,1" BorderThickness="1" BorderBrush="{DynamicResource ControlEdge}" IsHitTestVisible="False">
          <TextBlock x:Name="SearchKey" Text="Ctrl K" FontSize="11" Foreground="{DynamicResource Muted}"/>
        </Border>
        <Popup x:Name="SearchPopup" PlacementTarget="{Binding ElementName=SearchBox}" Placement="Bottom" StaysOpen="False" AllowsTransparency="True" VerticalOffset="4">
          <Border Background="{DynamicResource Flyout}" BorderBrush="{DynamicResource RuleStrong}" BorderThickness="1" CornerRadius="8" Padding="4" Width="420" MaxHeight="440">
            <ListBox x:Name="SearchList" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
          </Border>
        </Popup>
      </Grid>
      <Grid DockPanel.Dock="Bottom" Margin="4,8,4,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border x:Name="AdminChip" CornerRadius="4" Padding="10,6" Margin="0,0,6,0" Background="{DynamicResource Subtle}" MinHeight="32">
          <Grid VerticalAlignment="Center">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <ContentControl x:Name="AdminIcon" Focusable="False" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <TextBlock x:Name="AdminTitle" Grid.Column="1" FontSize="12" VerticalAlignment="Center" TextWrapping="Wrap"/>
          </Grid>
        </Border>
        <Button x:Name="BtnTheme" Grid.Column="1" Style="{StaticResource Btn}" Padding="9,0" AutomationProperties.Name="Cambiar tema">
          <ContentControl x:Name="ThemeIcon" Focusable="False"/>
        </Button>
      </Grid>
      <Border x:Name="ProRow" DockPanel.Dock="Bottom" CornerRadius="4" Padding="12,8" Margin="4,8,4,0" Background="Transparent" Cursor="Hand"
              ToolTip="Claves del registro, servicios y tareas de cada ajuste, y el registro de actividad.">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <ContentControl x:Name="ProIcon" Focusable="False" VerticalAlignment="Center" Margin="0,0,12,0"/>
          <TextBlock Grid.Column="1" Text="Mostrar detalles técnicos" FontSize="13" VerticalAlignment="Center" TextWrapping="Wrap"/>
          <ToggleButton x:Name="ProSwitch" Grid.Column="2" Style="{StaticResource Switch}" VerticalAlignment="Center" Margin="8,0,0,0" AutomationProperties.Name="Mostrar detalles técnicos"/>
        </Grid>
      </Border>
      <ListBox x:Name="Nav" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
    </DockPanel>

    <!-- content: a slightly lighter layer over Mica, with the top corner rounded -->
    <Border x:Name="Layer" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="2" Background="{DynamicResource Layer}" BorderBrush="{DynamicResource LayerEdge}" BorderThickness="1,1,0,0" CornerRadius="8,0,0,0"/>
    <Grid Grid.Row="1" Grid.Column="1">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Grid Margin="40,28,36,12">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="Crumb" FontSize="14" Foreground="{DynamicResource Ink2}" Margin="0,0,0,4" Cursor="Hand" Visibility="Collapsed"/>
          <TextBlock x:Name="PageTitle" FontFamily="{StaticResource Display}" FontSize="28" FontWeight="SemiBold"/>
          <TextBlock x:Name="PageDesc" Foreground="{DynamicResource Ink2}" FontSize="14" Margin="0,4,0,0" TextWrapping="Wrap" MaxWidth="620" HorizontalAlignment="Left"/>
        </StackPanel>
        <StackPanel x:Name="PresetBar" Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Bottom" Margin="20,0,0,0">
          <Button x:Name="BtnComp" Style="{StaticResource Btn}" Margin="0,0,8,0"
                  ToolTip="Más a fondo: puede quitar funciones que uses. Revisa cada ajuste antes de aplicar."/>
          <Button x:Name="BtnRec" Style="{StaticResource BtnPrimary}"
                  ToolTip="Seguro para casi todos los equipos."/>
        </StackPanel>
      </Grid>
      <StackPanel x:Name="InfoHost" Grid.Row="1" Margin="40,0,36,4"/>
      <ScrollViewer x:Name="TabScroll" Grid.Row="2" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Disabled" Margin="40,2,36,4">
        <WrapPanel x:Name="Tabs" Orientation="Horizontal"/>
      </ScrollViewer>
      <ScrollViewer x:Name="TweakPage" Grid.Row="3" VerticalScrollBarVisibility="Auto" Padding="40,4,30,24">
        <StackPanel x:Name="TweakList"/>
      </ScrollViewer>
      <ScrollViewer x:Name="ToolsPage" Grid.Row="3" VerticalScrollBarVisibility="Auto" Padding="40,4,30,24" Visibility="Collapsed">
        <StackPanel x:Name="ToolGrid"/>
      </ScrollViewer>
      <Border x:Name="LogPage" Grid.Row="3" Visibility="Collapsed" Margin="40,0,36,24" Background="{DynamicResource Card}" CornerRadius="8"
              BorderBrush="{DynamicResource CardEdge}" BorderThickness="1">
        <TextBox x:Name="Log" IsReadOnly="True" Background="Transparent" BorderThickness="0" Foreground="{DynamicResource Ink2}"
                 FontFamily="{StaticResource Mono}" FontSize="12.5" Padding="14,12" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
      </Border>
      <ScrollViewer x:Name="ModulePage" Grid.Row="3" VerticalScrollBarVisibility="Auto" Padding="40,4,30,24" Visibility="Collapsed">
        <ContentControl x:Name="ModuleHost" Focusable="False"/>
      </ScrollViewer>
    </Grid>

    <!-- side rail: tweak details and change sheet -->
    <Border x:Name="Rail" Grid.Row="1" Grid.Column="2" Width="340" BorderBrush="{DynamicResource Rule}" BorderThickness="1,0,0,0">
      <DockPanel>
        <Border x:Name="Ledger" DockPanel.Dock="Bottom" Margin="16,8,16,16" CornerRadius="8" BorderBrush="{DynamicResource CardEdge}" BorderThickness="1" Background="{DynamicResource Card}">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <Grid Margin="16,14,16,8">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel VerticalAlignment="Center">
                <TextBlock Text="Cambios pendientes" FontWeight="SemiBold"/>
                <TextBlock x:Name="LedgerSub" FontSize="12" Foreground="{DynamicResource Ink2}" Margin="0,2,0,0"/>
              </StackPanel>
              <TextBlock x:Name="LedgerCount" Grid.Column="1" Text="0" FontFamily="{StaticResource Display}" FontSize="28" FontWeight="SemiBold" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
            </Grid>
            <Grid x:Name="LedgerStats" Grid.Row="1" Margin="16,0,16,4">
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <StackPanel><TextBlock Text="Aplicar" FontSize="12" Foreground="{DynamicResource Ink2}"/><TextBlock x:Name="LedgerApply" Text="0" FontSize="15" FontWeight="SemiBold"/></StackPanel>
              <StackPanel Grid.Column="1"><TextBlock Text="Revertir" FontSize="12" Foreground="{DynamicResource Ink2}"/><TextBlock x:Name="LedgerRevert" Text="0" FontSize="15" FontWeight="SemiBold"/></StackPanel>
              <StackPanel Grid.Column="2"><TextBlock Text="Reinicio" FontSize="12" Foreground="{DynamicResource Ink2}"/><TextBlock x:Name="LedgerReboot" Text="no" FontSize="15" FontWeight="SemiBold"/></StackPanel>
            </Grid>
            <Border x:Name="LedgerGrid" Grid.Row="2" MaxHeight="150" BorderBrush="{DynamicResource Rule}" BorderThickness="0,1,0,0" Margin="0,6,0,0">
              <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="LedgerList" Margin="16,8,16,6"/></ScrollViewer>
            </Border>
            <Grid Grid.Row="3" Margin="16,4,16,16">
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Button x:Name="BtnDiscard" Style="{StaticResource Btn}" Content="Descartar" Margin="0,0,8,0"/>
              <Button x:Name="BtnApply" Grid.Column="1" Style="{StaticResource BtnPrimary}" Content="Aplicar cambios"/>
            </Grid>
          </Grid>
        </Border>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Focusable="False">
          <StackPanel x:Name="Detail" Margin="20,24,20,8"/>
        </ScrollViewer>
      </DockPanel>
    </Border>

    <!-- status bar -->
    <Border Grid.Row="2" Grid.ColumnSpan="3" Background="{DynamicResource Layer}" BorderBrush="{DynamicResource Rule}" BorderThickness="0,1,0,0" Padding="20,0">
      <Grid MinHeight="30">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel x:Name="StatList" Orientation="Horizontal" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="Pendientes" Foreground="{DynamicResource Ink2}" FontSize="12" Margin="0,0,6,0" VerticalAlignment="Center"/>
          <Border x:Name="QueuePill" CornerRadius="4" Padding="7,0" Background="{DynamicResource Subtle}">
            <TextBlock x:Name="QueueText" Text="0" FontSize="12" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

# ---------- tools: each folder in tools\ brings its tool.json and tool.ps1; the core knows none of them by name
$script:AppDir = $PSScriptRoot
function Get-Tools([string]$Dir) {
    $seen = @{}
    foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter 'tool.json' -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName) {
        try {
            $m = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $miss = @('id', 'kind', 'category', 'name', 'icon', 'view', 'risk', 'requiresAdmin', 'reversible', 'undo' | Where-Object { $null -eq $m.$_ })
            if ($miss.Count) { throw "faltan $($miss -join ', ')" }
            if ($m.risk -notin 'safe', 'moderate', 'advanced') { throw "riesgo desconocido: $($m.risk)" }
            if ($seen.ContainsKey($m.id)) { throw "id repetido: $($m.id)" }
            # page keys are case-insensitive: "apps" would overwrite the "Apps" tweaks tab
            if ($m.id -in (@('all', 'tools', 'log') + @($Tweaks | ForEach-Object { $_.Cat })) -or $m.id -like 'h-*' -or $m.id -like 'c-*') { throw "id reservado: $($m.id)" }
            $seen[$m.id] = $true
            $m | Add-Member -NotePropertyName Dir -NotePropertyValue $f.DirectoryName
            $m
        } catch { Write-Log "Herramienta no cargada ($($f.Directory.Name)): $($_.Exception.Message)" 'WARN' }   # one broken tool doesn't take down the rest
    }
}
$script:Tools = @(Get-Tools (Join-Path $PSScriptRoot 'tools'))
# PS 5.1: ConvertFrom-Json returns the list as a single object; going through a variable unrolls it
$ToolCats = @(try { $j = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tools\categories.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json; $j } catch { })
function ConvertTo-PageDef($m) {
    @{ Label = Get-ToolText $m.name; Icon = $m.icon; Module = $m.view; Color = $m.color; OnShow = $m.onShow; Tool = $m
       Title = $(if ($m.title) { Get-ToolText $m.title } else { Get-ToolText $m.name }); Desc = Get-ToolText $m.summary }
}
function Get-CatTools([string]$Cat) { @($script:Tools | Where-Object category -eq $Cat | Sort-Object { [int]$_.order }) }

# Pages: the navigation only has Home, History and the categories from tools\categories.json. Each category opens its
# page (a "hub") with its tools and tweak groups; if it has only one, that one opens directly.
$Pages = [ordered]@{}
foreach ($c in @($ToolCats | Sort-Object { [int]$_.order })) {
    $items = @()
    foreach ($m in Get-CatTools $c.id) { $items += [pscustomobject]@{ Order = [int]$m.order; Key = $m.id; Def = (ConvertTo-PageDef $m) } }
    foreach ($g in @($c.tweaks)) {
        if (-not $g) { continue }
        $items += [pscustomobject]@{ Order = [int]$g.order; Key = $g.id; Def = @{ Tab = $g.id; Label = (Get-ToolText $g.name); Title = (Get-ToolText $g.name); Desc = (Get-ToolText $g.summary); Icon = $g.icon } }
    }
    $items = @($items | Sort-Object Order)
    if ($c.id -eq 'start') { foreach ($it in $items) { $it.Def.Nav = $true; $Pages[$it.Key] = $it.Def }; continue }
    if (-not $items.Count) { continue }
    $hub = "c-$($c.id)"
    $Pages[$hub] = @{ Label = (Get-ToolText $c.name); Title = (Get-ToolText $c.name); Desc = (Get-ToolText $c.summary); Icon = $c.icon; Nav = $true; Hub = [Collections.ArrayList]@($items | ForEach-Object { $_.Key }) }
    foreach ($it in $items) { $it.Def.Parent = $hub; $Pages[$it.Key] = $it.Def }
}
# core pages: all tweaks together (with filters), backups and profiles, and the activity log (with technical details)
$Pages['all'] = @{ Tab = 'all'; Label = 'Todos los ajustes'; Title = 'Todos los ajustes'; Desc = 'Los 60 ajustes en una lista, con filtros por grupo.' }
$Pages['tools'] = @{ Label = 'Copias y perfiles'; Icon = 'archive'; Title = 'Copias y perfiles'; Desc = 'Punto de restauración, perfiles para otros equipos y copias de seguridad.'; Parent = 'c-system' }
$Pages['log'] = @{ Label = 'Actividad'; Icon = 'scroll'; Title = 'Actividad'; Desc = 'Lo que ha hecho el panel en esta sesión.'; Parent = 'c-system'; ProOnly = $true }
if ($Pages.Contains('c-system')) { [void]$Pages['c-system'].Hub.Add('tools'); [void]$Pages['c-system'].Hub.Add('log') }
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
           # Windows restarts it on its own; starting it from here (elevated) would give a desktop with administrator rights
           for ($i = 0; $i -lt 40 -and -not (Get-Process explorer -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 250; Update-Ui }
           if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { runas /trustlevel:0x20000 explorer.exe } } }
    @{ Icon = 'archive'; Name = 'Copias de seguridad'; Desc = 'La carpeta con el estado original de cada ajuste y el registro del panel.'; Button = 'Abrir carpeta'; Admin = $false
       Action = { Start-Process explorer.exe $script:Root } }
)

try {
    # the window shows in the taskbar as OptiEleven, with its logo, not as just another PowerShell window
    try { [void][GP.Shell]::SetCurrentProcessExplicitAppUserModelID('OptiEleven.Panel') } catch {}
    # fixed window texts: translated in the XAML before loading it (x:Name values are left alone)
    foreach ($node in $xaml.SelectNodes('//*')) {
        foreach ($a in @($node.Attributes)) {
            if ($a.LocalName -in 'Text', 'Content', 'ToolTip', 'Title', 'Header', 'AutomationProperties.Name' -and $a.NamespaceURI -eq '' -and $a.Value -and -not $a.Value.StartsWith('{')) { $a.Value = T $a.Value }
        }
    }
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    # An error inside a button must not close the whole panel: it is logged, the user is told and the window stays open.
    $window.Dispatcher.Add_UnhandledException({
        param($src, $e)
        $e.Handled = $true
        $ex = $e.Exception; while ($ex.InnerException) { $ex = $ex.InnerException }
        try { Write-Log "Error inesperado: $($ex.Message)" 'ERROR' } catch {}
        try { if ($script:Busy) { Set-Busy $false } } catch {}
        try { [void][Windows.MessageBox]::Show($window, (T 'Algo ha fallado, pero el panel sigue abierto. Los detalles están en Actividad (Modo experto).') + "`n`n$($ex.Message)", 'OptiEleven', 'OK', 'Warning') } catch {}
    })
    $wa = [System.Windows.SystemParameters]::WorkArea
    $window.Height = [math]::Min($window.Height, $wa.Height - 24)
    $window.Width  = [math]::Min($window.Width, $wa.Width - 24)
    $ui = @{}
    foreach ($n in 'Root', 'TitleRow', 'TitleMark', 'Layer', 'SearchBox', 'SearchHint', 'SearchKey', 'SearchPopup', 'SearchList', 'Crumb', 'InfoHost', 'Nav', 'BrandMark', 'BtnLang', 'LangIcon', 'LangCode', 'ProRow', 'ProIcon', 'ProSwitch', 'LedgerStats','AdminChip', 'AdminIcon', 'AdminTitle', 'BtnTheme', 'ThemeIcon', 'PageTitle', 'PageDesc', 'PresetBar', 'BtnRec', 'BtnComp',
                   'Tabs', 'TabScroll', 'TweakPage', 'TweakList', 'ToolsPage', 'ToolGrid', 'LogPage', 'Log', 'ModulePage', 'ModuleHost', 'Rail', 'Detail',
                   'Ledger', 'LedgerSub', 'LedgerCount', 'LedgerApply', 'LedgerRevert', 'LedgerReboot', 'LedgerGrid', 'LedgerList', 'BtnDiscard', 'BtnApply',
                   'StatList', 'QueuePill', 'QueueText') {
        $ui[$n] = $window.FindName($n)
    }
    $script:LogBox = $ui.Log
    # Pro view: keys, services, tasks and paths. Without it, the panel shows only what you need to decide.
    $script:ProFile = Join-Path $script:Root 'pro.txt'
    $script:Pro = Test-Path -LiteralPath $script:ProFile
    $script:ProOnly = @()
    $FgProp = [Windows.Controls.TextBlock]::ForegroundProperty
    $BgProp = [Windows.Controls.Border]::BackgroundProperty
    $FillProp = [Windows.Shapes.Shape]::FillProperty

    # ---------- shared building blocks (the modules use them too)
    function New-Text([string]$Text, [double]$Size = 14, [string]$Brush = 'Ink', [string]$Weight = 'Normal') {
        $tb = [Windows.Controls.TextBlock]::new()
        $tb.Text = (T $Text); $tb.FontSize = $Size; $tb.FontWeight = $Weight; $tb.TextWrapping = 'Wrap'
        $tb.SetResourceReference($FgProp, $Brush)
        $tb
    }
    function New-Mono([string]$Text, [double]$Size = 13, [string]$Brush = 'Ink') {
        $tb = New-Text $Text $Size $Brush; $tb.FontFamily = $window.FindResource('Mono'); $tb.TextWrapping = 'NoWrap'; $tb
    }
    # Icons: Segoe Fluent Icons, the Windows 11 icon font, for everything functional (the usual names
    # map to their glyph); Simple Icons (CC0, assets\icons.json) only for brands, which get their real color.
    $IconGlyphs = @{
        'app-window' = 0xECAA; 'archive' = 0xE7B8; 'arrow-circle-down' = 0xE896; 'arrow-circle-up' = 0xE898; 'arrow-counter-clockwise' = 0xE7A7
        'arrows-clockwise' = 0xE72C; 'arrows-counter-clockwise' = 0xE777; 'arrows-down-up' = 0xE8CB; 'arrows-in' = 0xE73F; 'battery-warning' = 0xE83F
        'brackets-curly' = 0xE943; 'broadcast' = 0xEC05; 'broom' = 0xEA99; 'browser' = 0xE774; 'browsers' = 0xE774; 'bug' = 0xEBE8; 'calendar-x' = 0xE787
        'chat-circle-dots' = 0xE8F2; 'check' = 0xE73E; 'circuitry' = 0xE964; 'clock-counter-clockwise' = 0xE81C; 'cloud' = 0xE753; 'cloud-arrow-down' = 0xE753
        'cloud-slash' = 0xE753; 'code' = 0xE943; 'copy' = 0xE8C8; 'cpu' = 0xE964; 'crosshair' = 0xE707; 'cube' = 0xE7B8; 'device-mobile' = 0xE8EA; 'devices' = 0xE772
        'download' = 0xE896; 'download-simple' = 0xE896; 'export' = 0xEDE1; 'eye-slash' = 0xED1A; 'file-pdf' = 0xEA90; 'files' = 0xE7C3; 'file-text' = 0xE8A5
        'file-zip' = 0xE7B8; 'film-strip' = 0xE8B2; 'fire' = 0xECAD; 'first-aid-kit' = 0xE95E; 'floppy-disk' = 0xE74E; 'folder-dashed' = 0xE8B7; 'folder-open' = 0xED25
        'folder-user' = 0xE8B7; 'folder' = 0xE8B7; 'game-controller' = 0xE7FC; 'gauge' = 0xEC4A; 'gear-six' = 0xE713; 'globe' = 0xE774; 'globe-simple' = 0xE774
        'graphics-card' = 0xF211; 'hard-drive' = 0xEDA2; 'hard-drives' = 0xEDA2; 'headset' = 0xE95B; 'house-line' = 0xE80F; 'image' = 0xE8B9; 'images' = 0xE8B9
        'joystick' = 0xE7FC; 'keyboard' = 0xE765; 'laptop' = 0xE7F8; 'layout' = 0xE8A9; 'lightning' = 0xE945; 'list-dashes' = 0xE8FD; 'lock-simple' = 0xE72E
        'magic-wand' = 0xE771; 'magnifying-glass' = 0xE721; 'map-pin' = 0xE707; 'megaphone' = 0xE789; 'memory' = 0xEEA0; 'microphone-slash' = 0xF781
        'microsoft-teams-logo' = 0xE716; 'microsoft-word-logo' = 0xE8A5; 'monitor-play' = 0xE7F4; 'moon' = 0xE708; 'moon-stars' = 0xE708; 'mouse' = 0xE962
        'music-notes' = 0xE8D6; 'network' = 0xE839; 'newspaper' = 0xE7C3; 'package' = 0xE7B8; 'paint-brush' = 0xE790; 'play-circle' = 0xE768; 'plugs' = 0xE83E
        'plugs-connected' = 0xE83E; 'plus' = 0xE710; 'power' = 0xE7E8; 'printer' = 0xE749; 'pulse' = 0xE9D9; 'puzzle-piece' = 0xEA86; 'ranking' = 0xE9D2
        'record' = 0xE7C8; 'rocket-launch' = 0xE945; 'scissors' = 0xE8C6; 'scroll' = 0xE7C3; 'share-network' = 0xE72D; 'shield-check' = 0xEA18; 'shield-slash' = 0xE83D
        'sign-in' = 0xE785; 'sliders-horizontal' = 0xE9E9; 'speaker-high' = 0xE767; 'stethoscope' = 0xE95E; 'storefront' = 0xE719; 'sun' = 0xE706; 'sun-horizon' = 0xE706
        'terminal' = 0xE756; 'terminal-window' = 0xE756; 'thermometer' = 0xE9CA; 'timer' = 0xE916; 'toggle-left' = 0xE9E9; 'trash' = 0xE74D; 'trash-simple' = 0xE74D
        'tray-arrow-down' = 0xE8B5; 'tree-structure' = 0xE8A4; 'usb' = 0xE88E; 'warning-octagon' = 0xE7BA; 'wave-sine' = 0xE9D9; 'wifi-high' = 0xE701; 'wifi-x' = 0xEB55
        'windows-logo' = 0xE7F4; 'wrench' = 0xE90F; 'x-circle' = 0xEA39; 'x-square' = 0xE711; 'info' = 0xE946; 'warning' = 0xE7BA; 'error' = 0xE783
        'chevron' = 0xE76C; 'chevron-down' = 0xE70D; 'chevron-up' = 0xE70E; 'search' = 0xE721; 'history' = 0xE81C; 'admin' = 0xE7EF; 'apps' = 0xE71D; 'eraser' = 0xE75C
    }
    $script:IconData = $null; $script:GeoCache = @{}
    try { $script:IconData = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'assets\icons.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    function New-Icon($Code, [double]$Size = 18, [string]$Brush = 'Ink2') {
        if ($Code -is [string] -and $IconGlyphs.ContainsKey($Code)) { $Code = $IconGlyphs[$Code] }
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
        # icon that takes the button's text color (so it dims like the text when the button is disabled)
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
        # like Windows Settings: just the icon, in the text color (category colors no longer tint icons);
        # brands keep their color
        $w = [Windows.Controls.Border]::new(); $w.Width = $Box; $w.Height = $Box; $w.VerticalAlignment = 'Center'
        if ($Brush -like 'Cat-*') { $Brush = 'Ink' }
        $isBrand = $Code -is [string] -and $Code -like 'brand-*'
        $ic = New-Icon $Code ([math]::Round($Box * $(if ($isBrand) { 0.6 } else { 0.5 }))) $(if ($Brush -eq 'Ink2' -and -not $isBrand) { 'Ink' } else { $Brush })
        $ic.HorizontalAlignment = 'Center'; $w.Child = $ic
        $w
    }
    function New-Chip([string]$Text, [string]$Bg = 'Paper3', [string]$Fg = 'Ink2') {
        $c = [Windows.Controls.Border]::new(); $c.CornerRadius = 4; $c.Padding = '8,2,8,3'; $c.Margin = '0,0,6,0'; $c.VerticalAlignment = 'Center'
        $c.SetResourceReference($BgProp, $Bg)
        $t = New-Text $Text 12 $Fg 'SemiBold'; $t.TextWrapping = 'NoWrap'; $c.Child = $t
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
    function New-Ruled { $s = [Windows.Controls.Border]::new(); $s.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Rule'); $s.BorderThickness = '0,1,0,0'; $s.Margin = '0,0,0,8'; $s }
    function New-Cols([string[]]$Widths) {
        $g = [Windows.Controls.Grid]::new()
        foreach ($w in $Widths) {
            $cd = [Windows.Controls.ColumnDefinition]::new()
            if ($w -eq '*') { $cd.Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star) }
            elseif ($w -match '^(\d+)\*$') { $cd.Width = [Windows.GridLength]::new([double]$Matches[1], [Windows.GridUnitType]::Star) }
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
    # Slow work in the background: $Work runs on another thread (it can't see the panel's functions: it must be self-contained) and
    # $Done gets its result back on the window thread, which doesn't freeze in the meantime.
    # $Progress (optional) is a shared table that $Work can fill in and $OnTick can read.
    $script:BgJobs = [Collections.Generic.List[object]]::new()
    $script:BgTimer = $null
    function Start-Bg([scriptblock]$Work, [object[]]$ArgList = @(), [scriptblock]$Done, [hashtable]$Progress, [scriptblock]$OnTick) {
        $ps = [powershell]::Create()
        [void]$ps.AddScript($Work.ToString())
        foreach ($a in $ArgList) { [void]$ps.AddArgument($a) }
        if ($null -ne $Progress) { [void]$ps.AddParameter('P', $Progress) }   # by name: the $Work blocks that use it call it $P
        $script:BgJobs.Add(@{ Ps = $ps; Handle = $ps.BeginInvoke(); Done = $Done; Tick = $OnTick; Progress = $Progress })
        if (-not $script:BgTimer) {
            $script:BgTimer = [System.Windows.Threading.DispatcherTimer]::new(); $script:BgTimer.Interval = [TimeSpan]::FromMilliseconds(120)
            $script:BgTimer.Add_Tick({
                foreach ($j in @($script:BgJobs)) {
                    if ($j.Tick) { try { & $j.Tick $j.Progress } catch { if (-not $j.TickErr) { $j.TickErr = $true; Write-Log "Segundo plano: $($_.Exception.Message)" 'WARN' } } }
                    if (-not $j.Handle.IsCompleted) { continue }
                    [void]$script:BgJobs.Remove($j)
                    $res = $null; $err = $null
                    try { $res = @($j.Ps.EndInvoke($j.Handle)) } catch { $err = $_.Exception.InnerException; if (-not $err) { $err = $_.Exception } }
                    $j.Ps.Dispose()
                    if ($err) { Write-Log "Segundo plano: $($err.Message)" 'WARN' }
                    if ($j.Done) { try { & $j.Done $res } catch { Write-Log "Segundo plano: $($_.Exception.Message)" 'ERROR' } }
                }
                if ($script:BgJobs.Count -eq 0) { $script:BgTimer.Stop() }
            })
        }
        $script:BgTimer.Start()
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
            finally { $ico.Dispose() }   # frees the HICON: the BitmapSource already has its own copy
            $img = [Windows.Controls.Image]::new(); $img.Source = $src; $img.Width = $Size; $img.Height = $Size
            $img
        }
        catch { $null }
    }
    # entrance micro-animation: fades in and rises a few pixels, with an optional delay to stagger lists
    $script:EaseOut = [Windows.Media.Animation.CubicEase]::new(); $script:EaseOut.EasingMode = 'EaseOut'; $script:EaseOut.Freeze()
    function Start-FadeIn($El, [double]$DelayMs = 0, [double]$Rise = 10) {
        $dur = [Windows.Duration][TimeSpan]::FromMilliseconds(260); $begin = [TimeSpan]::FromMilliseconds($DelayMs)
        $o = [Windows.Media.Animation.DoubleAnimation]::new(0, 1, $dur); $o.BeginTime = $begin; $o.EasingFunction = $script:EaseOut
        $El.Opacity = 0
        $El.BeginAnimation([Windows.UIElement]::OpacityProperty, $o)
        if ($Rise -gt 0) {
            $tt = [Windows.Media.TranslateTransform]::new(0, $Rise); $El.RenderTransform = $tt
            $m = [Windows.Media.Animation.DoubleAnimation]::new($Rise, 0, $dur); $m.BeginTime = $begin; $m.EasingFunction = $script:EaseOut
            $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $m)
        }
    }
    # loading indicator: a spinning arc and a text, so the window never looks hung
    function New-Spinner([double]$Size = 22) {
        $arc = [Windows.Shapes.Path]::new(); $arc.Data = [Windows.Media.Geometry]::Parse('M 11,2 A 9,9 0 1 1 2,11'); $arc.Width = 22; $arc.Height = 22
        $arc.StrokeThickness = 3; $arc.StrokeStartLineCap = 'Round'; $arc.StrokeEndLineCap = 'Round'; $arc.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, 'Accent')
        $rot = [Windows.Media.RotateTransform]::new(0, 11, 11); $arc.RenderTransform = $rot
        $spin = [Windows.Media.Animation.DoubleAnimation]::new(0, 360, [Windows.Duration][TimeSpan]::FromSeconds(0.9)); $spin.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $spin)
        $vb = [Windows.Controls.Viewbox]::new(); $vb.Width = $Size; $vb.Height = $Size; $vb.Child = $arc; $vb.VerticalAlignment = 'Center'
        $vb
    }
    function New-Loader([string]$Text) {
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.Margin = '4,24,0,24'
        $tb = New-Text $Text 14.5 'Ink2' 'Medium'; $tb.VerticalAlignment = 'Center'; $tb.Margin = '14,0,0,0'
        [void]$sp.Children.Add((New-Spinner 22)); [void]$sp.Children.Add($tb)
        $sp
    }
    # Working overlay inside the panel (not another window): dims what's behind, spinning circle in the middle, what it is
    # doing and a bar. Returns its parts so the text can be updated; Close-Working removes it.
    function Show-Working([string]$Title, [string]$Detail, [scriptblock]$OnCancel) {
        $ov = [Windows.Controls.Grid]::new()
        [Windows.Controls.Grid]::SetRowSpan($ov, 10); [Windows.Controls.Grid]::SetColumnSpan($ov, 10); [Windows.Controls.Panel]::SetZIndex($ov, 90)
        $ov.Background = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromArgb(0x80, 0x00, 0x00, 0x00))
        $card = [Windows.Controls.Border]::new(); $card.CornerRadius = 8; $card.Padding = '36,32,36,28'; $card.Width = 420; $card.BorderThickness = 1
        $card.HorizontalAlignment = 'Center'; $card.VerticalAlignment = 'Center'
        $card.SetResourceReference($BgProp, 'Paper2'); $card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'RuleStrong')
        $card.Effect = [Windows.Media.Effects.DropShadowEffect]::new(); $card.Effect.BlurRadius = 32; $card.Effect.ShadowDepth = 8; $card.Effect.Direction = 270; $card.Effect.Opacity = 0.28
        $sp = [Windows.Controls.StackPanel]::new()
        $sv = New-Spinner 48; $sv.HorizontalAlignment = 'Center'
        $t = New-Text $Title 20 'Ink' 'SemiBold'; $t.FontFamily = $window.FindResource('Display'); $t.TextAlignment = 'Center'; $t.Margin = '0,22,0,0'
        $d = New-Text $Detail 14 'Ink2'; $d.TextAlignment = 'Center'; $d.Margin = '0,8,0,0'; $d.MinHeight = 40
        $track = [Windows.Controls.Border]::new(); $track.Height = 4; $track.CornerRadius = 2; $track.Margin = '0,18,0,0'; $track.SetResourceReference($BgProp, 'Paper3')
        $bar = [Windows.Controls.Border]::new(); $bar.CornerRadius = 2; $bar.HorizontalAlignment = 'Left'; $bar.Width = 0; $bar.SetResourceReference($BgProp, 'Accent')
        $track.Child = $bar
        foreach ($x in $sv, $t, $d, $track) { [void]$sp.Children.Add($x) }
        if ($OnCancel) {
            $cb = New-Btn 'Cancelar'; $cb.Margin = '0,20,0,0'; $cb.HorizontalAlignment = 'Center'; $cb.MinWidth = 140; $cb.Tag = $OnCancel
            $cb.Add_Click({ param($src) $src.IsEnabled = $false; & $src.Tag })
            [void]$sp.Children.Add($cb)
        }
        $card.Child = $sp
        [void]$ov.Children.Add($card)
        [void]$window.Content.Children.Add($ov)
        Start-FadeIn $card 0 14
        Update-Ui
        @{ Overlay = $ov; Title = $t; Detail = $d; Bar = $bar; Track = $track }
    }
    function Set-WorkingProgress($W, [double]$Fraction) { if ($W) { $W.Bar.Width = [math]::Max([double]0, [math]::Min([double]1, $Fraction)) * $W.Track.ActualWidth } }
    function Close-Working($W) { if ($W -and $W.Overlay) { [void]$window.Content.Children.Remove($W.Overlay) } }
    function Start-Stagger($Items, [int]$Max = 14) {
        $i = 0
        foreach ($it in $Items) { if ($i -ge $Max) { break }; if ($it.Visibility -eq 'Visible') { Start-FadeIn $it ($i * 28) 8; $i++ } }
    }
    foreach ($tool in $script:Tools) { $p = Join-Path $tool.Dir 'tool.ps1'; if (Test-Path -LiteralPath $p) { . $p } }

    # ---------- theme
    function Get-Luma([string]$Hex) { $c = [Windows.Media.ColorConverter]::ConvertFromString($Hex); (0.2126 * $c.R + 0.7152 * $c.G + 0.0722 * $c.B) / 255 }
    function Set-Theme([string]$Name) {
        $th = $Themes[$Name]; $script:ThemeName = $Name
        # All colors go into a new dictionary that replaces the old one in one go: changing the resources
        # one by one makes WPF walk the whole window for each color (with ~100 colors, several seconds).
        $cols = @{}; foreach ($k in $th.Keys) { if ($k -notin 'Dark', 'Mica') { $cols[$k] = $th[$k] } }
        if ($script:Mica) { foreach ($k in $th.Mica.Keys) { $cols[$k] = $th.Mica[$k] } }   # with Mica, translucent backgrounds
        $rd = [Windows.ResourceDictionary]::new()
        foreach ($k in $cols.Keys) {
            $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($cols[$k])); $b.Freeze(); $rd[$k] = $b
            if ($k -like 'Cat-*') {   # soft background for each color (used by bars and data swatches)
                $c = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($cols[$k]); $c.A = $(if ($th.Dark) { 0x30 } else { 0x24 })
                $sb = [Windows.Media.SolidColorBrush]::new($c); $sb.Freeze(); $rd["Soft$k"] = $sb
            }
        }
        foreach ($bk in $BrandColors.Keys) {
            $hex = $BrandColors[$bk]; if ($th.Dark -and (Get-Luma $hex) -lt 0.3) { $hex = $th.Ink }
            $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex)); $b.Freeze(); $rd["Brand-$bk"] = $b
        }
        # old names some sections still use: the "gradient" is now the flat accent, and the glows are nothing
        $rd['AccentGrad'] = $rd['Accent']; $rd['PageGlow'] = [Windows.Media.Brushes]::Transparent; $rd['PageGlow2'] = [Windows.Media.Brushes]::Transparent
        if (-not $script:ThemeDict) { foreach ($k in @($rd.Keys)) { if ($window.Resources.Contains($k)) { $window.Resources.Remove($k) } } }   # the XAML's default colors
        $oldRd = $script:ThemeDict
        $window.Resources.MergedDictionaries.Add($rd); $script:ThemeDict = $rd
        if ($oldRd) { [void]$window.Resources.MergedDictionaries.Remove($oldRd) }
        $h = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
        if ($h -ne [IntPtr]::Zero) { $v = [int]$th.Dark; [void][GP.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4) }
        $ui.ThemeIcon.Content = if ($th.Dark) { New-Icon 'sun' 16 'Ink' } else { New-Icon 'moon' 16 'Ink' }
        $ui.BtnTheme.ToolTip = T $(if ($th.Dark) { 'Tema claro' } else { 'Tema oscuro' })
        try { Set-Content -LiteralPath (Join-Path $script:Root 'theme.txt') -Value $Name } catch {}
    }
    # Mica (Windows 11 22H2 or later): Windows paints the background with the blurred desktop color. WPF has to make
    # its background transparent and extend the frame over the whole window (WindowChrome); Windows draws the title bar buttons.
    $script:Mica = [Environment]::OSVersion.Version.Build -ge 22621 -and -not $env:OPTIELEVEN_NO_MICA
    if ($script:Mica) {
        $chrome = [Windows.Shell.WindowChrome]::new()
        $chrome.GlassFrameThickness = [Windows.Thickness]::new(-1); $chrome.CaptionHeight = 32; $chrome.ResizeBorderThickness = [Windows.Thickness]::new(6)
        $chrome.UseAeroCaptionButtons = $true; $chrome.CornerRadius = [Windows.CornerRadius]::new(0)
        [Windows.Shell.WindowChrome]::SetWindowChrome($window, $chrome)
        $ui.TitleRow.Height = [Windows.GridLength]::new(32)
        # when maximized, Windows puts the resize border off screen: compensate so the content isn't cut off
        $window.Add_StateChanged({ $ui.Root.Margin = if ($window.WindowState -eq 'Maximized') { '7' } else { '0' } })
    }
    $window.Add_SourceInitialized({
        $h = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
        $v = [int]$Themes[$script:ThemeName].Dark; [void][GP.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
        if ($script:Mica) {
            [Windows.Interop.HwndSource]::FromHwnd($h).CompositionTarget.BackgroundColor = [Windows.Media.Colors]::Transparent
            $m = 2; [void][GP.Dwm]::DwmSetWindowAttribute($h, 38, [ref]$m, 4)   # DWMWA_SYSTEMBACKDROP_TYPE = Mica
        }
    })
    $startTheme = 'Dark'
    try {
        $saved = (Get-Content -LiteralPath (Join-Path $script:Root 'theme.txt') -ErrorAction Stop | Select-Object -First 1).Trim()
        $saved = @{ Furrow = 'Light'; FurrowNoche = 'Dark' }[$saved], $saved | Where-Object { $_ } | Select-Object -First 1   # names from 1.x
        if ($Themes.ContainsKey($saved)) { $startTheme = $saved }
    } catch {}
    Set-Theme $startTheme    # ---------- logo: open ring (the "O" of Opti, like a power button) with the 11 inside
    function New-Logo([double]$Size) {
        $logo = [Windows.Controls.Canvas]::new(); $logo.Width = 64; $logo.Height = 64
        foreach ($p in @('M 47.56 18.44 A 22 22 0 1 1 16.44 18.44', 'M 23.5 12.5 L 27.5 8.5 L 27.5 31 M 36.5 12.5 L 40.5 8.5 L 40.5 31')) {
            $path = [Windows.Shapes.Path]::new(); $path.Data = [Windows.Media.Geometry]::Parse($p); $path.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, 'AccentInk')
            $path.StrokeThickness = 6.5; $path.StrokeStartLineCap = 'Round'; $path.StrokeEndLineCap = 'Round'; $path.StrokeLineJoin = 'Round'
            [void]$logo.Children.Add($path)
        }
        $vb = [Windows.Controls.Viewbox]::new(); $vb.Width = $Size; $vb.Height = $Size; $vb.Child = $logo; $vb.Margin = '0,1,0,0'
        $vb
    }
    $ui.BrandMark.Content = New-Logo 20
    $ui.TitleMark.Content = New-Logo 12    try { $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri](Join-Path $PSScriptRoot 'assets\optieleven.ico')) } catch {}

    # ---------- language (at the very top, next to the name)
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

    # ---------- preset buttons: large, with an icon, like the Boost FPS one
    foreach ($pb in @(@($ui.BtnRec, 'shield-check', 'Recomendado'), @($ui.BtnComp, 'lightning', 'Avanzado'))) {
        $c = [Windows.Controls.StackPanel]::new(); $c.Orientation = 'Horizontal'
        $i = New-BtnIcon $pb[1] 19; $i.Margin = '0,0,9,0'
        $l = [Windows.Controls.TextBlock]::new(); $l.Text = T $pb[2]; $l.VerticalAlignment = 'Center'
        [void]$c.Children.Add($i); [void]$c.Children.Add($l); $pb[0].Content = $c
    }

    # ---------- notice on open
    $script:WarnFile = Join-Path $script:Root 'warning.ok'
    # Windows InfoBar: icon, one sentence and, if needed, a button; closed with the X
    function New-InfoBar([string]$Icon, [string]$Text, [string]$Tone = 'info', [string]$Button, [scriptblock]$OnButton, [scriptblock]$OnClose) {
        $bar = [Windows.Controls.Border]::new(); $bar.CornerRadius = 4; $bar.Padding = '14,8,8,8'; $bar.Margin = '0,0,0,8'; $bar.BorderThickness = 1
        $bar.SetResourceReference($BgProp, $(switch ($Tone) { 'warn' { 'AmberSoft' } 'ok' { 'GreenSoft' } default { 'AccentSoft' } }))
        $bar.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'CardEdge')
        $g = New-Cols @('Auto', '*', 'Auto', 'Auto')
        $ic = New-Icon $Icon 16 $(switch ($Tone) { 'warn' { 'Amber' } 'ok' { 'Green' } default { 'Accent' } }); $ic.Margin = '0,0,12,0'; [void](Add-At $g $ic 0)
        $tx = New-Text $Text 13 'Ink'; $tx.VerticalAlignment = 'Center'; [void](Add-At $g $tx 1)
        if ($Button) { $b = New-Btn $Button; $b.Margin = '12,0,4,0'; $b.Tag = $OnButton; $b.Add_Click({ param($s) & $s.Tag }); [void](Add-At $g $b 2) }
        $x = [Windows.Controls.Button]::new(); $x.Style = $window.FindResource('Btn'); $x.Background = [Windows.Media.Brushes]::Transparent; $x.BorderBrush = [Windows.Media.Brushes]::Transparent
        $x.Padding = '8,0'; $x.Content = New-Icon 'x-square' 12 'Ink2'; $x.ToolTip = T 'Cerrar'; $x.Tag = @{ Bar = $bar; Close = $OnClose }
        $x.Add_Click({ param($s) if ($s.Tag.Close) { & $s.Tag.Close }; $p = $s.Tag.Bar.Parent; if ($p) { [void]$p.Children.Remove($s.Tag.Bar) } })
        [void](Add-At $g $x 3)
        $bar.Child = $g
        $bar
    }
    # the first time, a single line instead of the old wall of text
    if (-not (Test-Path -LiteralPath $script:WarnFile)) {
        $script:WarnBar = New-InfoBar 'info' 'Casi todo se puede deshacer desde Historial. Crea un punto de restauración antes del primer cambio.' 'info' $(if ($script:IsAdmin) { 'Crear punto' } else { $null }) { Set-Busy $true; try { [void](New-RestorePoint) } finally { Set-Busy $false } } { try { Set-Content -LiteralPath $script:WarnFile -Value (Get-Date -Format s) } catch {} }
        [void]$ui.InfoHost.Children.Add($script:WarnBar)
    }    # once the window is real only the dark title bar is missing; the colors are already set
    $ui.BtnTheme.Add_Click({ if ($script:ThemeName -eq 'Light') { Set-Theme 'Dark' } else { Set-Theme 'Light' } })

    if ($script:IsAdmin) { $ui.AdminIcon.Content = (New-Icon 'shield-check' 16 'Green'); $ui.AdminTitle.Text = (T 'Administrador'); $ui.AdminChip.ToolTip = (T 'Puedes aplicar y revertir ajustes.') }
    else {
        # without admin rights everything is visible but nothing applies: the chip offers to reopen the panel as administrator
        $ui.AdminIcon.Content = (New-Icon 'lock-simple' 16 'Ink2')
        $ui.AdminTitle.Inlines.Clear()
        $ui.AdminTitle.Inlines.Add([Windows.Documents.Run]::new((T 'Sin permisos de administrador')))
        $ui.AdminTitle.Inlines.Add([Windows.Documents.LineBreak]::new())
        $lk = [Windows.Documents.Run]::new((T 'Reiniciar como admin')); $lk.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'AccentEdge'); $lk.FontWeight = 'SemiBold'
        $ui.AdminTitle.Inlines.Add($lk)
        $ui.AdminChip.Cursor = 'Hand'; $ui.AdminChip.ToolTip = (T 'Vuelve a abrir el panel con permisos para aplicar cambios.')
        $ui.AdminChip.Add_MouseLeftButtonUp({ Restart-AsAdmin })
    }
    function Restart-AsAdmin {
        if (@(Get-Pending).Count -and [Windows.MessageBox]::Show($window, (T 'Los cambios sin aplicar se pierden al volver a abrir el panel.'), 'OptiEleven', 'OKCancel', 'Question') -ne 'OK') { return }
        $page = if ($script:CurrentPage) { $script:CurrentPage } else { 'home' }
        try { Start-Panel $page -Admin }
        catch { Write-Log 'No se abrió como administrador (cancelado).' 'WARN'; return }   # if the user says no, the panel stays open
        $window.Close()
    }

    # ---------- navigation: Home, History and the categories; icon in the text color, the selected one with the small accent bar
    $script:NavParts = @{}
    foreach ($key in $Pages.Keys) {
        $pg = $Pages[$key]; if (-not $pg.Nav) { continue }
        $g = New-Cols @('Auto', '*'); $g.Tag = $key
        $ic = New-Icon $pg.Icon 16 'Ink2'; $ic.Margin = '2,0,14,0'
        [void](Add-At $g $ic 0)
        $lb = New-Text $pg.Label 14 'Ink'; $lb.VerticalAlignment = 'Center'; $lb.TextWrapping = 'NoWrap'
        [void](Add-At $g $lb 1)
        [void]$ui.Nav.Items.Add($g)
        $script:NavParts[$key] = @{ Icon = $ic; Label = $lb }
    }
    function Update-NavColors {
        foreach ($k in $script:NavParts.Keys) {
            $sel = $ui.Nav.SelectedItem -and $ui.Nav.SelectedItem.Tag -eq $k
            $np = $script:NavParts[$k]
            Set-IconBrush $np.Icon $(if ($sel) { 'Ink' } else { 'Ink2' })
            $np.Label.FontWeight = $(if ($sel) { 'SemiBold' } else { 'Normal' })
        }
    }
    # category page: one card per tool or tweak group, with its state
    function New-HubView([string]$Key) {
        $sp = [Windows.Controls.StackPanel]::new()
        foreach ($k in $Pages[$Key].Hub) {
            $pg = $Pages[$k]; if (-not $pg -or ($pg.ProOnly -and -not $script:Pro)) { continue }
            $row = [Windows.Controls.Border]::new(); $row.Style = $window.FindResource('RuleRow'); $row.Cursor = 'Hand'; $row.Tag = $k; $row.Padding = '16,14,16,14'
            $g = New-Cols @('40', '*', 'Auto', 'Auto')
            [void](Add-At $g (New-IconWell $pg.Icon 28) 0)
            $tx = [Windows.Controls.StackPanel]::new(); $tx.VerticalAlignment = 'Center'
            [void]$tx.Children.Add((New-Text $pg.Label 14 'Ink'))
            if ($pg.Desc) { $dl = New-Text $pg.Desc 12 'Ink2'; $dl.TextTrimming = 'CharacterEllipsis'; $dl.TextWrapping = 'NoWrap'; [void]$tx.Children.Add($dl) }
            [void](Add-At $g $tx 1)
            if ($pg.Tab) {   # tweak group: how many are applied
                $rows = @($script:Rows.Values | Where-Object { $_.Tweak.Cat -eq $k })
                $on = @($rows | Where-Object { $_.Applied -eq $true }).Count
                $st = New-Text $(if ($script:StatusReady) { T "$on de $($rows.Count) aplicados" } else { T "$($rows.Count) ajustes" }) 12.5 'Ink2'; $st.VerticalAlignment = 'Center'; $st.Margin = '12,0,12,0'
                [void](Add-At $g $st 2)
            }
            $ch = New-Icon 'chevron' 12 'Ink2'; $ch.Margin = '8,0,0,0'; [void](Add-At $g $ch 3)
            $row.Child = $g
            $row.Add_MouseLeftButtonUp({ param($src) Select-NavKey ([string]$src.Tag) })
            [void]$sp.Children.Add($row)
        }
        $sp
    }    $script:TabParts = [ordered]@{}
    foreach ($key in @(@('all') + @($Pages.Keys | Where-Object { $_ -ne 'all' }))) {   # "Todos" (All) first
        $pg = $Pages[$key]; if (-not $pg.Tab) { continue }
        $tb = [Windows.Controls.Primitives.ToggleButton]::new(); $tb.Style = $window.FindResource('TabToggle'); $tb.Tag = $key
        $n = if ($key -eq 'all') { $Tweaks.Count } else { @($Tweaks | Where-Object Cat -eq $key).Count }
        $tc = [Windows.Controls.StackPanel]::new(); $tc.Orientation = 'Horizontal'
        $tl = [Windows.Controls.TextBlock]::new(); $tl.Text = T $(if ($key -eq 'all') { 'Todos' } else { $pg.Label }); $tl.VerticalAlignment = 'Center'; [void]$tc.Children.Add($tl)
        $tn = [Windows.Controls.TextBlock]::new(); $tn.Text = "$n"; $tn.FontSize = 12; $tn.Opacity = 0.6; $tn.Margin = '8,0,0,0'; $tn.VerticalAlignment = 'Center'
        [void]$tc.Children.Add($tn)
        $tb.Content = $tc; $tb.ToolTip = (T "$n ajustes")
        $tb.Add_Click({ param($src, $e) Show-Page $src.Tag })
        [void]$ui.Tabs.Children.Add($tb)
        $script:TabParts[$key] = $tb
    }
    function Update-Tabs([string]$Key) { foreach ($k in $script:TabParts.Keys) { $script:TabParts[$k].IsChecked = ($k -eq $Key) } }

    # ---------- tweak cards (like Windows Settings): icon, name, one line, state and toggle;
    # "More info" expands the technical part (what it touches and its current state), computed only when opened
    $script:Rows = [ordered]@{}
    $script:GroupHeads = @{}
    $script:Selected = $null
    $riskChip = @{ Seguro = @('Seguro', 'GreenSoft', 'Green'); Moderado = @('Moderado', 'AmberSoft', 'Amber'); Avanzado = @('Avanzado', 'RedSoft', 'Red') }
    $cats = @($Pages.Keys | Where-Object { $Pages[$_].Tab -and $_ -ne 'all' })
    function Add-CategoryRows([string]$cat) {
        $list = @($Tweaks | Where-Object Cat -eq $cat)
        if (-not $list) { return }
        $head = New-Text $Pages[$cat].Title 14 'Ink' 'SemiBold'; $head.Margin = '2,18,0,8'   # only shown in "All tweaks"
        [void]$ui.TweakList.Children.Add($head)
        $script:GroupHeads[$cat] = @($head)
        foreach ($t in $list) {
            $card = [Windows.Controls.Border]::new(); $card.Style = $window.FindResource('RuleRow'); $card.Padding = '0'; $card.Tag = $t.Id
            $stack = [Windows.Controls.StackPanel]::new()
            $outer = New-Cols @('3', '*')
            $mark = [Windows.Controls.Border]::new(); $mark.SetResourceReference($BgProp, 'Accent'); $mark.Visibility = 'Hidden'; $mark.Margin = '0,14,0,14'; $mark.CornerRadius = 2
            [void](Add-At $outer $mark 0)
            $grid = New-Cols @('44', '*', 'Auto', 'Auto', 'Auto'); $grid.Margin = '10,12,10,12'; $grid.Background = [Windows.Media.Brushes]::Transparent; $grid.Cursor = 'Hand'; $grid.Tag = $t.Id
            $icon = if ($TweakIcons.ContainsKey($t.Id)) { $TweakIcons[$t.Id] } else { 'gear-six' }
            [void](Add-At $grid (New-IconWell $icon 28) 0)
            $left = [Windows.Controls.StackPanel]::new(); $left.VerticalAlignment = 'Center'
            $nm = New-Text $t.Name 14 'Ink'; $nm.TextWrapping = 'NoWrap'; $nm.TextTrimming = 'CharacterEllipsis'
            $ds = New-Text $t.Desc 12 'Ink2'; $ds.TextWrapping = 'NoWrap'; $ds.TextTrimming = 'CharacterEllipsis'; $ds.ToolTip = $ds.Text
            [void]$left.Children.Add($nm); [void]$left.Children.Add($ds)
            [void](Add-At $grid $left 1)
            $chips = [Windows.Controls.StackPanel]::new(); $chips.Orientation = 'Horizontal'; $chips.Margin = '12,0,4,0'
            $rc = $riskChip[$t.Risk]
            if ($t.Risk -ne 'Seguro') { [void]$chips.Children.Add((New-Chip $rc[0] $rc[1] $rc[2])) }
            $state = New-Chip '...' 'Subtle' 'Ink2'; [void]$chips.Children.Add($state)
            [void](Add-At $grid $chips 2)
            $sw = New-Switch; $sw.Margin = '8,0,8,0'; $sw.IsEnabled = $false; $sw.Tag = $t.Id
            [Windows.Automation.AutomationProperties]::SetName($sw, $t.Name)
            $sw.Add_Click({ param($src, $e) Update-Pending; Select-Row $script:Rows[$src.Tag] })
            [void](Add-At $grid $sw 3)
            $mb = [Windows.Controls.Button]::new(); $mb.Style = $window.FindResource('Btn'); $mb.Background = [Windows.Media.Brushes]::Transparent; $mb.BorderBrush = [Windows.Media.Brushes]::Transparent
            $mb.Padding = '8,0'; $mb.Tag = $t.Id; $mb.ToolTip = T 'Más info'; [Windows.Automation.AutomationProperties]::SetName($mb, (T 'Más info'))
            $chev = New-Icon 'chevron-down' 12 'Ink2'; $mb.Content = $chev
            $mb.Add_Click({ param($src) Switch-TweakMore $script:Rows[$src.Tag] })
            [void](Add-At $grid $mb 4)
            [void](Add-At $outer $grid 1)
            [void]$stack.Children.Add($outer)
            $more = [Windows.Controls.Border]::new(); $more.Visibility = 'Collapsed'; $more.BorderThickness = '0,1,0,0'; $more.Padding = '57,12,20,14'
            $more.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Rule')
            [void]$stack.Children.Add($more)
            $card.Child = $stack
            $grid.Add_MouseLeftButtonUp({
                param($src, $e)
                if ($e.OriginalSource -is [Windows.FrameworkElement] -and ($e.OriginalSource.TemplatedParent -is [Windows.Controls.Primitives.ButtonBase] -or $e.OriginalSource -is [Windows.Controls.Primitives.ButtonBase])) { return }
                Select-Row $script:Rows[$src.Tag]
            })
            $grid.Add_MouseLeftButtonDown({
                param($src, $e)
                if ($e.ClickCount -eq 2) { $row = $script:Rows[$src.Tag]; if ($row.Switch.IsEnabled -and -not $script:Busy) { $row.Switch.IsChecked = -not [bool]$row.Switch.IsChecked; Update-Pending; Select-Row $row } }
            })
            [void]$ui.TweakList.Children.Add($card)
            $script:Rows[$t.Id] = @{ Tweak = $t; Switch = $sw; Card = $card; Border = $card; State = $state; Mark = $mark; Applied = $null; Desc = $ds; More = $more; Chev = $chev }
        }
    }
    # "More info": the full description, whether it can be undone and what it really touches on this PC
    function Switch-TweakMore($row) {
        $m = $row.More
        if ($m.Visibility -eq 'Visible') { $m.Visibility = 'Collapsed'; $row.Chev.Text = [string][char]0xE70D; return }
        $t = $row.Tweak; $sp = [Windows.Controls.StackPanel]::new()
        $d = New-Text $(if ($t.Detail) { $t.Detail } else { $t.Desc }) 13 'Ink2'; $d.Margin = '0,0,0,8'; [void]$sp.Children.Add($d)
        $chips = [Windows.Controls.WrapPanel]::new(); $chips.Margin = '0,0,0,8'
        [void]$chips.Children.Add((New-Chip $(if ($t.Presets -contains 'R') { 'En Recomendado' } elseif ($t.Presets -contains 'A') { 'En Avanzado' } else { 'Solo a mano' }) 'Subtle' 'Ink2'))
        if ($t.Reboot) { [void]$chips.Children.Add((New-Chip 'Pide reinicio' 'Subtle' 'Ink2')) }
        [void]$chips.Children.Add((New-Chip $(if ($t.Irreversible) { 'Sin vuelta atrás' } else { 'Se puede deshacer' }) 'Subtle' 'Ink2'))
        [void]$sp.Children.Add($chips)
        $revert = [bool]$row.Applied
        $diff = try { @(Get-TweakDiff $t $revert) } catch { @() }
        $ht = New-Text $(if ($revert) { 'Qué vuelve al revertir' } else { 'Qué cambia al aplicar' }) 12 'Ink' 'SemiBold'; $ht.Margin = '0,4,0,4'; [void]$sp.Children.Add($ht)
        $shown = 0
        foreach ($l in $diff) {
            if ($shown -ge 12) { [void]$sp.Children.Add((New-Text "y $($diff.Count - 12) más" 12 'Ink2')); break }
            $li = New-Cols @('*', 'Auto'); $li.Margin = '0,2,0,2'
            $tg = New-Mono $l.Target 11.5 'Ink2'; $tg.TextTrimming = 'CharacterEllipsis'; $tg.ToolTip = $l.Target; [void](Add-At $li $tg 0)
            $vv = New-Mono $(if ($l.Same) { T "$($l.Before)" } else { "$(T $l.Before)  →  $(T $l.After)" }) 11.5 $(if ($l.Same) { 'Muted' } else { 'Ink' }); $vv.Margin = '16,0,0,0'
            [void](Add-At $li $vv 1)
            [void]$sp.Children.Add($li); $shown++
        }
        if (-not $diff) { [void]$sp.Children.Add((New-Text 'Nada que cambiar en este equipo.' 12 'Ink2')) }
        $m.Child = $sp; $m.Visibility = 'Visible'; $row.Chev.Text = [string][char]0xE70E
        Start-FadeIn $sp 0 4
    }
    # Only the first two categories before showing the window (what is visible on open); the rest right after
    # the first render, so the window appears sooner. This event is registered before the state
    # check, so all rows exist by the time that starts.
    foreach ($cat in @($cats | Select-Object -First 2)) { Add-CategoryRows $cat }
    $window.Add_ContentRendered({
        foreach ($cat in @($cats | Select-Object -Skip 2)) { Add-CategoryRows $cat }
        if ($script:CurrentPage -and $Pages[$script:CurrentPage].Tab) { Show-Page $script:CurrentPage }
    })

    # ---------- details: exactly what changes
    function Select-Row($row) {
        if ($script:Selected -and $script:Selected -ne $row) { $script:Selected.Card.ClearValue([Windows.Controls.Border]::BorderBrushProperty) }
        $script:Selected = $row
        if ($row) { $row.Card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'Accent') }
        Show-Detail $row
    }    function Show-Detail($row) {
        $d = $ui.Detail; $d.Children.Clear()
        if (-not $row) {
            $well = [Windows.Controls.Border]::new(); $well.Width = 40; $well.Height = 40; $well.CornerRadius = 8; $well.HorizontalAlignment = 'Left'
            $well.SetResourceReference($BgProp, 'AccentSoft')
            $wi = New-Icon 'sliders-horizontal' 18 'Accent'; $wi.HorizontalAlignment = 'Center'; $well.Child = $wi
            [void]$d.Children.Add($well)
            $et = New-Text 'Elige un ajuste' 20 'Ink' 'SemiBold'; $et.FontFamily = $window.FindResource('Display'); $et.Margin = '0,16,0,6'
            [void]$d.Children.Add($et)
            [void]$d.Children.Add((New-Text 'Toca un ajuste para ver qué cambia, o pulsa Recomendado.' 14 'Ink2'))
            return
        }
        $t = $row.Tweak
        $hd = New-Cols @('52', '*')
        [void](Add-At $hd (New-IconWell $(if ($TweakIcons.ContainsKey($t.Id)) { $TweakIcons[$t.Id] } else { 'gear-six' }) 36) 0)
        $tt = New-Text $t.Name 18 'Ink' 'SemiBold'; $tt.FontFamily = $window.FindResource('Display'); $tt.VerticalAlignment = 'Center'
        [void](Add-At $hd $tt 1)
        [void]$d.Children.Add($hd)
        $ds = New-Text $(if ($t.Detail) { $t.Detail } else { $t.Desc }) 13.5 'Ink2'; $ds.Margin = '0,10,0,10'; [void]$d.Children.Add($ds)

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
            # simple view: no keys or values, only whether something changes and how to see it
            $n = $changes
            $box = [Windows.Controls.Border]::new(); $box.CornerRadius = 10; $box.Padding = '14,12'; $box.Margin = '0,16,0,0'
            $box.SetResourceReference($BgProp, 'Subtle')
            $bg = New-Cols @('Auto', '*')
            $bi = New-Icon $(if ($revert -or $n) { 'arrow-counter-clockwise' } else { 'check' }) 16 'Ink2'; $bi.Margin = '0,2,12,0'; $bi.VerticalAlignment = 'Top'
            [void](Add-At $bg $bi 0)
            $msg = if ($t.Irreversible -and -not $revert) { 'Este no se puede deshacer desde el panel. Lee bien la descripción.' }
                   elseif ($revert) { 'Está aplicado. Si lo desactivas, Windows vuelve a como estaba.' }
                   elseif ($n) { 'Al aplicarlo se guarda cómo estaba, para poder revertirlo cuando quieras.' }
                   else { 'En este equipo ya está así.' }
            [void](Add-At $bg (New-Text $msg 13.5 'Ink') 1)
            $box.Child = $bg
            [void]$d.Children.Add($box)
            $pro = New-Text 'Con «Mostrar detalles técnicos» ves las claves, servicios y tareas.' 12 'Ink2'; $pro.Margin = '0,12,0,0'
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

    # ---------- search (Ctrl+K): tools, tweak groups and each tweak, by name, description, id or keywords
    $script:SearchIndex = $null
    function Get-SearchIndex {
        $items = @()
        foreach ($k in $Pages.Keys) {
            $pg = $Pages[$k]
            if ($pg.Header -or $pg.Hub -or $k -eq 'all' -or ($pg.ProOnly -and -not $script:Pro)) { continue }
            $kw = if ($pg.Tool -and $pg.Tool.keywords) { @($pg.Tool.keywords) -join ' ' } else { '' }
            $cat = if ($pg.Parent) { T $Pages[$pg.Parent].Title } else { '' }
            $items += [pscustomobject]@{ Key = $k; Tweak = $null; Icon = $pg.Icon; Name = (T $pg.Label); Cat = $cat; Text = "$(T $pg.Label) $(T $pg.Desc) $k $kw".ToLower() }
        }
        foreach ($row in $script:Rows.Values) {
            $tw = $row.Tweak
            $items += [pscustomobject]@{ Key = $tw.Cat; Tweak = $tw.Id; Icon = $(if ($TweakIcons.ContainsKey($tw.Id)) { $TweakIcons[$tw.Id] } else { 'gear-six' }); Name = $tw.Name
                                         Cat = (T $Pages[$tw.Cat].Title); Text = "$($tw.Name) $($tw.Desc) $($tw.Id)".ToLower() }
        }
        $items
    }
    function Update-Search {
        $ui.SearchHint.Visibility = if ($ui.SearchBox.Text) { 'Collapsed' } else { 'Visible' }
        $q = $ui.SearchBox.Text.Trim().ToLower()
        if (-not $q) { $ui.SearchPopup.IsOpen = $false; return }
        if (-not $script:SearchIndex) { $script:SearchIndex = @(Get-SearchIndex) }
        $words = @($q -split '\s+')
        $hits = @($script:SearchIndex | Where-Object { $x = $_; -not @($words | Where-Object { $x.Text -notlike "*$_*" }).Count } |
                  Sort-Object { if ($_.Name.ToLower().StartsWith($words[0])) { 0 } elseif (-not $_.Tweak) { 1 } else { 2 } } | Select-Object -First 12)
        $ui.SearchList.Items.Clear()
        foreach ($h in $hits) {
            $g = New-Cols @('32', '*', 'Auto'); $g.Tag = $h
            [void](Add-At $g (New-Icon $h.Icon 16 'Ink2') 0)
            $tx = [Windows.Controls.StackPanel]::new()
            $n = New-Text $h.Name 13.5 'Ink'; $n.TextTrimming = 'CharacterEllipsis'; $n.TextWrapping = 'NoWrap'; $n.Text = $h.Name; [void]$tx.Children.Add($n)
            if ($h.Cat) { $c = New-Text $h.Cat 11.5 'Ink2'; $c.Text = $h.Cat; [void]$tx.Children.Add($c) }
            [void](Add-At $g $tx 1)
            if ($h.Tweak) {
                $r = $script:Rows[$h.Tweak]
                $st = New-Text $(if ($r.Applied -eq $true) { 'Aplicado' } elseif ($r.Applied -eq $false) { 'No aplicado' } else { '' }) 11.5 $(if ($r.Applied -eq $true) { 'Green' } else { 'Ink2' })
                $st.VerticalAlignment = 'Center'; $st.Margin = '10,0,0,0'; [void](Add-At $g $st 2)
            }
            [void]$ui.SearchList.Items.Add($g)
        }
        if (-not $hits.Count) { $em = [Windows.Controls.ListBoxItem]::new(); $em.IsEnabled = $false; $em.Content = (New-Text 'Sin resultados' 13 'Ink2'); [void]$ui.SearchList.Items.Add($em) }
        else { $ui.SearchList.SelectedIndex = 0 }
        $ui.SearchPopup.IsOpen = $true
    }
    function Open-SearchHit($h) {
        if (-not $h) { return }
        $ui.SearchPopup.IsOpen = $false; $ui.SearchBox.Text = ''
        Select-NavKey $h.Key
        if ($h.Tweak) {
            $script:SearchJump = $script:Rows[$h.Tweak]; Select-Row $script:SearchJump
            [void]$window.Dispatcher.BeginInvoke([Action] { if ($script:SearchJump) { $script:SearchJump.Card.BringIntoView() } }, [Windows.Threading.DispatcherPriority]::Loaded)
        }
    }
    $ui.SearchHint.Text = T 'Buscar'
    $ui.SearchBox.Add_TextChanged({ Update-Search })
    $ui.SearchBox.Add_PreviewKeyDown({
        param($src, $e)
        $n = $ui.SearchList.Items.Count
        switch ($e.Key) {
            'Down'   { if ($n) { $ui.SearchList.SelectedIndex = [math]::Min($n - 1, $ui.SearchList.SelectedIndex + 1) }; $e.Handled = $true }
            'Up'     { if ($n) { $ui.SearchList.SelectedIndex = [math]::Max(0, $ui.SearchList.SelectedIndex - 1) }; $e.Handled = $true }
            'Return' { if ($ui.SearchList.SelectedItem -is [Windows.Controls.Grid]) { Open-SearchHit $ui.SearchList.SelectedItem.Tag }; $e.Handled = $true }
            'Escape' { $ui.SearchBox.Text = ''; $ui.SearchPopup.IsOpen = $false; [void]$ui.Nav.Focus(); $e.Handled = $true }
        }
    })
    $ui.SearchList.Add_MouseLeftButtonUp({ if ($ui.SearchList.SelectedItem -is [Windows.Controls.Grid]) { Open-SearchHit $ui.SearchList.SelectedItem.Tag } })
    $window.Add_PreviewKeyDown({
        param($src, $e)
        if ($e.Key -eq 'K' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) { [void]$ui.SearchBox.Focus(); $ui.SearchBox.SelectAll(); $e.Handled = $true }
    })
    # ---------- System
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

    # ---------- live monitor (in the background so the window doesn't freeze)
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
    # don't close with the booster on without warning: paused services would stay paused
    $window.Add_Closing({
        param($src, $e)
        # no prompt when switching language: the booster stays on and the new window reads it from boost.json
        if (-not $script:Relaunch -and $script:BoostFile -and (Test-Path $script:BoostFile) -and $script:IsAdmin) {
            $r = [Windows.MessageBox]::Show($window, (T "El Game Booster sigue activo: hay servicios pausados y apps cerradas.`n`n¿Restaurarlo todo antes de salir?"), 'OptiEleven', 'YesNoCancel', 'Warning')
            if ($r -eq 'Cancel') { $e.Cancel = $true }
            elseif ($r -eq 'Yes') { try { Stop-Boost } catch { Write-Log "Booster: $($_.Exception.Message)" 'ERROR' } }
        }
    })

    $script:Stats = [ordered]@{}
    $StatColors = @{ Cpu = 'Ink'; Gpu = 'Ink'; Ram = 'Ink'; Temp = 'Ink'; Proc = 'Ink'; Svc = 'Ink'; Tweaks = 'Ink' }
    foreach ($s in @(@('Cpu', 'CPU'), @('Gpu', 'GPU'), @('Ram', 'RAM'), @('Temp', 'Temperatura'), @('Proc', 'Procesos'), @('Svc', 'Servicios'), @('Tweaks', 'Ajustes aplicados'))) {
        $l = New-Text $s[1] 12 'Ink2'; $l.Margin = '0,0,6,0'; $l.VerticalAlignment = 'Center'
        $v = New-Text '--' 12 $StatColors[$s[0]] 'SemiBold'; $v.TextWrapping = 'NoWrap'; $v.Margin = '0,0,20,0'; $v.VerticalAlignment = 'Center'
        [void]$ui.StatList.Children.Add($l); [void]$ui.StatList.Children.Add($v)
        $script:Stats[$s[0]] = $v
        if ($s[0] -in 'Proc', 'Svc') { $script:ProOnly += $l, $v }   # not needed in the simple view
    }
    $script:Stats.Temp.ToolTip = T 'Windows solo da la temperatura con permisos de administrador, y no en todos los equipos.'
    $updateStats = {
        $T = $script:Telemetry
        if (-not $T.Ready) { return }
        $script:Stats.Cpu.Text = (T '{0:N0} %') -f $T.Cpu
        $script:Stats.Gpu.Text = (T '{0:N0} %') -f $T.Gpu
        $script:Stats.Ram.Text = (T '{0:N1} / {1:N0} GB') -f ($T.RamUsed / 1GB), ($T.RamTotal / 1GB)
        Update-HomeStats
        $script:Stats.Temp.Text = if ($null -ne $T.Temp) { "$($T.Temp) °C" } else { T 'n/d' }
        $script:Stats.Proc.Text = (T "$($T.Proc)")
        $script:Stats.Svc.Text = (T "$($T.Svc)")
    }
    $timer = New-Timer 1.5 $updateStats

    # ---------- state and change sheet
    $script:Busy = $false
    function Get-Pending { @($script:Rows.Values | Where-Object { $null -ne $_.Applied -and ([bool]$_.Switch.IsChecked -ne $_.Applied) }) }
    function Update-Pending {
        $applied = 0
        foreach ($row in $script:Rows.Values) {
            if ($null -eq $row.Applied) { Set-Chip $row.State 'No disponible' 'Subtle' 'Ink2'; $row.Mark.Visibility = 'Hidden'; continue }
            if ($row.Applied) { $applied++ }
            $want = [bool]$row.Switch.IsChecked
            if ($want -ne $row.Applied) {
                Set-Chip $row.State $(if ($want) { 'Se aplicará' } else { 'Se revertirá' }) 'Accent' 'AccentInk'
                $row.Mark.Visibility = 'Visible'
            }
            else {
                if ($row.Applied) { Set-Chip $row.State 'Aplicado' 'GreenSoft' 'Green' }
                elseif (Get-Backup $row.Tweak.Id) { Set-Chip $row.State 'Cambiado fuera' 'AmberSoft' 'Amber'; $row.State.ToolTip = T 'Lo aplicaste con el panel, pero Windows u otro programa lo ha vuelto a cambiar.' }
                else { Set-Chip $row.State $null $null $null }
                $row.Mark.Visibility = 'Hidden'
            }
        }
        $script:Stats.Tweaks.Text = T "$applied de $($script:Rows.Count)"
        Update-HomeStats
        $pend = Get-Pending
        $na = @($pend | Where-Object { $_.Switch.IsChecked }).Count; $nr = $pend.Count - $na
        $ui.LedgerCount.Text = (T "$($pend.Count)"); $ui.LedgerApply.Text = (T "$na"); $ui.LedgerRevert.Text = (T "$nr")
        $ui.LedgerReboot.Text = T $(if ($pend | Where-Object { $_.Tweak.Reboot }) { 'sí' } else { 'no' })
        $ui.QueueText.Text = (T "$($pend.Count)")
        $ui.QueuePill.SetResourceReference($BgProp, $(if ($pend.Count) { 'Accent' } else { 'Subtle' }))
        $ui.QueueText.SetResourceReference($FgProp, $(if ($pend.Count) { 'AccentInk' } else { 'Ink2' }))
        $ui.LedgerList.Children.Clear()
        if ($pend.Count -eq 0) {
            $ui.LedgerSub.Text = T 'Nada pendiente'
            $e = New-Text 'Mueve un interruptor o elige un preset.' 12.5 'Ink2'; $e.Margin = '0,2,0,0'
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
        if (-not $script:IsAdmin) { $ui.LedgerSub.Text = T 'Sin permisos de administrador' }
        $ui.BtnApply.IsEnabled = $script:IsAdmin -and $pend.Count -gt 0 -and -not $script:Busy
        $ui.BtnDiscard.IsEnabled = $pend.Count -gt 0 -and -not $script:Busy
    }
    function Update-Status {
        $ui.LedgerSub.Text = T 'Comprobando el estado...'; Update-Ui
        $script:AppxNames = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object Name)
        $i = 0
        foreach ($row in @($script:Rows.Values)) {
            $row.Applied = try { Test-Tweak $row.Tweak } catch { $null }
            if ((++$i % 4) -eq 0) { Update-Ui }   # the window stays responsive while checking
            if ($null -eq $row.Applied) { $row.Switch.IsEnabled = $false }
            else { $row.Switch.IsEnabled = -not $script:Busy; $row.Switch.IsChecked = [bool]$row.Applied }
        }
        Update-Pending
        Show-Detail $script:Selected
        # the open page may depend on the state (e.g. History and its undo buttons): it is redrawn with its "onShow"
        $cp = if ($script:CurrentPage) { $Pages[$script:CurrentPage] }
        if ($cp -and $cp.OnShow -and $script:ModuleCache.ContainsKey($script:CurrentPage)) { try { & $cp.OnShow } catch {} }
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

    # ---------- pages
    $script:ModuleCache = @{}
    function Select-NavKey([string]$Key) {
        if (-not $Pages.Contains($Key)) { return }
        # the navigation highlights the page or its category; then the requested page opens
        $navKey = if ($Pages[$Key].Nav) { $Key } else { $Pages[$Key].Parent }
        $item = $null; foreach ($it in $ui.Nav.Items) { if ($it -is [Windows.Controls.Grid] -and $it.Tag -eq $navKey) { $item = $it } }
        $script:NavTarget = $Key
        try { if ($item -and $ui.Nav.SelectedItem -ne $item) { $ui.Nav.SelectedItem = $item } else { Show-Page $Key } } finally { $script:NavTarget = $null }
    }
    function Show-Page([string]$Key) {
        $pg = $Pages[$Key]
        # a category with only one item opens that item directly
        if ($pg.Hub) { $vis = @($pg.Hub | Where-Object { $Pages[$_] -and -not ($Pages[$_].ProOnly -and -not $script:Pro) }); if ($vis.Count -eq 1) { Show-Page $vis[0]; return } }
        $script:CurrentPage = $Key
        $ui.PageTitle.Text = (T $pg.Title); $ui.PageDesc.Text = (T $pg.Desc)
        $parent = if ($pg.Parent) { $Pages[$pg.Parent] }
        $multi = $parent -and @($parent.Hub | Where-Object { $Pages[$_] -and -not ($Pages[$_].ProOnly -and -not $script:Pro) }).Count -gt 1
        if ($multi) { $ui.Crumb.Text = "$(T $parent.Title)  ›"; $ui.Crumb.Tag = $pg.Parent; $ui.Crumb.Visibility = 'Visible' } else { $ui.Crumb.Visibility = 'Collapsed' }
        $ui.PageDesc.Visibility = if ($pg.Desc) { 'Visible' } else { 'Collapsed' }
        Start-FadeIn $ui.PageTitle 0 4; Start-FadeIn $ui.PageDesc 30 4
        $isModule = [bool]$pg.Module -or [bool]$pg.Hub
        $isTweaks = [bool]$pg.Tab
        $ui.TweakPage.Visibility  = if ($isTweaks) { 'Visible' } else { 'Collapsed' }
        $ui.ToolsPage.Visibility  = if ($Key -eq 'tools') { 'Visible' } else { 'Collapsed' }
        $ui.LogPage.Visibility    = if ($Key -eq 'log') { 'Visible' } else { 'Collapsed' }
        $ui.ModulePage.Visibility = if ($isModule) { 'Visible' } else { 'Collapsed' }
        $ui.PresetBar.Visibility  = if ($isTweaks) { 'Visible' } else { 'Collapsed' }
        $ui.TabScroll.Visibility  = if ($Key -eq 'all') { 'Visible' } else { 'Collapsed' }
        $ui.Rail.Visibility       = if ($isTweaks) { 'Visible' } else { 'Collapsed' }
        if ($isTweaks) {
            Update-Tabs $Key
            foreach ($cat in $script:GroupHeads.Keys) {
                $script:GroupHeads[$cat][0].Visibility = if ($Key -eq 'all') { 'Visible' } else { 'Collapsed' }
            }
            foreach ($row in $script:Rows.Values) { $row.Card.Visibility = if ($Key -eq 'all' -or $row.Tweak.Cat -eq $Key) { 'Visible' } else { 'Collapsed' } }
            $ui.TweakPage.ScrollToTop()
            Start-Stagger @($ui.TweakList.Children) 12
            # nothing is selected automatically: the right pane explains what to do until you pick a tweak
            if ($script:Selected -and $script:Selected.Card.Visibility -ne 'Visible') { Select-Row $null }
        }
        if ($pg.Hub) {
            $ui.ModuleHost.Content = New-HubView $Key
            $ui.ModulePage.ScrollToTop(); Start-Stagger @($ui.ModuleHost.Content.Children) 10
        }
        elseif ($isModule) {
            if (-not $script:ModuleCache.ContainsKey($Key)) {
                $ui.ModuleHost.Content = (New-Loader (T "Cargando $(T $pg.Title)...")); Update-Ui
                try { $script:ModuleCache[$Key] = & $pg.Module }
                catch {
                    Write-Log "$($pg.Title): $($_.Exception.Message) (línea $($_.InvocationInfo.ScriptLineNumber))" 'ERROR'
                    $script:ModuleCache[$Key] = New-Text "No se pudo cargar este apartado: $($_.Exception.Message)" 14 'Red'
                }
            }
            $ui.ModuleHost.Content = $script:ModuleCache[$Key]
            $ui.ModulePage.ScrollToTop()
            if ($ui.ModuleHost.Content -is [Windows.Controls.Panel]) { Start-Stagger @($ui.ModuleHost.Content.Children) 10 } else { Start-FadeIn $ui.ModuleHost }
            if ($pg.OnShow) { try { & $pg.OnShow } catch { Write-Log "$($pg.Title): $($_.Exception.Message)" 'ERROR' } }   # "onShow" from tool.json
        }
    }
    $ui.Nav.Add_SelectionChanged({ Update-NavColors; if ($ui.Nav.SelectedItem) { Show-Page $(if ($script:NavTarget) { $script:NavTarget } else { [string]$ui.Nav.SelectedItem.Tag }) } })
    $ui.Crumb.Add_MouseLeftButtonUp({ if ($ui.Crumb.Tag) { Select-NavKey ([string]$ui.Crumb.Tag) } })
    function Select-Preset([string]$Code, [string]$Label) {
        $n = 0
        foreach ($row in $script:Rows.Values) {
            if ($null -ne $row.Applied -and $row.Tweak.Presets -contains $Code -and -not $row.Switch.IsChecked) { $row.Switch.IsChecked = $true; $n++ }
        }
        if (-not ($script:CurrentPage -and $Pages[$script:CurrentPage].Tab)) { Select-NavKey 'all' }
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

    # ---------- Pro view
    function Update-ProNav { if ($script:CurrentPage -and $Pages[$script:CurrentPage].Hub) { Show-Page $script:CurrentPage } }   # Activity shows under System only with technical details on
    function Set-ProView([bool]$On) {
        $script:Pro = $On; $script:SearchIndex = $null
        try { if ($On) { Set-Content -LiteralPath $script:ProFile -Value 'on' } else { Remove-Item -LiteralPath $script:ProFile -ErrorAction SilentlyContinue } } catch {}
        $vis = if ($On) { 'Visible' } else { 'Collapsed' }
        foreach ($el in $script:ProOnly) { $el.Visibility = $vis }
        $ui.LedgerStats.Visibility = $vis
        Update-ProNav
        Set-IconBrush $ui.ProIcon.Content $(if ($On) { 'Accent' } else { 'Ink2' })
        if ($ui.ProSwitch.IsChecked -ne $On) { $ui.ProSwitch.IsChecked = $On }
        # the sections are rebuilt with or without details
        $script:ModuleCache = @{}
        if (-not $On -and $script:CurrentPage -eq 'log') { Select-NavKey 'c-system'; return }
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
    if ($script:Pro) { Set-IconBrush $ui.ProIcon.Content 'Accent' }

    # ---------- startup
    $ui.BtnApply.IsEnabled = $false; $ui.BtnDiscard.IsEnabled = $false
    Update-Pending
    Select-NavKey $Page
    if (-not $ui.Nav.SelectedItem) { Select-NavKey 'home' }

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
    # language change: reopens on the same section (if closing was cancelled, the window stays open and this is never reached)
    if ($script:Relaunch) { Start-Panel $script:Relaunch }
}
catch {
    $script:LogBox = $null
    Write-Log "Error al iniciar el panel: $($_.Exception.Message) | $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim()) | $($_.ScriptStackTrace -replace "`r?`n", ' <- ')" 'ERROR'
    [void][System.Windows.MessageBox]::Show((T 'Error al iniciar el panel:') + "`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)", 'OptiEleven', 'OK', 'Error')
}
