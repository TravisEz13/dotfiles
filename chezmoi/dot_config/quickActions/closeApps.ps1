get-process fork,fing,preview,photos,'activity monito' -ErrorAction SilentlyContinue | Stop-Process
Get-Process electron | ? {$_.path -match '/Visual Studio Code\.'} | Stop-Process
Write-Host "Apps closed"
