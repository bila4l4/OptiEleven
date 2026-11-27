#Requires -Version 5.1
# Runs every tests\*.Tests.ps1 with Pester 5 or later (installed for the current user if missing; Windows ships 3.4).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1
# Exit code: 0 when everything passes, 1 otherwise. Used by CI and build\Build.ps1.
param([string]$Output = 'Detailed')

$ErrorActionPreference = 'Stop'
$min = [version]'5.0.0'
if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge $min)) {
    Write-Host 'Installing Pester 5 for the current user...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object Version -ge ([version]'2.8.5.201'))) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    }
    Install-Module Pester -MinimumVersion $min -Scope CurrentUser -Force -SkipPublisherCheck
}
Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion $min

$cfg = New-PesterConfiguration
$cfg.Run.Path = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' | ForEach-Object FullName)
$cfg.Run.PassThru = $true
$cfg.Output.Verbosity = $Output
$r = Invoke-Pester -Configuration $cfg

Write-Host ''
Write-Host ("Passed: {0}  Failed: {1}  Skipped: {2}  NotRun: {3}" -f $r.PassedCount, $r.FailedCount, $r.SkippedCount, $r.NotRunCount)
foreach ($t in $r.Failed) { Write-Host "  FAILED: $($t.ExpandedPath)" -ForegroundColor Red }
foreach ($c in $r.FailedContainers) { Write-Host "  FAILED TO RUN: $($c.Item)" -ForegroundColor Red }
if ($r.Result -ne 'Passed') { exit 1 }
exit 0
