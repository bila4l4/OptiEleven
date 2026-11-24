# OptiEleven one-line launcher
#   irm bila4l4.github.io/OptiEleven | iex
#
# First run: downloads the latest release from GitHub into %LOCALAPPDATA%\OptiEleven and opens it.
# Later runs: a quick check on GitHub; if there's a newer release it's installed first, then the panel
# opens. If GitHub doesn't answer, the version you have opens. Nothing else is installed.
# Kept ASCII-only on purpose: it is read as text by Invoke-RestMethod.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads in PowerShell 5.1 very slow
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo    = 'bila4l4/OptiEleven'
    $home_   = Join-Path $env:LOCALAPPDATA 'OptiEleven'
    $app     = Join-Path $home_ 'app'
    $next    = Join-Path $home_ 'next'
    $verFile = Join-Path $home_ 'version.txt'
    $entry   = Join-Path $app 'OptiEleven.ps1'

    function Write-Step([string]$Text) { Write-Host "  OptiEleven  " -ForegroundColor Black -BackgroundColor DarkYellow -NoNewline; Write-Host " $Text" }

    function Get-Latest([int]$Timeout = 15) {
        try {
            $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'OptiEleven-launcher' } -TimeoutSec $Timeout
            $url = ($rel.assets | Where-Object name -eq 'OptiEleven.zip' | Select-Object -First 1).browser_download_url
            if ($url) { return [pscustomobject]@{ Tag = $rel.tag_name; Url = $url } }
        }
        catch { Write-Step "Couldn't reach GitHub: $($_.Exception.Message)" }
        $null
    }

    # downloads a release into $Dest (replacing it) and returns $true if it worked
    function Save-Release($Latest, [string]$Dest) {
        $tmp = Join-Path $env:TEMP ("optieleven-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $zip = Join-Path $tmp 'OptiEleven.zip'
            Invoke-WebRequest $Latest.Url -OutFile $zip -UseBasicParsing -TimeoutSec 120
            Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
            $src = Join-Path $tmp 'OptiEleven'
            if (-not (Test-Path (Join-Path $src 'OptiEleven.ps1'))) { throw 'the download does not look like an OptiEleven release' }
            Get-ChildItem -LiteralPath $src -Recurse -File | Unblock-File
            Set-Content -LiteralPath (Join-Path $src 'version.txt') -Value $Latest.Tag
            New-Item -ItemType Directory -Path $home_ -Force | Out-Null
            if (Test-Path $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
            Move-Item -LiteralPath $src -Destination $Dest
            return $true
        }
        catch { Write-Step "Download failed: $($_.Exception.Message)"; return $false }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    function Open-Panel {
        $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$entry`"")
        try {
            Write-Step 'Opening the panel (accept the administrator prompt)...'
            Start-Process powershell.exe -ArgumentList $a -Verb RunAs
        }
        catch {
            # administrator prompt declined: the panel still opens, in read-only mode
            Write-Step 'No administrator rights: opening in read-only mode.'
            Start-Process powershell.exe -ArgumentList $a
        }
    }

    Write-Host ''
    # an update downloaded last time goes in now, before opening
    if (Test-Path (Join-Path $next 'OptiEleven.ps1')) {
        try {
            if (Test-Path $app) { Remove-Item -LiteralPath $app -Recurse -Force }
            Move-Item -LiteralPath $next -Destination $app
            Copy-Item (Join-Path $app 'version.txt') $verFile -Force -ErrorAction SilentlyContinue
            Write-Step "Updated to $((Get-Content $verFile -Raw).Trim())."
        }
        catch { Write-Step "Couldn't apply the update now (is the panel open?). It will be tried again next time." }
    }

    $current = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { $null }
    if (Test-Path $entry) {
        # a quick check first (under a second normally): a new version is installed before opening, so you always
        # get the latest; if GitHub is slow or unreachable, the version you have opens right away
        Write-Step 'Checking for updates...'
        $latest = Get-Latest 4
        if ($latest -and $latest.Tag -ne $current) {
            Write-Step "Updating to OptiEleven $($latest.Tag)..."
            if (Save-Release $latest $next) {
                try {
                    Remove-Item -LiteralPath $app -Recurse -Force
                    Move-Item -LiteralPath $next -Destination $app
                    Copy-Item (Join-Path $app 'version.txt') $verFile -Force
                    Write-Step "Updated to $($latest.Tag)."
                }
                catch { Write-Step "Couldn't replace the old version now (is the panel open?). It will update next time." }
            }
        }
        elseif ($latest) { Write-Step "OptiEleven $current is up to date." }
        Open-Panel
    }
    else {
        Write-Step 'Downloading OptiEleven...'
        $latest = Get-Latest
        if (-not $latest) { Write-Host ''; return }
        if (-not (Save-Release $latest $app)) { Write-Host ''; return }
        Copy-Item (Join-Path $app 'version.txt') $verFile -Force
        Write-Step "Installed OptiEleven $($latest.Tag) in $app"
        Open-Panel
    }
    Write-Host ''
}
