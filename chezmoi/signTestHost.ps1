$files = @()
$files += Get-ChildItem C:\Users\tplunk\wdac\pwshConsole\Debug\* -Recurse | Where-Object { $_.Extension -in '.dll', '.exe' -or $_.Extension -like '.ps*'}
$files += Get-ChildItem 'C:\Users\tplunk\Documents\PowerShell\profile.ps1'
$files  | Set-AuthenticodeSignatureForCiPolicy
