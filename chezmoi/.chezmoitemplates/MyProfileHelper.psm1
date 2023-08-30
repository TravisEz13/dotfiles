# Cleanup bad local repositories
function Clear-PSRepository {
    Get-PSRepository | ForEach-Object {
        $uri = [uri] $_.SourceLocation
        if ($uri.scheme -notlike 'http*' -and !(test-path $uri.OriginalString)) {
            $_ | Unregister-PSRepository
        }
    }
}

function Set-ConstrainedLanguageMode {
    $ExecutionContext.SessionState.LanguageMode = 'ConstrainedLanguage'
    if ($Global:TabTitle) {
        Set-TabTitle -Title "Constrained - $Global:TabTitle"
    }
}

function Enable-DockerExperimentalCli {
    $dockerConfigFolder = "$env:userprofile/.docker"
    if (!(Test-Path $dockerConfigFolder)) { new-item -Type Directory -Path $dockerConfigFolder }
    $dockerCliConfig = "$env:userprofile/.docker/config.json"
    $dockerCliBackup = "$env:userprofile/.docker/config-backup.json"
    if (Test-Path $dockerCliConfig) { copy-item $dockerCliConfig $dockerCliBackup -force }
    @{experimental = 'enabled' } | ConvertTo-Json | Out-File -Encoding ascii -FilePath $dockerCliConfig
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

function Test-Spelling {
    param(
        [string[]]
        $Paths,
        [switch]
        $Fix

    )

    if (!(Get-Command mdspell -ErrorAction SilentlyContinue)) {
        Install-IfNotInstalled -packageName node -PackageManager brew
        Install-IfNotInstalled -packageName yarn -PackageManager brew
        Install-IfNotInstalled -packageName markdown-spellcheck -PackageManager yarn -packageVersion 0.11.0
    }

    $fileList = @()

    foreach ($path in $Paths) {
        if ($path -match '^\.[/\\]') {
            $fileList += ($path -replace '^\.[/\\]')
        }
        else {
            $fileList += $path
        }
    }

    $extraParams = @()

    if (!$Fix.IsPresent) {
        $extraParams += '--report'
    }

    Write-Verbose "Testing spelling for $fileList" -Verbose
    mdspell $fileList --ignore-numbers --ignore-acronyms @extraParams --en-us --no-suggestions
}

function Clear-AzResourceGroup {
    [alias('Cleanup-AzResourceGroup')]
    [CmdletBinding()]
    param()
    $null = Get-AzResourceGroup | ForEach-Object {
        $yes = [System.Management.Automation.Host.ChoiceDescription]::new('&Yes')
        $no = [System.Management.Automation.Host.ChoiceDescription]::new('&No')
        $result = Read-Choice -message "Delete $($_.ResourceGroupName)" -choices $yes, $no -caption question -defaultChoiceIndex 1
        if ($result -eq '&Yes') {
            $_
        }
    } | Remove-AzResourceGroup -Force -AsJob
}

function Get-ProcessPreventingSleep {
    param(
        [switch]
        $PassThru
    )
    $results = pmset -g assertions |
    Where-Object { $_ -match 'pid.*Prevent\w*Sleep' } |
    ForEach-Object {
        $null = $_ -match 'pid (\d*){1}.*(Prevent\w*Sleep)'
        $processId = $Matches.1
        $issue = $Matches.2
        $process = Get-Process -Id $processId
        $process | Add-Member -Name Issue -MemberType NoteProperty -Value $issue
        Write-Output $process
    }
    if ($PassThru) {
        $results | ForEach-Object { Write-Output $_ }
        return
    }

    $results | Select-Object Id, ProcessName, Issue
}

function Get-PSGitCommit {
    $sma = Get-Item (Join-Path $PSHome "System.Management.Automation.dll")
    $formattedVersion = $sma.VersionInfo.ProductVersion
    $formattedVersion
}

function ConvertTo-Base64 {
    param(
        [parameter(Mandatory, ValueFromPipeline = $true)]
        [string]$InputObject
    )

    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($InputObject))
}

function ConvertFrom-Base64 {
    param(
        [parameter(Mandatory, ValueFromPipeline = $true)]
        [string]$InputObject
    )

    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($InputObject))
}


