
#Enable concise errorview for PS7 and up
if ($psversiontable.psversion.major -ge 7) {
    $ErrorView = 'ConciseView'
}

#Enable AzPredictor if present
if ((Get-Module psreadline).Version -gt 2.1.99 -and (Get-Command 'Enable-AzPredictor' -ErrorAction SilentlyContinue)) {
    Enable-AzPredictor
}

#Enable new fancy progress bar
if ($psversiontable.psversion.major -ge '7.2.0') {
    Enable-ExperimentalFeature PSAnsiProgress,PSAnsiRendering -WarningAction SilentlyContinue
    #Windows Terminal
    if ($ENV:WT_SESSION) {
        $PSStyle.Progress.UseOSCIndicator = $true
    }
}


#Starship Prompt
if (Get-Command starship -CommandType Application -ErrorAction SilentlyContinue) {
    #Separate Prompt for vscode. We don't use the profile so this works for both integrated and external terminal modes
    if ($ENV:VSCODE_GIT_IPC_HANDLE) {
        $ENV:STARSHIP_CONFIG = "$HOME\.config\starship-vscode.toml"
    }
    #Get Starship Prompt Initializer
    [string]$starshipPrompt = (& starship init powershell --print-full-init) -join "`n"

    #Kludge: Take a common line and add a suffix to it
    $stubToReplace = 'prompt {'
    $replaceShim = {
        $env:STARSHIP_ENVVAR = if (Test-Path Variable:/PSDebugContext) {
            "`u{1f41e}"
        } else {
            $null
        }
    }

    $starshipPrompt = $starshipPrompt -replace 'prompt \{',"prompt { $($replaceShim.ToString())"
    if ($starshipPrompt -notmatch 'STARSHIP_ENVVAR') { Write-Error 'Starship shimming failed, check $profile' }

    . ([ScriptBlock]::create($starshipPrompt))
    if ((Get-Module PSReadline).Version -ge '2.1.0') {
        Set-PSReadLineOption -PromptText "`e[32m❯ ", '❯ '
    }
}

#region Helper functions

# allows idweb to be open from mac
function idweb {
    kdestroy --all; kinit --keychain tyleonha@REDMOND.CORP.MICROSOFT.COM; open https://idweb -a Safari.app
}

#endregion

#region Argument completers

# dotnet CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
    dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# dotnet suggest-based CLIs
if (Get-Command dotnet-suggest -ErrorAction SilentlyContinue) {
    $availableToComplete = (dotnet-suggest list) | Out-String
    $availableToCompleteArray = $availableToComplete.Split([Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries)

    Register-ArgumentCompleter -Native -CommandName $availableToCompleteArray -ScriptBlock {
        param($commandName, $wordToComplete, $cursorPosition)
        $fullpath = (Get-Command $wordToComplete.CommandElements[0]).Source

        $arguments = $wordToComplete.Extent.ToString().Replace('"', '\"')
        dotnet-suggest get -e $fullpath --position $cursorPosition -- "$arguments" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    $env:DOTNET_SUGGEST_SCRIPT_VERSION = "1.0.0"
}

# UnixCompleters
Import-Module Microsoft.PowerShell.UnixCompleters -ErrorAction SilentlyContinue

#endregion

#region Hooks

# Set CurrentDirectory when LocationChangedAction is invoked.
# This allows iTerm2's "Reuse previous session's directory" to work
$ExecutionContext.SessionState.InvokeCommand.LocationChangedAction += {
    [Environment]::CurrentDirectory = $pwd.ProviderPath
}

#endregion

#region Global variables

# For PSZoom
$global:ZoomApiKey = Get-Secret -Name ZoomApiKey -AsPlainText -ErrorAction SilentlyContinue
$global:ZoomApiSecret = Get-Secret -Name ZoomApiSecret -AsPlainText -ErrorAction SilentlyContinue

#endregion

#region Start up

if (Test-Path "/Applications/Remove Sophos Endpoint.app") {
    # Since it's a .app, the best we can do is pop the GUI
    open "/Applications/Remove Sophos Endpoint.app"
}

#endregion
