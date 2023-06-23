chezmoi apply --force
get-content -raw C:\Users\tplunk\Documents\Powershell\Modules\MyProfileHelper\CiPolicyHelper.psm1 | Invoke-Expression
dir C:\Users\tplunk\Documents\Powershell\Modules\MyProfileHelper\*.ps* |%{Set-AuthenticodeSignatureForCiPolicy -Path $_.FullName}
import-module C:\Users\tplunk\Documents\Powershell\Modules\MyProfileHelper -force
Set-AuthenticodeSignatureForCiPolicy -path 'C:\Users\tplunk\AppData\Local\Microsoft\WinGet\Links\chezmoi.exe'
Set-AuthenticodeSignatureForCiPolicy -Path 'C:\Program Files\starship\bin\starship.exe'
Set-AuthenticodeSignatureForCiPolicy -Path './signTestHost.ps1'
