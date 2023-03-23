# Cleanup bad local repositories
function Clear-PSRepository {
    Get-PSRepository | ForEach-Object {
        $uri = [uri] $_.SourceLocation
        if ($uri.scheme -notlike 'http*' -and !(test-path $uri.OriginalString)) {
            $_ | Unregister-PSRepository
        }
    }
}

function Set-ConstrainedLanguageMode
{
    $ExecutionContext.SessionState.LanguageMode='ConstrainedLanguage'
    if($Global:TabTitle)
    {
        Set-TabTitle -Title "Constrained - $Global:TabTitle"
    }
}

function Enable-DockerExperimentalCli
{
    $dockerConfigFolder = "$env:userprofile/.docker"
    if(!(Test-Path $dockerConfigFolder)){ new-item -Type Directory -Path $dockerConfigFolder}
    $dockerCliConfig = "$env:userprofile/.docker/config.json"
    $dockerCliBackup = "$env:userprofile/.docker/config-backup.json"
    if(Test-Path $dockerCliConfig) { copy-item $dockerCliConfig $dockerCliBackup -force}
    @{experimental='enabled'}|ConvertTo-Json | Out-File -Encoding ascii -FilePath $dockerCliConfig
}

# Used at runtime
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
    [alias('Cleanup-AzResourceGroup')]
    [CmdletBinding()]
    param()
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


function Set-GitLocation {
    [alias('cdgit')]
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
        github-copilot-cli $Command "$Query" --shellout $shellOutFile
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

function Invoke-ChezmoiEdit {
    [alias('chezmoi-edit')]
    param()

    code -w $(chezmoi source-path)
    chezmoi apply
}

$gitHeads = @{}

function New-BranchFromMain {
    param(
        [Parameter(Mandatory)]
        [string]
        $BranchName,
        [switch]
        $Overwrite
    )

    $activityName = "New Branch from Main"
    $remote = git remote | Select-String -Pattern 'upstream|origin' -NoEmphasis | Where-Object { $_ } | Sort-Object | Select-Object -First 1
    Write-Progress -Activity $activityName -Status "Fetching $remote" -PercentComplete 1
    git fetch $remote
    if (!$gitHeads.ContainsKey($PWD)) {
        Write-Progress -Activity $activityName -Status "Finding main" -PercentComplete 10
        $mainHead = git ls-remote --heads $remote |
            ForEach-Object { ($_ -split '\s+')[1] } |
            where-object { $_ -match '^refs/heads/(master|main)$' }
        $gitHeads[$PWD] = $mainHead
    }

    $mainHead = $gitHeads[$PWD]
    $ref = $mainHead -replace 'refs/heads', $remote
    Write-Progress -Activity $activityName -Status "Creating $BranchName from $ref" -PercentComplete 90
    $switch = '-c'
    if ($Overwrite) {
        $switch = '-C'
    }
    git switch $ref $switch $BranchName
    git branch --unset-upstream
    git log --oneline -n 5
    Write-Progress -Activity $activityName -Status "Done" -Completed
}

function Invoke-Mariner {
    param(
        [hashtable]
        $Environment
    )
    $tag = 'mymariner'
    docker build "$PSScriptRoot/mariner" -t $tag
    $environmentParams =@()
    foreach($key in $Environment.Keys) {
        $value = $Environment.$key
        $environmentParams += @(
            '--env'
            "$key=$value"
        )
    }
    docker run -it $environmentParams --rm $tag
}