function Set-GitLocation {
    [alias('cdgit')]
    [CmdletBinding(DefaultParameterSetName = 'Path', HelpUri = 'https://go.microsoft.com/fwlink/?LinkID=2097049')]
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

        if ($repos.Count -gt 0) {
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

    begin {
        try {
            $Path = $PSBoundParameters["Path"]
            $Path = Join-Path -Path '~/git' -ChildPath $Path
        }
        catch {
            throw
        }
    }

    process {
        try {
            Set-Location -Path $Path -PassThru:$PassThru
        }
        catch {
            throw
        }
    }
}

function Invoke-CopilotCli {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [parameter(mandatory = $true, position = 0)]
        [string]
        $Command,
        [parameter(mandatory = $true, position = 1, ValueFromRemainingArguments = $true)]
        $Query
    )

    $shellOutFile = [system.io.path]::GetTempFileName() + '.ps1'
    try {
        github-copilot-cli $Command "$Query" --shellout $shellOutFile
        if (Test-Path $shellOutFile) {
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
        [parameter(mandatory = $true, position = 0, ValueFromRemainingArguments = $true)]
        $Query
    )
    Invoke-CopilotCli -Command git-assist -Query $Query
}

function Invoke-CopilotGHAssist {
    [Alias("gh?")]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [parameter(mandatory = $true, position = 0, ValueFromRemainingArguments = $true)]
        $Query
    )
    Invoke-CopilotCli -Command gh-assist -Query $Query
}

function Invoke-CopilotWhatTheShell {
    [Alias("wts", "wts?")]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [parameter(mandatory = $true, position = 0, ValueFromRemainingArguments = $true)]
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
    $remote = git remote | Select-String -Pattern 'upstream|origin' -NoEmphasis | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
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
    $environmentParams = @()
    foreach ($key in $Environment.Keys) {
        $value = $Environment.$key
        $environmentParams += @(
            '--env'
            "$key=$value"
        )
    }
    docker run -it $environmentParams --rm $tag
}

function Get-GitDatabases {
    param($root = "~/")
    Get-ChildItem -Path $root -Filter .git -Recurse -Directory -Attributes Hidden -ErrorAction SilentlyContinue | ForEach-Object {
        $resultString = (tmutil isexcluded ($_.FullName))
        Write-Verbose "'$resultString"
        $excluded = $resultString -like '*[Excluded]*'
        $kb = du -s -k  ($_.FullName) | ForEach-Object { ($_ -split '/s*')[0] }
        $_ |
        Add-Member -NotePropertyName TimeMachineExcluded -NotePropertyValue $excluded -PassThru |
        Add-Member -NotePropertyName TotalSize -NotePropertyValue ($kb * 1KB) -PassThru
    }
}

