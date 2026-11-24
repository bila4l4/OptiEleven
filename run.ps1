# OptiEleven one-line launcher
#   irm https://raw.githubusercontent.com/bilal1122c/OptiEleven/main/run.ps1 | iex
#
# Downloads the latest release from GitHub into %LOCALAPPDATA%\OptiEleven, updates it if
# a newer one exists, and opens the panel as administrator. Nothing else is installed.
# Kept ASCII-only on purpose: it is read as text by Invoke-RestMethod.

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads in PowerShell 5.1 very slow
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $repo    = 'bilal1122c/OptiEleven'
    $home_   = Join-Path $env:LOCALAPPDATA 'OptiEleven'
    $app     = Join-Path $home_ 'app'
    $verFile = Join-Path $home_ 'version.txt'
    $entry   = Join-Path $app 'OptiEleven.ps1'

    function Write-Step([string]$Text) { Write-Host "  OptiEleven  " -ForegroundColor Black -BackgroundColor DarkYellow -NoNewline; Write-Host " $Text" }

    Write-Host ''
    Write-Step 'Checking the latest version...'
    $tag = $null; $zipUrl = $null
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'OptiEleven-launcher' } -TimeoutSec 20
        $tag = $rel.tag_name
        $zipUrl = ($rel.assets | Where-Object name -eq 'OptiEleven.zip' | Select-Object -First 1).browser_download_url
    }
    catch { Write-Step "Couldn't reach GitHub: $($_.Exception.Message)" }

    $current = if (Test-Path $verFile) { (Get-Content $verFile -Raw).Trim() } else { $null }
    if ($zipUrl -and ($tag -ne $current -or -not (Test-Path $entry))) {
        Write-Step "Downloading OptiEleven $tag..."
        $tmp = Join-Path $env:TEMP ("optieleven-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $zip = Join-Path $tmp 'OptiEleven.zip'
            Invoke-WebRequest $zipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120
            Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
            $src = Join-Path $tmp 'OptiEleven'
            if (-not (Test-Path (Join-Path $src 'OptiEleven.ps1'))) { throw 'the download does not look like an OptiEleven release' }
            Get-ChildItem -LiteralPath $src -Recurse -File | Unblock-File
            New-Item -ItemType Directory -Path $home_ -Force | Out-Null
            if (Test-Path $app) { Remove-Item -LiteralPath $app -Recurse -Force }
            Move-Item -LiteralPath $src -Destination $app
            Set-Content -LiteralPath $verFile -Value $tag
            Write-Step "Installed in $app"
        }
        catch {
            Write-Step "Update failed: $($_.Exception.Message)"
            if (-not (Test-Path $entry)) { Write-Host ''; return }
            Write-Step 'Opening the version you already have.'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    elseif (Test-Path $entry) { Write-Step "OptiEleven $current is up to date." }
    else { Write-Host ''; return }

    $args_ = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$entry`"")
    try {
        Write-Step 'Opening the panel (accept the administrator prompt)...'
        Start-Process powershell.exe -ArgumentList $args_ -Verb RunAs
    }
    catch {
        # administrator prompt declined: the panel still opens, in read-only mode
        Write-Step 'No administrator rights: opening in read-only mode.'
        Start-Process powershell.exe -ArgumentList $args_
    }
    Write-Host ''
}
