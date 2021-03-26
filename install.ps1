$configPath = (Join-Path $PSScriptRoot '.config')

# Set up symlinks
Get-ChildItem -Path $configPath | ForEach-Object {
    New-Item -Path (Join-Path '~/.config' $_.Name) -ItemType SymbolicLink -Value $_.FullName
}

Install-Module PSDepend -Force
Invoke-PSDepend -Force (Join-Path $PSScriptRoot 'requirements.psd1')

wget https://github.com/twpayne/chezmoi/releases/download/v2.0.4/chezmoi_2.0.4_linux_amd64.deb
chmod a+r ./chezmoi_2.0.4_linux_amd64.deb
apt update
apt install ./chezmoi_2.0.4_linux_amd64.deb
chezmoi init --apply travisez13
