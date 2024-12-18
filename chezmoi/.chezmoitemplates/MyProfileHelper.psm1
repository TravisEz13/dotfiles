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

function Set-ICloudLocation {
    [alias('cdicloud')]
    [CmdletBinding(DefaultParameterSetName = 'Path', HelpUri = 'https://go.microsoft.com/fwlink/?LinkID=2097049')]
    param(
    )

    Push-Location "~/Library/Mobile Documents/com~apple~CloudDocs/"
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

    [UInt32]
    $FailedCount

    [void] Resolve([string]$Message='default') {
        if($this.Target -eq '*') {
            $this.IsResolved = $true
            return
        }
        Write-Verbose -Message "resolving ($Message) $($this.Target)"
        $this.ResolvedTarget = dig -x $this.Target +noall +answer +nocomments |
            Where-Object { $_ -match '^[^;]' } |
            ForEach-Object { ($_ -split '[ \t]')[4] }
        $this.IsResolved = $true
    }

    [bool]
    $IsResolved = $false
}

class PingPathData {
    [datetime]
    $Expiration

    [string[]]
    $TargetList
}

enum InternetProtocol {
    IPv4
    IPv6
}

[System.Collections.Generic.Dictionary[String,PingPathResult]]$script:ResultCache = [System.Collections.Generic.Dictionary[String,PingPathResult]]::new();

function Merge-PingPath {
    [CmdletBinding()]
    param(
        [PingPathResult[]]
        $ResultToMerge
    )

    [PingPathResult[]]$newResults = @()

    if($ResultToMerge.Count -eq 0) {
        throw "no results to merge"
    }

    foreach($result in $ResultToMerge) {
        $target= $result.Target
        if ($script:ResultCache.ContainsKey($target)) {
            $existingResult = $script:ResultCache[$target]
            $totalCount = $existingResult.Count + $result.Count
            $totalFailedCount = $existingResult.FailedCount + $result.FailedCount

            if ($totalCount -gt 0) {
                $existingResult.lossRate = 100 * $totalFailedCount / $totalCount
            }
            $existingResult.Count = $totalCount
            $newResults += $existingResult
            $script:ResultCache[$target] = $existingResult
        }
        else {
            $script:ResultCache[$target] = $result
            $newResults += $result
        }
    }
    foreach ($result in $newResults) {
        if (!$result.IsResolved) {
            $result.Resolve('Merge')
        }
    }

    return $newResults
}

[System.Collections.Generic.Dictionary[string, PingPathData]]$script:PingPathCache = [System.Collections.Generic.Dictionary[string, PingPathData]]::new();
[int]$script:PingPathCacheExpirationMinutes = 1
function Get-PingPathData {
    [CmdletBinding()]
    param(
        [string]
        $TargetName,

        [InternetProtocol]
        $Protocol = [InternetProtocol]::IPv6
    )

    if ($script:PingPathCache.ContainsKey($TargetName)) {
        [PingPathData]$cacheData = $script:PingPathCache[$TargetName]
        $targets = $cacheData.TargetList
        if ($cacheData.Expiration -gt (Get-Date)) {
            return $targets
        }
        else {
            $null=$script:PingPathCache.Remove($TargetName)
        }
    }

    switch ($Protocol) {
        "IPv6" {
            $traceCommand = 'traceroute6'
        }
        "IPv4" {
            $traceCommand = 'traceroute'
        }
        default {
            throw "unknown protocol $Protocol"
        }
    }

    $activityName = "Finding ping Path"

    Write-Progress -Activity $activityName -Status "Finding Path to $TargetName ..." -PercentComplete 0
    if ($IsMacOs) {
        $rawTrStrings = &$traceCommand -I -q 1 -w 1 -n $TargetName 2>&1
        if($LASTEXITCODE -ne 0) {
            Write-Warning ($rawTrStrings -join "`n")
        }
        $trStrings = $rawTrStrings |
        Where-Object { $_ -match '^\s?\d+\s+' }
        Write-Verbose -Message "rawTrStrings: $rawTrStrings"
    }

    Write-Verbose -Message "trStrings: $trStrings"

    [string[]]$targets = $trStrings | ForEach-Object {
        $null = $_ -match '^\s?\d+\s+([^\s]*)'
        $target = $Matches[1]
        Write-Output $target
    }

    Write-Progress -Activity $activityName -Status "Finding Path to $TargetName ..." -PercentComplete 100 -Completed

    [PingPathData]$data = [PingPathData]@{
        Expiration = (Get-Date).AddMinutes($script:PingPathCacheExpirationMinutes)
        TargetList = $targets
    }

    $script:PingPathCache[$TargetName] = $data
    return $targets
}

