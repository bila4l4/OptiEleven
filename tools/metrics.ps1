# Saves the repo's numbers before GitHub forgets them: GitHub keeps visits and clones for 14 days only.
# Run it once a week (or daily during a launch) with the GitHub CLI logged in as an owner of the repo:
#   powershell -ExecutionPolicy Bypass -File tools\metrics.ps1
# It keeps two CSV files outside the repo (traffic is private data, so it isn't committed):
#   daily.csv     one row per day: views, unique visitors, clones, unique cloners (merged, so running it often is fine)
#   snapshot.csv  one row per run: stars, forks, watchers, open issues and release downloads
# and prints where the visitors came from in the last 14 days.
param(
    [string]$Repo = 'bila4l4/OptiEleven',
    [string]$Out = (Join-Path $env:USERPROFILE 'OptiEleven-metrics')
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Needs the GitHub CLI (gh), logged in with gh auth login.' }
function Get-Gh([string]$Path) { $j = gh api $Path; if ($LASTEXITCODE -ne 0) { throw "gh api $Path failed" }; $j | ConvertFrom-Json }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

# ---- one row per day, merged with what earlier runs saved
$views = Get-Gh "repos/$Repo/traffic/views"
$clones = Get-Gh "repos/$Repo/traffic/clones"
$dailyFile = Join-Path $Out 'daily.csv'
$days = @{}
if (Test-Path $dailyFile) { foreach ($r in Import-Csv $dailyFile) { $days[$r.date] = $r } }
foreach ($v in @($views.views)) {
    $d = ([datetime]$v.timestamp).ToString('yyyy-MM-dd')
    if (-not $days[$d]) { $days[$d] = [pscustomobject]@{ date = $d; views = 0; visitors = 0; clones = 0; cloners = 0 } }
    $days[$d].views = $v.count; $days[$d].visitors = $v.uniques
}
foreach ($c in @($clones.clones)) {
    $d = ([datetime]$c.timestamp).ToString('yyyy-MM-dd')
    if (-not $days[$d]) { $days[$d] = [pscustomobject]@{ date = $d; views = 0; visitors = 0; clones = 0; cloners = 0 } }
    $days[$d].clones = $c.count; $days[$d].cloners = $c.uniques
}
$days.Values | Sort-Object date | Export-Csv $dailyFile -NoTypeInformation -Encoding UTF8

# ---- a snapshot of the totals
$r = Get-Gh "repos/$Repo"
$releases = @(Get-Gh "repos/$Repo/releases?per_page=100")
$downloads = 0; foreach ($rel in $releases) { foreach ($a in @($rel.assets)) { $downloads += [int]$a.download_count } }
$snap = [pscustomobject]@{ date = (Get-Date).ToString('yyyy-MM-dd HH:mm'); stars = $r.stargazers_count; forks = $r.forks_count
    watchers = $r.subscribers_count; open_issues = $r.open_issues_count; downloads = $downloads }
$snapFile = Join-Path $Out 'snapshot.csv'
$snap | Export-Csv $snapFile -NoTypeInformation -Encoding UTF8 -Append

# ---- summary
"Last 14 days: $($views.count) views from $($views.uniques) visitors, $($clones.count) clones from $($clones.uniques) cloners."
"Now: $($snap.stars) stars, $($snap.forks) forks, $($snap.watchers) watchers, $($snap.open_issues) open issues and PRs, $downloads release downloads."
$refs = @(Get-Gh "repos/$Repo/traffic/popular/referrers")
if ($refs.Count) { 'Where visitors came from (14 days):'; $refs | ForEach-Object { '  {0,-28} {1,5} views {2,4} visitors' -f $_.referrer, $_.count, $_.uniques } }
"Saved in $Out"
