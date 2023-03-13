#Requires -Version 5.1
using namespace System.Collections.Generic;
using namespace System.Management.Automation;

$userProfile = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile)
$downloads = Join-Path $userProfile -ChildPath 'Downloads'

#Enable concise errorview for PS7 and up
if ($psversiontable.psversion.major -ge 7) {
    $ErrorView = 'ConciseView'
}

if (!$IsWindows) {
    #Other terminal bindings
    # Alt+Shift+ArrowLeft to \033b
    # Alt+Shift+ArrowLeft to \033B
    # Alt+Shift+ArrowRight to \033f
    # Alt+Shift+ArrowRight to \033F

    Set-PSReadlineKeyHandler -Chord Escape -Function RevertLine # No terminal binding needed
    Set-PSReadlineKeyHandler -Chord Alt+H -Function BeginningOfLine #Home in terminal bound to \033h
    Set-PSReadlineKeyHandler -Chord Alt+Shift+H -Function SelectBackwardsLine  #Shift+Home in terminal bound to \033H
    Set-PSReadlineKeyHandler -Chord Alt+E -Function EndOfLine #End in terminal bound to \033e
    Set-PSReadlineKeyHandler -Chord Alt+Shift+E -Function SelectLine  #Shift+End in terminal bound to \033E
    Set-PSReadlineKeyHandler -Chord Alt+8 -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Chord alt+enter -Function addline
    # Set-PSReadLineKeyHandler -Function SwitchPredictionView -Chord f2
    Set-PSReadLineOption -PredictionSource History

    $dotnetcli = Join-Path -Path $userProfile -ChildPath '.dotnet'
    if (Test-Path $dotnetcli ) {
        if ($env:PATH -notcontains $dotnetcli) {
            $env:PATH = $env:PATH + ':' + $dotnetcli
        }
    }

    $dotnetSource = $null
    $dotnetCommand = $null
    $dotnetCommand = gcm 'dotnet' -ErrorAction ignore
    if($dotnetCommand) {
        $dotnetSource = (split-path -ErrorAction ignore $dotnetCommand.Source)
        if ($dotnetSource) {
            $env:DOTNET_ROOT = $dotnetSource
        }
    }

    if ($IsMacOS) {
        if ($env:PATH -notmatch '\b/usr/local/bin\b') {
            # prevent repeated replacement of $env:PATH
            function setenv ($variable, $value) { [Environment]::SetEnvironmentVariable($variable, $value)  }
            # `/usr/libexec/path_helper -c` conveniently outputs something like 'setenv PATH "/usr/local/bin:..."',
            # which we can pass to Invoke-Expression, which then calls our transient `setenv()` function.
            /usr/libexec/path_helper -c | foreach-object {
                Write-Verbose "Updating env: $_ "
                Invoke-Expression $_
            }
            $env:PATH = "${pshome}:$env:PATH"
            if(!(Get-Command brew -ErrorAction SilentlyContinue)){
                /opt/homebrew/bin/brew shellenv  | foreach-object {
                    Write-Verbose "Updating env: $_ "
                    Invoke-Expression $_
                }
            }
        }

        $env:PATH="${env:PATH}:/Users/travisplunk/.dotnet/tools"
        $env:HOMEBREW_EDITOR='code -w'
        $env:EDITOR='code -w'
        $env:XDG_CONFIG_HOME = ((Resolve-Path '~/.config/').ProviderPath)
    }

    function script:precheck
    {
        param([string]$command, [string]$missedMessage)

        $c = Get-Command $command -ErrorAction Ignore
        if (-not $c) {
            if (-not [string]::IsNullOrEmpty($missedMessage))
            {
                Write-Warning $missedMessage
            }
            return $false
        } else {
            return $true
        }
    }

    Function Find-MyDotNet
    {
        $originalPath = $env:PATH
        $dotnetPath = if ($Environment.IsWindows) { "$env:LocalAppData\Microsoft\dotnet" } else { "$env:HOME/.dotnet" }

        # If there dotnet is already in the PATH, check to see if that version of dotnet can find the required SDK
        # This is "typically" the globally installed dotnet
        if (!(script:precheck dotnet)) {
            Write-Warning "Could not find 'dotnet', appending $dotnetPath to PATH."
            $env:PATH =   $dotnetPath + [IO.Path]::PathSeparator + $env:PATH
        }

        if (-not (precheck 'dotnet' "Still could not find 'dotnet', restoring PATH.")) {
            $env:PATH = $originalPath
        }
    }
    Find-MyDotNet
}

# #Enable AzPredictor if present
# if ((Get-Module psreadline).Version -gt 2.1.99 -and (Get-Command 'Enable-AzPredictor' -ErrorAction SilentlyContinue)) {
#     Enable-AzPredictor
# }

