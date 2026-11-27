#Requires -Version 5.1
<#
  Builds a release of OptiEleven, the same way on your PC and in GitHub Actions (.github/workflows/release.yml):
    1. runs tests\Run-Tests.ps1 if it exists, and stops if it fails
    2. takes the committed files (git archive HEAD), so uncommitted changes are never released
    3. compiles with the C# compiler of .NET Framework 4.8 (part of Windows), nothing to install:
         OptiEleven\OptiEleven.exe                launcher (launcher\Launcher.cs)
         OptiEleven\native\OptiEleven.Native.dll  the $GpSource block of OptiEleven.ps1
         OptiEleven\native\OptiEleven-Apps.exe    assets\installer.cs, as a stub the panel appends the app list to
       so users' PCs no longer run Add-Type or csc.exe for these
    4. adds LICENSE and THIRD-PARTY.md, signs with build\Sign.ps1 (skipped when there is no certificate)
    5. writes dist\OptiEleven.zip and dist\SHA256SUMS.txt
  Usage:  powershell -ExecutionPolicy Bypass -File build\Build.ps1 [-SkipTests]
#>
param([switch]$SkipTests)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Run Build.ps1 with Windows PowerShell 5.1 (powershell.exe): the launcher links its System.Management.Automation.' }
if (-not (Test-Path $csc)) { throw "C# compiler not found: $csc" }

function Write-Step([string]$Text) { Write-Host "== $Text" -ForegroundColor Cyan }
function Invoke-Csc([string[]]$CscArgs) {
    $log = & $csc /nologo /optimize+ /platform:anycpu @CscArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "csc failed:`n$(($log | Out-String).Trim())" }
}
function Get-ShortHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    -join ($sha.ComputeHash($Bytes)[0..5] | ForEach-Object { $_.ToString('x2') })
}
# the panel compares this "Comments" field with the hash of its own source before loading a prebuilt file
function New-Stamp([string]$Dir, [string]$Hash) {
    $f = Join-Path $Dir "stamp-$Hash.cs"
    [IO.File]::WriteAllText($f, "[assembly: System.Reflection.AssemblyDescription(`"$Hash`")]")
    $f
}

$tests = Join-Path $root 'tests\Run-Tests.ps1'
if ((Test-Path $tests) -and -not $SkipTests) {
    Write-Step 'Tests'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tests
    if ($LASTEXITCODE -ne 0) { throw "tests\Run-Tests.ps1 failed (exit code $LASTEXITCODE)" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('optieleven-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    Write-Step 'Sources (git archive HEAD)'
    if (git -C $root status --porcelain) { Write-Warning 'There are uncommitted changes; they are not part of this build.' }
    $srcZip = Join-Path $tmp 'src.zip'
    & git -C $root archive --format=zip -o $srcZip HEAD OptiEleven launcher LICENSE THIRD-PARTY.md
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
    $src = Join-Path $tmp 'src'
    Expand-Archive -LiteralPath $srcZip -DestinationPath $src
    $app = Join-Path $src 'OptiEleven'
    $native = Join-Path $app 'native'
    New-Item -ItemType Directory -Path $native | Out-Null

    Write-Step 'Native DLL'
    $core = Join-Path $app 'OptiEleven.ps1'
    $errs = $null; $ast = [Management.Automation.Language.Parser]::ParseFile($core, [ref]$null, [ref]$errs)
    if ($errs) { throw "OptiEleven.ps1 does not parse: $($errs[0].Message)" }
    $assign = $ast.Find({ param($a) $a -is [Management.Automation.Language.AssignmentStatementAst] -and $a.Left.VariablePath.UserPath -eq 'GpSource' }, $false)
    if (-not $assign) { throw 'No $GpSource block in OptiEleven.ps1' }
    $gp = $assign.Right.Expression.Value
    $gpHash = Get-ShortHash ([Text.Encoding]::UTF8.GetBytes($gp))
    $gpFile = Join-Path $tmp 'native.cs'
    [IO.File]::WriteAllText($gpFile, $gp, (New-Object Text.UTF8Encoding $true))
    Invoke-Csc @('/target:library', "/out:$(Join-Path $native 'OptiEleven.Native.dll')", $gpFile, (New-Stamp $tmp $gpHash))

    Write-Step 'App installer stub'
    $assets = Join-Path $app 'assets'
    $icon = Join-Path $assets 'optieleven.ico'
    $instCs = Join-Path $assets 'installer.cs'
    $instHash = Get-ShortHash ([IO.File]::ReadAllBytes($instCs))
    $stubCs = Join-Path $tmp 'installer.cs'
    [IO.File]::WriteAllText($stubCs, [IO.File]::ReadAllText($instCs).Replace('__APPS__', ''), (New-Object Text.UTF8Encoding $true))
    # same manifest the panel uses when it compiles the installer itself (tools\install\tool.ps1)
    $instManifest = Join-Path $tmp 'installer.manifest'
    [IO.File]::WriteAllText($instManifest, '<?xml version="1.0" encoding="utf-8"?><assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1"><assemblyIdentity version="1.0.0.0" name="OptiEleven.AppInstaller"/>' +
        '<trustInfo xmlns="urn:schemas-microsoft-com:asm.v2"><security><requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3"><requestedExecutionLevel level="requireAdministrator" uiAccess="false"/></requestedPrivileges></security></trustInfo>' +
        '<application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings><dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware></windowsSettings></application></assembly>')
    Invoke-Csc @('/target:winexe', "/out:$(Join-Path $native 'OptiEleven-Apps.exe')", "/win32manifest:$instManifest", "/win32icon:$icon",
        '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', $stubCs, (New-Stamp $tmp $instHash))

    Write-Step 'Launcher OptiEleven.exe'
    $launcher = Join-Path $src 'launcher'
    $sma = [PSObject].Assembly.Location   # System.Management.Automation of Windows PowerShell 5.1, from the GAC
    Invoke-Csc @('/target:winexe', "/out:$(Join-Path $app 'OptiEleven.exe')", "/win32manifest:$(Join-Path $launcher 'app.manifest')", "/win32icon:$icon",
        "/r:$sma", '/r:System.Windows.Forms.dll', (Join-Path $launcher 'Launcher.cs'))

    Copy-Item (Join-Path $src 'LICENSE'), (Join-Path $src 'THIRD-PARTY.md') -Destination $app

    Write-Step 'Signing'
    & (Join-Path $PSScriptRoot 'Sign.ps1') -Path $app

    Write-Step 'Zip and SHA256SUMS.txt'
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    $zip = Join-Path $dist 'OptiEleven.zip'
    $sums = Join-Path $dist 'SHA256SUMS.txt'
    Remove-Item -LiteralPath $zip, $sums -Force -ErrorAction SilentlyContinue
    Compress-Archive -LiteralPath $app -DestinationPath $zip   # the zip root holds the OptiEleven folder
    $lines = foreach ($f in @($zip)) { '{0}  {1}' -f (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant(), (Split-Path $f -Leaf) }
    [IO.File]::WriteAllText($sums, (($lines -join "`n") + "`n"))
    Get-Content -LiteralPath $sums
    Write-Step "Done: $dist"
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
