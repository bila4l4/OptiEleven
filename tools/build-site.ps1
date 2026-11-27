# Builds docs/index.html (the GitHub Pages page) from run.ps1.
# The page is both HTML and PowerShell, so "irm <domain> | iex" runs run.ps1
# and a browser sees a normal page. Run it every time you change run.ps1.
param([string]$Command = 'irm optieleven.app | iex')

$root = Split-Path $PSScriptRoot -Parent
$script = [IO.File]::ReadAllText((Join-Path $root 'run.ps1'))
$tpl = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'site-template.html'))
if ($script.Contains('#>')) { throw 'run.ps1 no puede contener "#>": cerraría el comentario de la página.' }
$html = $tpl.Replace('{{COMMAND}}', $Command).Replace('{{SCRIPT}}', $script.TrimEnd())
if ($tpl.Substring(2, $tpl.IndexOf('<div hidden>') - 2).Contains('#>')) { throw 'La parte HTML no puede contener "#>".' }
$out = Join-Path $root 'docs\index.html'
[IO.File]::WriteAllText($out, $html, (New-Object Text.UTF8Encoding $false))
$errs = $null; [void][Management.Automation.Language.Parser]::ParseInput($html, [ref]$null, [ref]$errs)
if ($errs) { throw "La página no es PowerShell válido: $($errs[0].Message)" }
"docs\index.html listo ($([math]::Round((Get-Item $out).Length / 1KB, 1)) KB), comando: $Command"