#Enable new fancy progress bar
if ([version]::new($psversiontable.psversion.major,$psversiontable.psversion.Minor,$psversiontable.psversion.Patch) -ge [version]'7.2.0') {
    $featureToEnable = @(
        'PSAnsiRenderingFileInfo'
    )

    Get-ExperimentalFeature | where-object {$_.name -in $featureToEnable} | Enable-ExperimentalFeature -WarningAction SilentlyContinue
    #Windows Terminal
    if ($ENV:WT_SESSION) {
        $PSStyle.Progress.UseOSCIndicator = $true
    }
}

# if (Get-Module -listavailable PoshCodex -ErrorAction SilentlyContinue) {
#     Import-Module PoshCodex
#     $env:OPENAI_API_KEY=(get-secret -AsPlainText -Name openai)
# } else {
#     #Write-Verbose "PoshCodex not installed" -Verbose
# }


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
else {
    Write-Warning "Please install starship"
}

#region Helper functions

#endregion

#region Argument completers

# dotnet CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
    dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# # dotnet suggest-based CLIs
# if (Get-Command dotnet-suggest -ErrorAction SilentlyContinue) {
#     $availableToComplete = (dotnet-suggest list) | Out-String
#     $availableToCompleteArray = $availableToComplete.Split([Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries)

#     Register-ArgumentCompleter -Native -CommandName $availableToCompleteArray -ScriptBlock {
#         param($commandName, $wordToComplete, $cursorPosition)
#         $fullpath = (Get-Command $wordToComplete.CommandElements[0]).Source

#         $arguments = $wordToComplete.Extent.ToString().Replace('"', '\"')
#         dotnet-suggest get -e $fullpath --position $cursorPosition -- "$arguments" | ForEach-Object {
#             [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
#         }
#     }
#     $env:DOTNET_SUGGEST_SCRIPT_VERSION = "1.0.0"
# }

# UnixCompleters
Import-Module Microsoft.PowerShell.UnixCompleters -ErrorAction SilentlyContinue

#endregion

#region Hooks

# Set CurrentDirectory when LocationChangedAction is invoked.
# This allows iTerm2's "Reuse previous session's directory" to work
# $ExecutionContext.SessionState.InvokeCommand.LocationChangedAction += {
#     [Environment]::CurrentDirectory = $pwd.ProviderPath
# }

#endregion

#region Global variables


#endregion

#region Start up


if (Test-Path "/Applications/Remove Sophos Endpoint.app") {
    # Since it's a .app, the best we can do is pop the GUI
    open "/Applications/Remove Sophos Endpoint.app"
}

#endregion


##################################old
#Requires -Version 5.1



$PSDefaultParameterValues.Clear()
$PSDefaultParameterValues += @{"Format-List:Force" = $true}
$PSDefaultParameterValues += @{"Get-*:OutVariable" = "__"}
$PSDefaultParameterValues += @{"Install-Module:Repository" = "PSGallery"}

# Cleanup bad local repositories
function Clear-PSRepository {
    Get-PSRepository | ForEach-Object {
        $uri = [uri] $_.SourceLocation
        if ($uri.scheme -notlike 'http*' -and !(test-path $uri.OriginalString)) {
            $_ | Unregister-PSRepository
        }
    }
}

#Set-PSReadlineOption -EditMode Windows
if ($null -eq $IsWindows) {
    $IsWindows = $true
}


function Set-ConstrainedLanguageMode
{
    $ExecutionContext.SessionState.LanguageMode='ConstrainedLanguage'
    if($Global:TabTitle)
    {
        Set-TabTitle -Title "Constrained - $Global:TabTitle"
    }
}

function script:Get-CompletionResults {
    param(
        [object[]] $Objects,
        [string] $PropertyName,
        [string] $WordToComplete
    )

    $allWords = $Objects.$PropertyName

    $filteredWords = $allWords  | Where-Object {$_ -like "$WordToComplete*"}


    $result = [List[CompletionResult]]::new()
    $filteredWords | ForEach-Object {
        $item = [CompletionResult]::new($_)
        $result.Add($item)
        Write-Verbose "adding $_"
    }

    return $result
}

class MultipassImageNameCompleter : System.Management.Automation.IArgumentCompleter {

    [IEnumerable[CompletionResult]] CompleteArgument(
        [string]$commandName,
        [string]$parameterName,
        [string]$wordToComplete,
        [System.Management.Automation.Language.CommandAst]$commandAst,
        [System.Collections.IDictionary]$fakeBoundParameters
    ) {
        try {

            $imageNames = (multipass find --format json | convertfrom-Json).Images | ForEach-Object { $_ | get-member -Type NoteProperty }
            [List[CompletionResult]] $result = Get-CompletionResults -Objects $imageNames -PropertyName 'Name' -WordToComplete $wordToComplete
            return $result
        }
        catch {
            Write-Verbose "catch: $_ " -Verbose
            Write-Verbose "catch: $($_.ScriptStackTrace) " -Verbose
        }

        return @()
    }
}

