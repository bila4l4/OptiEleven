# Shared by the *.Tests.ps1 files: paths, JSON readers and the engine loader. Dot-source it from BeforeAll / BeforeDiscovery.
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$AppDir     = Join-Path $RepoRoot 'OptiEleven'
$ToolsDir   = Join-Path $AppDir 'tools'
$TweaksDir  = Join-Path $ToolsDir 'tweaks'
$CorePath   = Join-Path $AppDir 'OptiEleven.ps1'
$LangPath   = Join-Path $AppDir 'lang\en.json'
$IconsPath  = Join-Path $AppDir 'assets\icons.json'

function Read-JsonFile([string]$Path) {
    # PS 5.1: a JSON array comes back as one object through the pipeline; going through a variable unrolls it
    $j = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $j
}

function Read-CaseSensitiveJson([string]$Path) {
    # en.json has keys that differ only by case, which ConvertFrom-Json rejects
    Add-Type -AssemblyName System.Web.Extensions
    $js = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $js.MaxJsonLength = 64MB
    $js.DeserializeObject([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8))
}

# Names that a tool.json "icon" may use. Change this one function if the app switches to Segoe Fluent glyphs.
function Get-IconNames {
    $d = Read-CaseSensitiveJson $IconsPath
    @($d.Keys)
}

# Source text of the core's top-level functions and the few lookup tables the engine reads, without running
# anything else of OptiEleven.ps1 (no ProgramData folders, no Add-Type, no window). Dot-source the result.
$EngineVars = 'TweakRisk', 'TweakPresets', 'StartNames', 'OverlayNames', 'CustomDiff'
function Get-EngineCode {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($CorePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "OptiEleven.ps1 does not parse: $($errors[0].Message)" }
    $parts = foreach ($s in $ast.EndBlock.Statements) {
        if ($s -is [Management.Automation.Language.FunctionDefinitionAst]) { $s.Extent.Text }
        elseif ($s -is [Management.Automation.Language.AssignmentStatementAst] -and
                $s.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                $EngineVars -contains $s.Left.VariablePath.UserPath) { $s.Extent.Text }
    }
    $parts -join "`n`n"
}
