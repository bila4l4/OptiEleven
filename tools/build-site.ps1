# Genera docs/index.html (la página de GitHub Pages) a partir de run.ps1.
# La página es a la vez HTML y PowerShell, así que "irm <dominio> | iex" ejecuta run.ps1
# y un navegador ve una página normal. Ejecútalo cada vez que cambies run.ps1.
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