function New-MultipassIntance
{
    param(
        [int] $CPU = 1,
        [int] $DiskGB = 16,
        [int] $MemMB = 1024,
        [Parameter(Mandatory)]
        [string] $Name,
        [ArgumentCompleter([MultipassImageNameCompleter])]
        [string] $Image
    )

    $arguments = @()

    $arguments += @(
        '--cpus'
        $CPU
    )

    $arguments += @(
        '--disk'
         "${DiskGB}G"
    )

    $arguments += @(
        '--mem'
        "${MemMB}M"
    )

    $arguments += @(
        '--name'
        $Name
    )

    $arguments += $Image

    Write-Verbose "running: multipass launch $($arguments -join ' ')" -v


    multipass launch $arguments
    <#>
    multipass launch --help
    Usage: multipass launch [options] [[<remote:>]<image> | <url>]
    Create and start a new instance.

    Options:
      -h, --help           Display this help
      -v, --verbose        Increase logging verbosity, repeat up to three times for
                           more detail
      -c, --cpus <cpus>    Number of CPUs to allocate.
                           Minimum: 1,

                           *****default: 1.
      -d, --disk <disk>    Disk space to allocate. Positive integers, in bytes, or
                           with K, M, G suffix.
                           Minimum: 512M,

                           ****default: 5G.
      -m, --mem <mem>      Amount of memory to allocate. Positive integers, in
                           bytes, or with K, M, G suffix.
                           Minimum: 128M,

                           ******default: 1G.
      -n, --name <name>    Name for the instance. If it is 'primary' (the
                           configured primary instance name), the user's home
                           directory is mounted inside the newly launched instance,
                           in 'Home'.
      --cloud-init <file>  Path to a user-data cloud-init configuration, or '-' for
      #>
}
# git aliases

git config --global alias.pushf "push --force-with-lease"
git config --global alias.discard "checkout --"
git config --global alias.logoneline "log --pretty=oneline"

function Enable-DockerExperimentalCli
{
    $dockerConfigFolder = "$env:userprofile/.docker"
    if(!(Test-Path $dockerConfigFolder)){ new-item -Type Directory -Path $dockerConfigFolder}
    $dockerCliConfig = "$env:userprofile/.docker/config.json"
    $dockerCliBackup = "$env:userprofile/.docker/config-backup.json"
    if(Test-Path $dockerCliConfig) { copy-item $dockerCliConfig $dockerCliBackup -force}
    @{experimental='enabled'}|ConvertTo-Json | Out-File -Encoding ascii -FilePath $dockerCliConfig
}

function Install-IfNotInstalled {
    param(
        [Parameter(Mandatory)]
        [string] $PackageName,

        [ValidateSet('brew', 'yarn')]
        [string] $PackageManager = 'brew',

        [string] $packageVersion
    )

    if (!(Get-Command $packageName -ErrorAction SilentlyContinue)) {
        switch ($PackageManager) {
            'brew' {
                Write-Verbose "insalling $PackageName ..." -Verbose
                brew install $PackageName
            }
            'yarn' {
                $yarnPackage = $PackageName
                if ($packageVersion) {
                    $yarnPackage += "@$packageVersion"
                }
                Write-Verbose "insalling $yarnPackage ..." -Verbose
                sudo yarn global add $yarnPackage
            }
        }
    }
}

function Test-Spelling
{
    param(
        [string[]]
        $Paths,
        [switch]
        $Fix

    )

    if(!(Get-Command mdspell -ErrorAction SilentlyContinue))
    {
        Install-IfNotInstalled -packageName node -PackageManager brew
        Install-IfNotInstalled -packageName yarn -PackageManager brew
        Install-IfNotInstalled -packageName markdown-spellcheck -PackageManager yarn -packageVersion 0.11.0
    }

    $fileList = @()

    foreach($path in $Paths)
    {
        if($path -match '^\.[/\\]')
        {
            $fileList += ($path -replace '^\.[/\\]')
        }
        else {
            $fileList += $path
        }
    }

    $extraParams = @()

    if(!$Fix.IsPresent)
    {
        $extraParams += '--report'
    }

    Write-Verbose "Testing spelling for $fileList" -Verbose
    mdspell $fileList --ignore-numbers --ignore-acronyms @extraParams --en-us --no-suggestions
}

function Clear-AzResourceGroup
{
    $null = Get-AzResourceGroup | ForEach-Object{
        $yes=[System.Management.Automation.Host.ChoiceDescription]::new('&Yes')
        $no=[System.Management.Automation.Host.ChoiceDescription]::new('&No')
        $result = Read-Choice -message "Delete $($_.ResourceGroupName)" -choices $yes, $no -caption question -defaultChoiceIndex 1
        if($result -eq '&Yes'){
            $_
        }
    } | Remove-AzResourceGroup -Force -AsJob
}