function Get-PRList {
    param(
        [switch] $Assigned,

        [ValidateSet('approved')]
        [string] $Review,

        [ValidateSet('false', 'true', 'all')]
        [string] $Draft,

        [Parameter(ParameterSetName = 'NotDraft')]
        [switch] $NoDraft,

        [string[]] $ExcludeLabel
    )
    $search = ""
    if ($Assigned) {
        $search += " assignee:TravisEz13"
    }
    if ($Review) {
        $search += " review:$Review"
    }
    if ($Draft ) {
        $search += " draft:true"

    }
    if ($NoDraft) {
        $search += ' draft:false'
    }
    foreach ($label in $ExcludeLabel) {
        $search += " -label:`"$label`""
    }
    Write-Verbose "search: '$search'" -Verbose
    gh pr list --search $search
}

class PingPathResult {
    [String]
    $Target

    [float]
    $lossRate

    [string]
    $ResolvedTarget

    [UInt32]
    $Count
}

enum InternetProtocol {
    IPv4
    IPv6
}

function Invoke-PingPath {
    param(
        [string]
        $TargetName,
        [ValidateScript({ $_ -gt 0 })]
        [uint]
        $Count = 25,
        [InternetProtocol]
        $Protocol = [InternetProtocol]::IPv6
    )
    $activityName = "Ping path"

    Update-FormatData -AppendPath $PSScriptRoot\PingPathResult.format.ps1xml

    switch ($Protocol) {
        "IPv6" {
            $traceCommand = 'traceroute6'
        }
        "IPv4" {
            $traceCommand = 'traceroute4'
        }
        default {
            throw "unknown protocol $Protocol"
        }
    }

    Write-Progress -Activity $activityName -Status "Finding Path to $TargetName ..." -PercentComplete 0
    if ($IsMacOs) {
        $trStrings = &$traceCommand -I -q 1 -w 1 -n $TargetName 2>&1 |
        Where-Object { $_ -match '^\s?\d+\s+' }
    }

    $doneCount = 0
    $hostCount = $trStrings.count
    $trStrings | ForEach-Object {
        $null = $_ -match '^\s?\d+\s+([^\s]*)'
        $target = $matches[1]
        $ping = @()
        if ($target -ne '*') {
            Write-Progress -Activity $activityName -Status "Finding loss rate to $target ..." -PercentComplete (100 * $doneCount / $hostCount)
            if ($Protocol -eq [InternetProtocol]::IPv4) {
                $escapedTarget = $target
            }
            else {
                $escapedTarget = "[$target]"
            }
            Write-Verbose -Message "Testing: $target ..."
            $ping = Test-Connection -TargetName $escapedTarget -Count $Count
            $results = $ping | group-object -Property status
            $successPings = ($results | Where-Object { $_.name -eq 'success' }).Count
            $successRate = [float]$successPings / $Count
            $lossRate = 1 - $successRate
            $resolvedTarget = dig -x $target +noall +answer +nocomments |
            Where-Object { $_ -match '^[^;]' } |
            ForEach-Object { ($_ -split '[ \t]')[4] }
            [PingPathResult]@{
                Target         = $target
                LossRate       = $lossRate * 100
                ResolvedTarget = $resolvedTarget
                Count          = $Count
            } | Write-Output
        }
        else {
            [PingPathResult]@{
                Target = $target
            } | Write-Output
        }
        $doneCount++
    }
}

#https://www.michev.info/blog/post/2140/decode-jwt-access-and-id-tokens-via-powershell

function ConvertFrom-JWTtoken {

    [cmdletbinding()]
    param([Parameter(Mandatory=$true)][string]$token)

    #Validate as per https://tools.ietf.org/html/rfc7519
    #Access and ID tokens are fine, Refresh tokens will not work
    if (!$token.Contains(".") -or !$token.StartsWith("eyJ")) {
        Write-Error "Invalid token" -ErrorAction Stop
    }

    #Header
    $tokenheader = $token.Split(".")[0].Replace('-', '+').Replace('_', '/')
    #Fix padding as needed, keep adding "=" until string length modulus 4 reaches 0
    while ($tokenheader.Length % 4) { Write-Verbose "Invalid length for a Base-64 char array or string, adding ="; $tokenheader += "=" }
    Write-Verbose "Base64 encoded (padded) header:"
    Write-Verbose $tokenheader
    #Convert from Base64 encoded string to PSObject all at once
    Write-Verbose "Decoded header:"
    [System.Text.Encoding]::ASCII.GetString([system.convert]::FromBase64String($tokenheader)) | ConvertFrom-Json | fl | Out-Default

    #Payload
    $tokenPayload = $token.Split(".")[1].Replace('-', '+').Replace('_', '/')
    #Fix padding as needed, keep adding "=" until string length modulus 4 reaches 0
    while ($tokenPayload.Length % 4) { Write-Verbose "Invalid length for a Base-64 char array or string, adding ="; $tokenPayload += "=" }
    Write-Verbose "Base64 encoded (padded) payoad:"
    Write-Verbose $tokenPayload
    #Convert to Byte array
    $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
    #Convert to string array
    $tokenArray = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)
    Write-Verbose "Decoded array in JSON format:"
    Write-Verbose $tokenArray
    #Convert from JSON to PSObject
    $tokobj = $tokenArray | ConvertFrom-Json
    Write-Verbose "Decoded Payload:"

    return $tokobj
}

function Invoke-InitCache {
    $env:home = $home
    $cacheRoot = "$env:home\Documents\windowspowershell"
    if(!(Test-Path $cacheRoot)) {
        $null = new-item -Path "$env:home\Documents\windowspowershell" -ItemType Directory
    }
}
function Get-PVForecast {
    Invoke-InitCache
    $pvCacheExpiration = Import-Cache -container 'PvForecastExpiration'
    if ($pvCacheExpiration -and $pvCacheExpiration -gt (Get-Date)) {
        $est = (Import-Cache -container 'PvForecast')
    }
    else {

        $headers = @{ Authorization = "Bearer $(Get-Secret -Name solcast -AsPlainText)" }
        $est = Invoke-RestMethod -Uri "https://api.solcast.com.au/rooftop_sites/$(Get-Secret -Name solcastSite -AsPlainText)/forecasts?format=json" -Headers $headers
        $est.forecasts | ForEach-Object {
            $estimate = $_
            $_.period_end.ToLocalTime() |
            ForEach-Object {
                Add-Member -NotePropertyName local_period_end -NotePropertyValue $_ -InputObject $estimate
            }
        }

        export-Cache -container 'PvForecast' -data $est
        export-Cache -container 'PvForecastExpiration' -data ((get-date).AddDays(1))
    }

    $now = Get-Date
    $est.forecasts | Where-Object { $_.local_period_end -ge $now }
}

function Get-PVMonthlyForecast {
    param(
        [double] $Latitude,
        [double] $Longitude,
        [int] $Tilt,
        [int] $Azimuth,
        [switch] $Refresh
    )

    Invoke-InitCache
    $pvCacheExpiration = Import-Cache -container 'PvMonthlyForecastExpiration'
    if ($pvCacheExpiration -and $pvCacheExpiration -gt (Get-Date) -and !$Refresh) {
        $est = (Import-Cache -container 'PvMonthlyForecast')
    }
    else {

        $headers = @{ Authorization = "Bearer $(Get-Secret -Name solcast -AsPlainText)" }


        $urlFormat = 'https://api.solcast.com.au/monthly_averages?latitude={0:f3}&longitude={1:f3}&timezone=-8&output_parameters=null&array_type=fixed&array_tilt={2}&array_azimuth={3}&format=json'
        $url = $urlFormat -f $Latitude, $Longitude, $tilt, $Azimuth
        Write-Verbose -Verbose "url:$url"
        $est = Invoke-RestMethod $url -Headers $headers

        export-Cache -container 'PvMonthlyForecast' -data $est
        export-Cache -container 'PvMonthlyForecastExpiration' -data ((get-date).AddDays(1))
    }

    return $est
}

function Get-PVEstimatedActuals {
    param(
        [switch]
        $Refresh
    )
    Invoke-InitCache
    $pvCacheExpiration = Import-Cache -container 'PvEstActualsExpiration'
    if ($pvCacheExpiration -and $pvCacheExpiration -gt (Get-Date) -and !$Refresh) {
        $est = (Import-Cache -container 'PvEstActuals')
    }
    else {

        $headers = @{ Authorization = "Bearer $(Get-Secret -Name solcast -AsPlainText)" }
        $est = Invoke-RestMethod -Uri "https://api.solcast.com.au/rooftop_sites/$(Get-Secret -Name solcastSite -AsPlainText)/estimated_actuals?format=json" -Headers $headers
        $est.estimated_Actuals | ForEach-Object {
            $estimate = $_
            $_.period_end.ToLocalTime() |
            ForEach-Object {
                Add-Member -NotePropertyName local_period_end -NotePropertyValue $_ -InputObject $estimate
            }
        }

        export-Cache -container 'PvEstActuals' -data $est
        export-Cache -container 'PvEstActualsExpiration' -data ((get-date).AddDays(1))
    }

    $est.estimated_Actuals | Sort-Object -Property local_period_end
}

function Show-PVForecast {
    if (!(Get-Module -ListAvailable poshtml5 -ErrorAction SilentlyContinue)) {
        Install-Module poshtml5
    }

    $est = Get-PVForecast  | Where-Object { $_.pv_estimate -gt 0.1 } | select-object -First 48
    $html = New-PWFPage -Title "Solar Production Estimates" -Charset UTF8 -Container -DarkTheme -Content { New-PWFChart -ChartType line -ChartValues ($est | Select-Object -ExpandProperty pv_estimate) -ChartTitle 'estimated kWh' -ChartLabels $est.local_period_end -DontShowTitle }
    $pagePath = 'temp:/PvEstChart.html'
    $html | out-file $pagePath
    & '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge' ((resolve-path $pagePath).ProviderPath)
}

function Show-PVEstimatedActuals {
    if (!(Get-Module -ListAvailable poshtml5 -ErrorAction SilentlyContinue)) {
        Install-Module poshtml5
    }

    $est = Get-PVEstimatedActuals  | Where-Object { $_.pv_estimate -gt 0.1 } | select-object -First 48
    $html = New-PWFPage -Title "Solar Production Estimates" -Charset UTF8 -Container -DarkTheme -Content { New-PWFChart -ChartType line -ChartValues ($est | Select-Object -ExpandProperty pv_estimate) -ChartTitle 'estimated kWh' -ChartLabels $est.local_period_end -DontShowTitle }
    $pagePath = 'temp:/PvEstActualChart.html'
    $html | out-file $pagePath
    & '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge' ((resolve-path $pagePath).ProviderPath)
}