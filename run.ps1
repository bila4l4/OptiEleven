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

    # The latest version comes from the redirect of github.com/<repo>/releases/latest (-> .../tag/vX.Y.Z).
    # That page has no rate limit, unlike api.github.com (60 requests an hour per IP without an account).
    function Get-Latest([int]$Timeout = 15) {
        try {
            $rq = [Net.HttpWebRequest]::Create("https://github.com/$repo/releases/latest")
            $rq.AllowAutoRedirect = $false; $rq.Method = 'HEAD'; $rq.Timeout = $Timeout * 1000; $rq.UserAgent = 'OptiEleven-launcher'
            $rs = $rq.GetResponse(); $loc = $rs.Headers['Location']; $rs.Close()
            if ($loc -match '/releases/tag/([^/?#]+)$') {
                $tag = [Uri]::UnescapeDataString($Matches[1])
                return [pscustomobject]@{ Tag = $tag; Url = "https://github.com/$repo/releases/download/$tag/OptiEleven.zip" }
            }
            Write-Step "Couldn't read the latest version from GitHub."
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
    # Swaps the downloaded version ($next) in. The old folder is renamed first: Windows refuses that while the panel
    # has files open, so an open panel leaves everything as it was (deleting file by file would leave it half gone).
    function Use-Next {
        $old = Join-Path $home_ 'app.old'
        if (Test-Path $old) { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $old) { return $false }
        if (Test-Path $app) { try { Rename-Item -LiteralPath $app -NewName 'app.old' -ErrorAction Stop } catch { return $false } }
        Move-Item -LiteralPath $next -Destination $app
        Copy-Item (Join-Path $app 'version.txt') $verFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue
        $true
    }

    # an update downloaded last time goes in now, before opening
    if (Test-Path (Join-Path $next 'OptiEleven.ps1')) {
        if (Use-Next) { Write-Step "Updated to $((Get-Content $verFile -Raw).Trim())." }
        else { Write-Step 'The panel is open: close it and run the command again to update.' }
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
                if (Use-Next) { Write-Step "Updated to $($latest.Tag)." }
                else { Write-Step 'The panel is open: close it and run the command again to update.' }
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