function Get-ProcessPreventingSleep
{
    param(
        [switch]
        $PassThru
    )
    $results = pmset -g assertions |
        Where-Object{$_ -match 'pid.*Prevent\w*Sleep'} |
            ForEach-Object{
                $null = $_ -match 'pid (\d*){1}.*(Prevent\w*Sleep)'
                $processId = $Matches.1
                $issue = $Matches.2
                $process = Get-Process -Id $processId
                $process | Add-Member -Name Issue -MemberType NoteProperty -Value $issue
                Write-Output $process
    }
    if($PassThru) {
        $results | ForEach-Object { Write-Output $_}
        return
    }

    $results | Select-Object Id, ProcessName, Issue
}

function Get-PSGitCommit
{
    $sma = Get-Item (Join-Path $PSHome "System.Management.Automation.dll")
    $formattedVersion = $sma.VersionInfo.ProductVersion
    $formattedVersion
}

New-Alias -Name Cleanup-AzResourceGroup -Value Clear-AzResourceGroup -Force

function ConvertTo-Base64
{
    param(
        [parameter(Mandatory,ValueFromPipeline = $true)]
        [string]$InputObject
    )

    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($InputObject))
}

function ConvertFrom-Base64
{
    param(
        [parameter(Mandatory,ValueFromPipeline = $true)]
        [string]$InputObject
    )

    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($InputObject))
}

function cdgit {
    [CmdletBinding(DefaultParameterSetName='Path', HelpUri='https://go.microsoft.com/fwlink/?LinkID=2097049')]
    param(
        [switch]
        ${PassThru}
    )

    DynamicParam {
        $repos = Get-ChildItem -Path '~/git' -Directory | Select-Object -ExpandProperty Name

        # Create the parameter attributs
        $Attributes = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        $ParameterAttr = [System.Management.Automation.ParameterAttribute]::new()
        $ParameterAttr.ParameterSetName = 'Path'
        $ParameterAttr.ValueFromPipeline = $true
        $ParameterAttr.ValueFromPipelineByPropertyName = $true
        $ParameterAttr.Position = 0
        $ParameterAttr.Mandatory = $Mandatory
        $Attributes.Add($ParameterAttr) > $null

        if($repos.Count -gt 0)
        {
            $ValidateSetAttr = [System.Management.Automation.ValidateSetAttribute]::new(([string[]]$repos))
            $Attributes.Add($ValidateSetAttr) > $null
        }

        # Create the parameter
        $Parameter = [System.Management.Automation.RuntimeDefinedParameter]::new("Path", [string], $Attributes)

        # Return parameters dictionaly
        $parameters = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        $parameters.Add("Path", $Parameter) > $null
        return $parameters
    }

    begin
    {
        try {
            $Path = $PSBoundParameters["Path"]
            $Path = Join-Path -Path '~/git' -ChildPath $Path
        } catch {
            throw
        }
    }

    process
    {
        try {
            Set-Location -Path $Path -PassThru:$PassThru
        } catch {
            throw
        }
    }
}

if(get-command github-copilot-cli -ErrorAction SilentlyContinue) {
    function Invoke-CopilotCli {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [parameter(mandatory=$true, position=0)]
            [string]
            $Command,
            [parameter(mandatory=$true, position=1, ValueFromRemainingArguments=$true)]
            $Query
        )

        $shellOutFile = [system.io.path]::GetTempFileName() + '.ps1'
        try {
            github-copilot-cli $Command $Query --shellout $shellOutFile
            if(Test-Path $shellOutFile) {
                $script = Get-Content -Path $shellOutFile -Raw
                $sb = [scriptblock]::create($script)
                if ($PSCmdlet.ShouldProcess($sb.ToString(), 'Invoke Script') ) {
                    & $sb
                }
            }
        }
        finally {
            remove-item -Path $shellOutFile -ErrorAction SilentlyContinue -Force
        }


    }

    function Invoke-CopilotGitAssist {
        [Alias("git?")]
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [parameter(mandatory=$true, position=0, ValueFromRemainingArguments=$true)]
            $Query
        )
        Invoke-CopilotCli -Command git-assist -Query $Query
    }

    function Invoke-CopilotGHAssist {
        [Alias("gh?")]
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [parameter(mandatory=$true, position=0, ValueFromRemainingArguments=$true)]
            $Query
        )
        Invoke-CopilotCli -Command gh-assist -Query $Query
    }

    function Invoke-CopilotWhatTheShell {
        [Alias("wts","wts?")]
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [parameter(mandatory=$true, position=0, ValueFromRemainingArguments=$true)]
            $Query
        )
        Invoke-CopilotCli -Command what-the-shell -Query $Query
    }
}
