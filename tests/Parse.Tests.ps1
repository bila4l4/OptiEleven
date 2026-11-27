# Every script parses in PowerShell 5.1, and every .ps1 of the app is saved as UTF-8 with BOM
# (without the BOM, PS 5.1 reads the file as ANSI and breaks the accented text).

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:AppScripts = @(Get-ChildItem -LiteralPath $AppDir -Filter '*.ps1' -Recurse)
}

Describe 'Scripts' {

    It 'every .ps1 under OptiEleven\ and run.ps1 parses with zero errors' {
        $files = @($script:AppScripts | ForEach-Object FullName) + (Join-Path $RepoRoot 'run.ps1')
        $bad = foreach ($f in $files) {
            $tk = $null; $er = $null
            [void][Management.Automation.Language.Parser]::ParseFile($f, [ref]$tk, [ref]$er)
            foreach ($e in $er) { "$($f.Substring($RepoRoot.Length + 1)):$($e.Extent.StartLineNumber): $($e.Message)" }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'every .ps1 under OptiEleven\ starts with a UTF-8 BOM' {
        $bad = foreach ($f in $script:AppScripts) {
            $b = New-Object byte[] 3
            $s = [IO.File]::OpenRead($f.FullName)
            try { $n = $s.Read($b, 0, 3) } finally { $s.Dispose() }
            if ($n -lt 3 -or $b[0] -ne 0xEF -or $b[1] -ne 0xBB -or $b[2] -ne 0xBF) { $f.FullName.Substring($RepoRoot.Length + 1) }
        }
        @($bad) | Should -BeNullOrEmpty
    }
}
