# Every tweak and tool manifest is valid. Each test collects all problems and lists them in one failure.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:Risks    = 'safe', 'moderate', 'advanced'
    $script:Presets  = 'recommended', 'advanced', 'competitive'
    $script:Undo     = 'snapshot', 'none', 'script'
    # tools describe how their own actions are undone; add a type here when a tool needs a new one
    $script:ToolUndo = 'none', 'auto', 'toggle', 'manual', 'recycle-bin', 'snapshot', 'script'
    $script:RegKinds = 'DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary'
    $script:Starts   = 'Auto', 'Delayed', 'Manual', 'Disabled'

    function Test-Lang($v) { $v -and $v.es -is [string] -and $v.es.Trim() -and $v.en -is [string] -and $v.en.Trim() }
    function Test-ParseFile([string]$Path) {
        $tk = $null; $er = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tk, [ref]$er)
        [pscustomobject]@{ Ast = $ast; Errors = @($er) }
    }

    $script:TweakFiles = @(Get-ChildItem -LiteralPath $TweaksDir -Filter '*.tweak.json' -Recurse)
    $script:Tweaks = foreach ($f in $script:TweakFiles) {
        try { [pscustomobject]@{ File = $f; Json = (Read-JsonFile $f.FullName); Error = $null } }
        catch { [pscustomobject]@{ File = $f; Json = $null; Error = $_.Exception.Message } }
    }
    $script:ToolFiles = @(Get-ChildItem -LiteralPath $ToolsDir -Filter 'tool.json' -Recurse)
    $script:Tools = foreach ($f in $script:ToolFiles) {
        try { [pscustomobject]@{ File = $f; Json = (Read-JsonFile $f.FullName); Error = $null } }
        catch { [pscustomobject]@{ File = $f; Json = $null; Error = $_.Exception.Message } }
    }
}

