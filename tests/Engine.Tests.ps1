# Engine round-trip against HKCU:\Software\OptiEleven-Test\<random> only, plus Import-Tweaks on temp folders.
# The core's functions are loaded from OptiEleven.ps1 through the AST, so no window opens and no admin is needed.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    . ([scriptblock]::Create((Get-EngineCode)))

    $script:Temp        = Join-Path ([IO.Path]::GetTempPath()) ("OptiEleven-Test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:Temp -Force | Out-Null
    $script:Root        = $script:Temp
    $script:BackupFile  = Join-Path $script:Temp 'backup.json'
    $script:HistoryFile = Join-Path $script:Temp 'history.jsonl'
    $script:LogFile     = Join-Path $script:Temp 'panel.log'
    $script:Store       = [pscustomobject]@{}
    $script:LangCode    = 'es'
    $script:LangStrings = $null; $script:LangPatterns = @()
    $script:LogBox      = $null
    if ($script:BackupFile -like "*$env:ProgramData*") { throw 'refusing to run against ProgramData' }

    # quiet stand-in for the core's Write-Log, which also keeps what was logged
    $script:Logged = New-Object System.Collections.Generic.List[string]
    function Write-Log([string]$Msg, [string]$Level = 'INFO') { $script:Logged.Add("$Level $Msg") }

    $script:Key = "HKCU:\Software\OptiEleven-Test\" + [guid]::NewGuid().ToString('N')
    New-Item -Path $script:Key -Force | Out-Null

    function New-TestTweak([string]$Id, $Reg) {
        @{ Id = $Id; Cat = 'Test'; Risk = 'Seguro'; Name = $Id; Desc = ''; Presets = @(); Reg = @($Reg) }
    }
}

AfterAll {
    if ($script:Key -and (Test-Path -LiteralPath $script:Key)) { Remove-Item -LiteralPath $script:Key -Recurse -Force }
    $parent = 'HKCU:\Software\OptiEleven-Test'
    if ((Test-Path $parent) -and -not (Get-ChildItem $parent) -and -not (Get-Item $parent).ValueCount) { Remove-Item $parent -Force }
    if ($script:Temp -and (Test-Path $script:Temp)) { Remove-Item -LiteralPath $script:Temp -Recurse -Force }
}

Describe 'Engine round-trip on a test registry key' {

    It 'creates a value that did not exist, then reverts to "did not exist"' {
        $t = New-TestTweak 'test-new' (RegV $script:Key 'NewVal' 1 'DWord')
        (Get-RegState $t.Reg[0]).Exists | Should -BeFalse
        Test-Tweak $t | Should -BeFalse

        Invoke-ApplyTweak $t
        Test-Tweak $t | Should -BeTrue
        (Get-ItemProperty -LiteralPath $script:Key).NewVal | Should -Be 1
        Get-Backup 'test-new' | Should -Not -BeNullOrEmpty
        Test-Path $script:BackupFile | Should -BeTrue

        Invoke-RevertTweak $t
        (Get-RegState $t.Reg[0]).Exists | Should -BeFalse
        Test-Tweak $t | Should -BeFalse
        Get-Backup 'test-new' | Should -BeNullOrEmpty
    }

    It 'overwrites an existing value, then restores its value and kind' {
        Set-RegValue $script:Key 'Existing' 5 'DWord'
        $t = New-TestTweak 'test-existing' (RegV $script:Key 'Existing' 'seven' 'String')
        $before = Get-RegState $t.Reg[0]
        Test-Tweak $t | Should -BeFalse

        Invoke-ApplyTweak $t
        Test-Tweak $t | Should -BeTrue
        (Get-RegState $t.Reg[0]).Kind | Should -Be 'String'

        Invoke-RevertTweak $t
        $after = Get-RegState $t.Reg[0]
        $after.Exists | Should -BeTrue
        $after.Value  | Should -Be $before.Value
        $after.Kind   | Should -Be $before.Kind
    }

    It 'with a backup, reverts to the previous state even when a Default is given' {
        $t = New-TestTweak 'test-default' (RegV $script:Key 'WithDef' 'on' 'String' 'off')
        Invoke-ApplyTweak $t
        Test-Tweak $t | Should -BeTrue
        Invoke-RevertTweak $t
        (Get-RegState $t.Reg[0]).Exists | Should -BeFalse
    }

    It 'without a backup (applied outside the panel), reverts to the Default' {
        $t = New-TestTweak 'test-default2' (RegV $script:Key 'WithDef2' 'on' 'String' 'off')
        Set-RegValue $script:Key 'WithDef2' 'on' 'String'
        Test-Tweak $t | Should -BeTrue
        Get-Backup 'test-default2' | Should -BeNullOrEmpty
        Invoke-RevertTweak $t
        $s = Get-RegState $t.Reg[0]
        $s.Exists | Should -BeTrue
        $s.Value  | Should -Be 'off'
    }

    It 'Get-ChangeList reports before and after for apply and revert' {
        $t = New-TestTweak 'test-diff' (RegV $script:Key 'DiffVal' 3 'DWord')
        $chg = @(Get-ChangeList $t $false)
        $chg.Count | Should -Be 1
        $chg[0].what   | Should -BeLike '*\DiffVal'
        $chg[0].before | Should -Be '(no existe)'
        $chg[0].after  | Should -Be '3 (DWord)'

        Invoke-ApplyTweak $t
        @(Get-ChangeList $t $false).Count | Should -Be 0   # nothing left to change
        $rev = @(Get-ChangeList $t $true)
        $rev.Count | Should -Be 1
        $rev[0].before | Should -Be '3 (DWord)'
        $rev[0].after  | Should -Be '(no existe)'
        Invoke-RevertTweak $t
    }

    It 'Invoke-Tweaks writes apply and revert history entries with ok=true' {
        $t = New-TestTweak 'test-history' (RegV $script:Key 'HistVal' 1 'DWord')
        Invoke-Tweaks @($t) 'Apply' | Out-Null
        Test-Tweak $t | Should -BeTrue
        Invoke-Tweaks @($t) 'Revert' | Out-Null
        Test-Tweak $t | Should -BeFalse

        $h = @(Get-History | Where-Object { $_.id -eq 'test-history' })
        $h.Count | Should -Be 2
        $h[0].action | Should -Be 'apply'
        $h[1].action | Should -Be 'revert'
        $h | ForEach-Object { $_.ok | Should -BeTrue; $_.source | Should -Be 'tweak' }
        $h[0].changes[0].before | Should -Be '(no existe)'
        $h[0].changes[0].after  | Should -Be '1 (DWord)'
        $h[1].changes[0].before | Should -Be '1 (DWord)'
    }

    It 'never writes to ProgramData' {
        $script:BackupFile  | Should -Not -BeLike "$env:ProgramData*"
        $script:HistoryFile | Should -Not -BeLike "$env:ProgramData*"
    }
}

