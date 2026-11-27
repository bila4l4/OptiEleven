#Requires -Version 5.1
<#
  Signs the .exe, .dll and .ps1 files of a staged release with signtool (SHA256 + RFC 3161 timestamp), then checks
  that Windows sees every signature as Valid. Called by build\Build.ps1 before zipping.

  The mode comes from environment variables (GitHub secrets in .github/workflows/release.yml):
    pfx    SIGN_PFX_BASE64    the .pfx file as base64
           SIGN_PFX_PASSWORD  its password
    azure  Azure Artifact Signing (formerly Trusted Signing), signtool with Microsoft's dlib:
           AZURE_SIGNING_ENDPOINT  e.g. https://weu.codesigning.azure.net
           AZURE_SIGNING_ACCOUNT   the Artifact Signing account name
           AZURE_SIGNING_PROFILE   the certificate profile name
           AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET  an app registration with the
                                   "Trusted Signing Certificate Profile Signer" role
                                   (read by the dlib through DefaultAzureCredential)
           SIGN_DLIB               path to Azure.CodeSigning.Dlib.dll (the workflow installs it from NuGet)
  Optional: SIGN_TIMESTAMP_URL, SIGNTOOL (path to signtool.exe).
  With none of them set it prints "signing skipped (no certificate)" and succeeds, so forks and local builds work.

  Since June 2023 public CAs only issue code-signing keys on hardware (a token or an HSM), so a .pfx from a public CA
  is no longer something you can download; pfx mode is for older certificates or a private CA. The cloud mode is the
  realistic one for a public, trusted signature.
#>
param([Parameter(Mandatory = $true)][string]$Path)

$ErrorActionPreference = 'Stop'
if ($env:SIGN_PFX_BASE64) { $mode = 'pfx' }
elseif ($env:AZURE_SIGNING_ENDPOINT) { $mode = 'azure' }
else { Write-Host 'signing skipped (no certificate)'; return }

# native\OptiEleven-Apps.exe is not signed: the panel appends each user's app list to the end of it, which would
# break a signature anyway (it is the same unsigned file the panel used to compile on the user's PC).
$files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Include *.ps1, *.psm1, *.exe, *.dll |
    Where-Object { $_.Name -ne 'OptiEleven-Apps.exe' } | ForEach-Object { $_.FullName })
if (-not $files) { throw "Nothing to sign in $Path" }

$signtool = $env:SIGNTOOL
if (-not $signtool) {
    $signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object { $_.Directory.Parent.Name -as [version] } -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $signtool -or -not (Test-Path $signtool)) { throw 'signtool.exe not found (install the Windows SDK or set SIGNTOOL)' }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('optieleven-sign-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    if ($mode -eq 'pfx') {
        $ts = 'http://timestamp.digicert.com'
        $pfx = Join-Path $tmp 'cert.pfx'
        [IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($env:SIGN_PFX_BASE64))
        $key = @('/f', $pfx, '/p', $env:SIGN_PFX_PASSWORD)
    }
    else {
        $ts = 'http://timestamp.acs.microsoft.com'
        if (-not $env:SIGN_DLIB -or -not (Test-Path $env:SIGN_DLIB)) { throw 'SIGN_DLIB must point to Azure.CodeSigning.Dlib.dll' }
        $meta = Join-Path $tmp 'metadata.json'
        $json = @{ Endpoint = $env:AZURE_SIGNING_ENDPOINT; CodeSigningAccountName = $env:AZURE_SIGNING_ACCOUNT; CertificateProfileName = $env:AZURE_SIGNING_PROFILE } | ConvertTo-Json
        [IO.File]::WriteAllText($meta, $json)
        $key = @('/dlib', $env:SIGN_DLIB, '/dmdf', $meta)
    }
    if ($env:SIGN_TIMESTAMP_URL) { $ts = $env:SIGN_TIMESTAMP_URL }
    Write-Host "Signing $($files.Count) files ($mode)"
    # in groups, to stay under the command-line length limit
    for ($i = 0; $i -lt $files.Count; $i += 40) {
        $group = $files[$i..([math]::Min($i + 39, $files.Count - 1))]
        & $signtool sign /fd SHA256 /tr $ts /td SHA256 @key @group
        if ($LASTEXITCODE -ne 0) { throw "signtool failed (exit code $LASTEXITCODE)" }
    }
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

$bad = @($files | Where-Object { (Get-AuthenticodeSignature -LiteralPath $_).Status -ne 'Valid' })
if ($bad) { throw "These files do not have a valid signature:`n$($bad -join "`n")" }
Write-Host "Signed and verified $($files.Count) files"