Describe 'Tweak manifests' {

    It 'there are 60 tweak files' {
        $script:TweakFiles.Count | Should -Be 60
    }

    It 'every tweak .json parses' {
        @($script:Tweaks | Where-Object Error | ForEach-Object { "$($_.File.Name): $($_.Error)" }) | Should -BeNullOrEmpty
    }

    It 'every tweak has all required fields with allowed values' {
        $bad = foreach ($t in @($script:Tweaks | Where-Object Json)) {
            $j = $t.Json; $n = $t.File.Name
            foreach ($k in 'id', 'kind', 'category', 'order', 'name', 'summary', 'risk', 'presets', 'requiresAdmin', 'reboot', 'reversible', 'undo', 'actions') {
                if ($j.PSObject.Properties.Name -notcontains $k) { "${n}: missing '$k'" }
            }
            if ($j.id -isnot [string] -or $j.id -notmatch '^[a-z0-9-]+$') { "${n}: bad id '$($j.id)'" }
            if ("$($j.id).tweak.json" -ne $n) { "${n}: id '$($j.id)' does not match the file name" }
            if ($j.kind -ne 'tweak') { "${n}: kind must be 'tweak'" }
            if ($j.category -ne $t.File.Directory.Name) { "${n}: category '$($j.category)' is not its folder '$($t.File.Directory.Name)'" }
            if ($j.order -isnot [int]) { "${n}: order must be an integer" }
            if ($script:Risks -cnotcontains $j.risk) { "${n}: risk '$($j.risk)'" }
            foreach ($p in @($j.presets)) { if ($script:Presets -cnotcontains $p) { "${n}: preset '$p'" } }
            foreach ($k in 'requiresAdmin', 'reboot', 'reversible') { if ($j.$k -isnot [bool]) { "${n}: $k must be true/false" } }
            if (-not $j.undo -or $script:Undo -cnotcontains $j.undo.type) { "${n}: undo.type '$($j.undo.type)'" }
            if ($j.undo.note -and -not (Test-Lang $j.undo.note)) { "${n}: undo.note needs es and en" }
            if ($j.script -and $j.script -ne "$($j.id).tweak.ps1") { "${n}: script should be '$($j.id).tweak.ps1'" }
            if (-not $j.script -and @($j.actions).Count -eq 0) { "${n}: no actions and no script" }
            foreach ($a in @($j.actions)) {
                $keys = @($a.PSObject.Properties.Name | Sort-Object) -join ','
                if ($a.registry) {
                    if ($keys -ne 'default,name,registry,type,value') { "${n}: registry action has fields $keys" }
                    if ($a.registry -notmatch '^(HKLM|HKCU):\\') { "${n}: registry path '$($a.registry)'" }
                    if ($script:RegKinds -cnotcontains $a.type) { "${n}: registry type '$($a.type)'" }
                    if ($null -eq $a.value) { "${n}: registry $($a.name) has no value" }
                }
                elseif ($a.service) {
                    if ($keys -ne 'default,service,startup') { "${n}: service action has fields $keys" }
                    if ($script:Starts -cnotcontains $a.startup) { "${n}: service startup '$($a.startup)'" }
                    if ($script:Starts -cnotcontains $a.default) { "${n}: service default '$($a.default)'" }
                }
                elseif ($a.task) {
                    if ($keys -ne 'task') { "${n}: task action has fields $keys" }
                    if ($a.task -notmatch '^\\') { "${n}: task path '$($a.task)' must start with \" }
                }
                else { "${n}: unknown action $keys" }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'every tweak has es and en name and summary' {
        @($script:Tweaks | Where-Object Json | Where-Object { -not (Test-Lang $_.Json.name) -or -not (Test-Lang $_.Json.summary) } | ForEach-Object { $_.File.Name }) | Should -BeNullOrEmpty
    }

    It 'tweak ids are unique' {
        @($script:Tweaks | Where-Object Json | Group-Object { $_.Json.id } | Where-Object Count -gt 1 | ForEach-Object Name) | Should -BeNullOrEmpty
    }

    It 'every script file exists and parses' {
        $bad = foreach ($t in @($script:Tweaks | Where-Object { $_.Json.script })) {
            $p = Join-Path $t.File.DirectoryName $t.Json.script
            if (-not (Test-Path -LiteralPath $p)) { "$($t.File.Name): missing $($t.Json.script)"; continue }
            $r = Test-ParseFile $p
            foreach ($e in $r.Errors) { "$($t.Json.script):$($e.Extent.StartLineNumber): $($e.Message)" }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'no .tweak.ps1 is left without a .tweak.json that names it' {
        $named = @($script:Tweaks | Where-Object { $_.Json.script } | ForEach-Object { Join-Path $_.File.DirectoryName $_.Json.script })
        @(Get-ChildItem -LiteralPath $TweaksDir -Filter '*.tweak.ps1' -Recurse | Where-Object { $named -notcontains $_.FullName } | ForEach-Object Name) | Should -BeNullOrEmpty
    }
}

Describe 'Tool manifests' {
    BeforeAll {
        $script:Cats = @(Read-JsonFile (Join-Path $ToolsDir 'categories.json'))
        $script:Icons = Get-IconNames
        $tweakCats = @($script:Tweaks | Where-Object Json | ForEach-Object { [string]$_.Json.category } | Select-Object -Unique)
        $script:Reserved = @('all', 'tools', 'log') + $tweakCats
    }

    It 'categories.json is a list of unique ids with an order' {
        $script:Cats.Count | Should -BeGreaterThan 0
        @($script:Cats | Where-Object { -not $_.id -or $null -eq $_.order }) | Should -BeNullOrEmpty
        @($script:Cats | Group-Object id | Where-Object Count -gt 1) | Should -BeNullOrEmpty
    }

    It 'every tool.json parses' {
        @($script:Tools | Where-Object Error | ForEach-Object { "$($_.File.Directory.Name): $($_.Error)" }) | Should -BeNullOrEmpty
    }

    It 'every tool.json has all required fields with allowed values' {
        $bad = foreach ($t in @($script:Tools | Where-Object Json)) {
            $j = $t.Json; $n = $t.File.Directory.Name
            foreach ($k in 'id', 'kind', 'category', 'order', 'name', 'title', 'summary', 'icon', 'color', 'view', 'risk', 'requiresAdmin', 'reversible', 'undo') {
                if ($j.PSObject.Properties.Name -notcontains $k) { "${n}: missing '$k'" }
            }
            if ($j.id -ne $n) { "${n}: id '$($j.id)' is not its folder name" }
            if ($j.kind -ne 'tool') { "${n}: kind must be 'tool'" }
            if ($j.order -isnot [int]) { "${n}: order must be an integer" }
            if ($script:Risks -cnotcontains $j.risk) { "${n}: risk '$($j.risk)'" }
            if ($j.requiresAdmin -isnot [bool]) { "${n}: requiresAdmin must be true/false" }
            if ($j.reversible -isnot [bool] -and $j.reversible -cne 'partial') { "${n}: reversible must be true/false/'partial'" }
            if (-not $j.undo -or $script:ToolUndo -cnotcontains $j.undo.type) { "${n}: undo.type '$($j.undo.type)'" }
            foreach ($k in 'name', 'title', 'summary') { if ($j.$k -and -not (Test-Lang $j.$k)) { "${n}: $k needs es and en" } }
            if (@($script:Cats | ForEach-Object id) -notcontains $j.category) { "${n}: category '$($j.category)' is not in categories.json" }
            if ($script:Icons -notcontains $j.icon) { "${n}: icon '$($j.icon)' is not in icons.json" }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'view and onShow are functions defined in the tool''s tool.ps1' {
        $bad = foreach ($t in @($script:Tools | Where-Object Json)) {
            $n = $t.File.Directory.Name
            $ps1 = Join-Path $t.File.DirectoryName 'tool.ps1'
            if (-not (Test-Path -LiteralPath $ps1)) { "${n}: no tool.ps1"; continue }
            $r = Test-ParseFile $ps1
            $defined = @($r.Ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name)
            foreach ($k in 'view', 'onShow') {
                $fn = $t.Json.$k
                if ($fn -and $defined -notcontains $fn) { "${n}: $k '$fn' is not defined in tool.ps1" }
            }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'tool ids are unique and not reserved' {
        $ids = @($script:Tools | Where-Object Json | ForEach-Object { [string]$_.Json.id })
        @($ids | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name) | Should -BeNullOrEmpty   # Group-Object ignores case
        @($ids | Where-Object { $script:Reserved -contains $_ -or $_ -like 'h-*' }) | Should -BeNullOrEmpty
    }
}
