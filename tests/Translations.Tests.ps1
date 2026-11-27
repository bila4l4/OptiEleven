# Every constant Spanish text the UI passes to T (directly, or through a helper that calls T) has an English
# translation in lang\en.json, either as an exact string or through a pattern. Editing a Spanish text without
# updating en.json makes this fail and lists the texts.

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    # commands whose first argument goes through T inside the core
    $script:TCommands = 'T', 'New-Text', 'New-Btn', 'Write-Log', 'New-Section', 'New-Chip'

    $lang = Read-CaseSensitiveJson $LangPath
    $script:Strings = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach ($k in $lang['strings'].Keys) { $script:Strings[$k] = [string]$lang['strings'][$k] }
    $script:Patterns = @(foreach ($p in @($lang['patterns'])) { if ($p -and $p.Count -ge 2) { [regex]::new([string]$p[0]) } })
    $script:Icons = Get-IconNames

    # same lookup as T in OptiEleven.ps1: each line on its own, exact string first, then the patterns
    function Test-Translated([string]$Text) {
        foreach ($line in ($Text -split "`n")) {
            $line = $line.TrimEnd("`r")
            if (-not $line -or $script:Strings.ContainsKey($line)) { continue }
            if (-not @($script:Patterns | Where-Object { $_.IsMatch($line) }).Count) { return $false }
        }
        $true
    }

    $files = @(Get-Item -LiteralPath $CorePath) + @(Get-ChildItem -LiteralPath $ToolsDir -Filter '*.ps1' -Recurse)
    $script:Texts = foreach ($f in $files) {
        $tk = $null; $er = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tk, [ref]$er)
        $calls = $ast.FindAll({ param($a) $a -is [Management.Automation.Language.CommandAst] -and $script:TCommands -contains $a.GetCommandName() }, $true)
        foreach ($c in $calls) {
            if ($c.CommandElements.Count -lt 2) { continue }
            $arg = $c.CommandElements[1]
            if ($arg -isnot [Management.Automation.Language.StringConstantExpressionAst]) { continue }   # variables, "$x ..." and parameters are not checked
            if ($arg.StringConstantType -eq 'BareWord') { continue }
            $s = $arg.Value
            # no words to translate: only {0:N1} placeholders, units and symbols, or an icon name
            $words = ($s -replace '\{\d+(:[^}]*)?\}', '') -creplace '\b(KB|MB|GB|TB|ms|Hz|MHz|GHz|FPS)\b', ''
            if ($words -notmatch '\p{L}' -or $script:Icons -contains $s) { continue }
            [pscustomobject]@{ Text = $s; Where = "$($f.FullName.Substring($RepoRoot.Length + 1)):$($arg.Extent.StartLineNumber)" }
        }
    }
}

Describe 'English translation' {

    It 'finds the texts to check' {
        @($script:Texts).Count | Should -BeGreaterThan 100
        Test-Translated 'Historial' | Should -BeTrue
        Test-Translated 'historial' | Should -BeFalse   # keys are case-sensitive, like T
        Test-Translated 'Texto que nadie ha traducido' | Should -BeFalse
    }

    It 'every constant text passed to T, New-Text, New-Btn, New-Section, New-Chip or Write-Log is in en.json' {
        $missing = @($script:Texts | Where-Object { -not (Test-Translated $_.Text) } | Group-Object Text | ForEach-Object {
            "$($_.Name)   [$((@($_.Group | ForEach-Object Where) | Select-Object -First 3) -join ', ')]" })
        if ($missing.Count) { Write-Host "`n$($missing.Count) texts without English:`n  $($missing -join "`n  ")" -ForegroundColor Yellow }
        $missing | Should -BeNullOrEmpty
    }
}