Describe 'Import-Tweaks' {
    BeforeAll {
        $script:TwDir = Join-Path $script:Temp 'tweaks\Test'
        New-Item -ItemType Directory -Path $script:TwDir -Force | Out-Null
        $valid = [ordered]@{
            id = 'test-valid'; kind = 'tweak'; category = 'Test'; order = 5
            name = @{ es = 'Nombre'; en = 'Name' }; summary = @{ es = 'Resumen'; en = 'Summary' }
            risk = 'moderate'; presets = @('recommended', 'competitive'); requiresAdmin = $false; reboot = $true; reversible = $true
            undo = @{ type = 'snapshot' }
            actions = @(
                @{ registry = 'HKCU:\Software\OptiEleven-Test\x'; name = 'A'; type = 'DWord'; value = 1; default = 0 },
                @{ registry = 'HKCU:\Software\OptiEleven-Test\x'; name = 'B'; type = 'String'; value = 'v'; default = $null }
            )
        }
        [IO.File]::WriteAllText((Join-Path $script:TwDir 'test-valid.tweak.json'), ($valid | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $script:TwDir 'test-broken.tweak.json'), '{ "id": "test-broken", "kind": ', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $script:TwDir 'test-norisk.tweak.json'), '{ "id": "test-norisk", "kind": "tweak" }', [Text.UTF8Encoding]::new($false))
    }

    It 'loads the valid tweak in the engine shape and skips the broken ones without throwing' {
        $script:Logged.Clear()
        $list = @(Import-Tweaks (Split-Path $script:TwDir))
        $list.Count | Should -Be 1
        $t = $list[0]
        $t.Id      | Should -Be 'test-valid'
        $t.Cat     | Should -Be 'Test'
        $t.Risk    | Should -Be 'Moderado'
        $t.Name    | Should -Be 'Nombre'
        $t.Desc    | Should -Be 'Resumen'
        $t.Reboot  | Should -BeTrue
        $t.Irreversible | Should -BeNullOrEmpty
        @($t.Presets) | Should -Be @('R', 'C')
        $t.Reg.Count | Should -Be 2
        $t.Reg[0] | Should -BeOfType [hashtable]
        $t.Reg[0].Path    | Should -Be 'HKCU:\Software\OptiEleven-Test\x'
        $t.Reg[0].Name    | Should -Be 'A'
        $t.Reg[0].Value   | Should -Be 1
        $t.Reg[0].Kind    | Should -Be 'DWord'
        $t.Reg[0].Default | Should -Be 0
        $t.Reg[1].Default | Should -BeNullOrEmpty
        @($script:Logged | Where-Object { $_ -like 'WARN*' }).Count | Should -Be 2
    }

    It 'maps every risk and preset value' {
        $TweakRisk['safe'] | Should -Be 'Seguro'
        $TweakRisk['moderate'] | Should -Be 'Moderado'
        $TweakRisk['advanced'] | Should -Be 'Avanzado'
        $TweakPresets['recommended'] | Should -Be 'R'
        $TweakPresets['advanced'] | Should -Be 'A'
        $TweakPresets['competitive'] | Should -Be 'C'
    }

    It 'loads all 60 real tweak files with no warnings' {
        $script:Logged.Clear()
        $list = @(Import-Tweaks $TweaksDir)
        $script:Logged | Should -BeNullOrEmpty
        $list.Count | Should -Be 60
    }
}
