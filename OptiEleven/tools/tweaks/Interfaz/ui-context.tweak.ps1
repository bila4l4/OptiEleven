# ui-context: lo que no cabe en el .json. Devuelve Backup / Test / Apply / Revert / Diff; las funciones que usa están en OptiEleven.ps1.
@{
           Test   = { param($bk) Test-Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' }
           Apply  = { param($bk) $k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
                      New-Item -Path $k -Force | Out-Null; Set-Item -LiteralPath $k -Value '' }
           Revert = { param($bk) Remove-Item 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction SilentlyContinue }
       }
