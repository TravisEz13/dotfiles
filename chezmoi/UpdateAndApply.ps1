chezmoi apply --force
dir C:\Users\tplunk\Documents\Powershell\Modules\MyProfileHelper\* |%{Set-AuthenticodeSignatureForCiPolicy -Path $_.FullName}
import-module C:\Users\tplunk\Documents\Powershell\Modules\MyProfileHelper -force
Set-AuthenticodeSignatureForCiPolicy -path 'C:\Users\tplunk\AppData\Local\Microsoft\WinGet\Links\chezmoi.exe'
Set-AuthenticodeSignatureForCiPolicy -Path 'C:\Program Files\starship\bin\starship.exe'