function Invoke-PingPath {
    [CmdletBinding()]
    param(
        [string]
        $TargetName,

        [ValidateScript({ $_ -gt 0 })]
        [uint]
        $Count = 25,

        [InternetProtocol]
        $Protocol = [InternetProtocol]::IPv6,

        [switch] $Continuous,

        [switch] $NoProgress,

        [switch] $NoResolve,

        [int] $PathRefreshMinutes = 1
    )

    if ($Continuous) {
        $script:PingPathCacheExpirationMinutes = $PathRefreshMinutes
        $null = Get-PingPathData -TargetName $TargetName -Protocol $Protocol
        $lastProgressPreference = $local:ProgressPreference
        $local:ProgressPreference = 'SilentlyContinue'
        try {
            $count = 1
            while ($true) {
                $currentResult = Invoke-PingPath -TargetName $TargetName -Count $count -Protocol $Protocol -NoProgress -NoResolve
                $mergedResults = Merge-PingPath -ResultToMerge $currentResult
                $output = $mergedResults | Format-Table | out-string
                Clear-Host
                Write-Host $output
                if($count -lt 5) {
                    $count++
                }
                #Start-Sleep -Seconds 2
            }
        }
        finally {
            $local:ProgressPreference = $lastProgressPreference
        }
    }
    else {
        $activityName = "Ping path"

        Update-FormatData -AppendPath $PSScriptRoot\PingPathResult.format.ps1xml

        $pathData = Get-PingPathData -TargetName $TargetName -Protocol $Protocol

        $doneCount = 0
        $hostCount = $pathData.count
        $pathData | ForEach-Object {
            $target = $_
            $ping = @()
            if ($target -ne '*') {
                if (!$NoProgress) {
                    Write-Progress -Activity $activityName -Status "Finding loss rate to $target ..." -PercentComplete (100 * $doneCount / $hostCount)
                }
                if ($Protocol -eq [InternetProtocol]::IPv4) {
                    $escapedTarget = $target
                }
                else {
                    $escapedTarget = "[$target]"
                }

                $ping = Test-Connection -TargetName $escapedTarget -Count $Count -ErrorAction SilentlyContinue
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
                    FailedCount    = $Count - $successPings
                } | ForEach-Object {
                    if(!$NoResolve){
                        $_.Resolve('Invoke')
                    }
                    $_ }| Write-Output
            }
            else {
                [PingPathResult]@{
                    Target = $target
                } | Write-Output
            }
            $doneCount++
        }
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

function Invoke-OcrMyPDF {
    param(
        $Path,
        [switch]
        $Rotate,
        [double]
        $RotateThreshold = 0,
        [switch]
        $ForceOcr
    )

    Get-ChildItem -Path $Path -Filter *.pdf -Recurse | ForEach-Object {
        $name = $_.FullName
        Write-Verbose -Verbose $name
        $arguments = @(
            '-O1'
            '--clean'
        )
        if ($Rotate) {
            $arguments += '--rotate-pages'
        }
        if ($RotateThreshold -ne 0 -and $Rotate) {
            $arguments += @(
                '--rotate-pages-threshold'
                $RotateThreshold
            )
        }
        if ($ForceOcr) {
            $arguments += '--force-ocr'
        }
        Write-Verbose -Verbose "Running: ocrmypdf $arguments <fileparams>"
        ocrmypdf $arguments $name $name
    }
}

function Publish-AzStorageFolderToStaticWeb {
    throw "not really implemented"

    $storageAccountName = 'account'
    $filter = '7.2.20*'
    $srcContainerName = 'tool'
    $newPrefix = $srcContainerName
    $publishContainer = '$web'

    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName
    $srcBlob = Get-AzStorageBlob -Container $srcContainerName   -Context $ctx
    $srcBlob | Where-Object { $_.name -like $filter } | % { [pscustomObject]@{old = $_.name; new = "$newPrefix/$($_.name)" } }
    | % {
        $dest = $_.new
        $src = $_.old
        Write-Verbose -Verbose "Copying tool/$src to `$web/$dest"
        Copy-AzStorageBlob -DestContainer $publishContainer  -DestBlob $dest -SrcContainer $srcContainerName  -SrcBlob $src  -Context $ctx  -verbose -confirm:$true
    }
}

function Invoke-CleanupDownloads {

    # Define the Downloads folder path
    $downloadsPath = [Environment]::GetFolderPath("UserProfile") + "/Downloads"
    Write-Verbose "downloadsPath: $downloadsPath" -Verbose

    # Define the scoring function
    function Get-FileScore {
        param (
            [System.IO.FileInfo]$file
        )
        $ageInDays = (Get-Date) - $file.LastWriteTime
        $sizeInMB = $file.Length / 1MB
        # Calculate score (you can adjust the formula as needed)
        $score = ($ageInDays.TotalDays * 0.5) + ($sizeInMB * 0.5)
        return $score
    }

    # Get all files in the Downloads folder
    $files = Get-ChildItem -Path $downloadsPath -File -Recurse

    # Define the score threshold for deletion
    $scoreThreshold = 100

    # Delete files with a score above the threshold
    foreach ($file in $files) {
        $score = Get-FileScore -file $file
        if ($score -gt $scoreThreshold) {
            Remove-Item -Path $file.FullName -Force
            Write-Verbose -Verbose "Deleted $($file.FullName) with score $score"
        }
    }

    # Remove empty folders
    $folders = Get-ChildItem -Path $downloadsPath -Directory -Recurse
    foreach ($folder in $folders) {
        if (-not (Get-ChildItem -Path $folder.FullName)) {
            Remove-Item -Path $folder.FullName -Force
            Write-Verbose -Verbose "Deleted empty folder $($folder.FullName)"
        }
    }
}