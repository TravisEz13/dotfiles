function Get-CITestPolicyCert {
    dir Cert:\CurrentUser\My\ | ?{$_.subject -like '*-cipolicytest'}
}

function New-CITestPolicy {
    param(
        [switch]
        $SkipElevationCheck
    )
    if (!(Test-IsElevated) -and !$SkipElevationCheck ) {
        throw "Must be run elevated"
    }
    
    $basePolicyXml = "$psscriptroot\basePolicy.xml"
    $policyXml = '.\SystemCIPolicy.xml'

    #$rules = @(New-CIPolicyRule -FilePathRule "C:\Program Files\*" -UserWriteablePaths)

    #Merge-CIPolicy -PolicyPaths $basePolicyXml -OutputFilePath $policyXml -Rules $rules -ErrorAction stop
    Copy-Item -Path $basePolicyXml -Destination $policyXml

    #New-CIPolicy -Level PcaCertificate -FilePath $policyXml -UserPEs -Audit:$false
    Set-RuleOption -FilePath $policyXml -Option 3 -Delete -ErrorAction stop
    Set-RuleOption -FilePath $policyXml -Option 16 -ErrorAction stop

    $cert = Get-CITestPolicyCert
    if(!$cert) {
        $cert = New-SelfSignedCertificate -DnsName "$env:COMPUTERNAME-cipolicytest" -CertStoreLocation "Cert:\CurrentUser\My\" -Type CodeSigningCert  -ErrorAction stop
        if (!(Test-Path C:\certs)) {
            $null = new-item -itemType Directory -Path C:\certs
        }
        Export-Certificate -Cert $cert -FilePath c:\certs\signing.cer
        $null = Import-Certificate -FilePath C:\certs\signing.cer -CertStoreLocation "Cert:\CurrentUser\Root\"
        $cert = Get-CITestPolicyCert
    }
    $cert | Format-List * | out-string | Write-Verbose

    <# dir "$pshome\pwsh.exe" | Set-AuthenticodeSignature -Certificate $cert #>

    Add-SignerRule -FilePath $policyXml -CertificatePath c:\certs\signing.cer -User

    $null = ConvertFrom-CIPolicy -XmlFilePath $policyXml -BinaryFilePath .\SIPolicy.p7b

    citool --update-policy .\SIPolicy.p7b -json
}

Function Set-AuthenticodeSignatureForCiPolicy {
    param(
        [parameter(ValueFromPipeline)]
        [string[]]
            $Path
        )

    Begin {
        $pathList = @()
        $cert = Get-CITestPolicyCert
    }

    Process {
        $pathList += $Path
    }

    End {
        $total = $pathList.Count
        $current = 0
        $signed = 0
        $activityName = "signing for ci"
        foreach($filePath in $pathList) {
            $current++
            Write-Progress -Activity $activityName -Status "checking signature for $filePath" -PercentComplete (100*$current/$total)
            $sig = (Get-AuthenticodeSignature $filePath)
            if($sig.Status -ne 'Valid' -and $sig.SignerCertificate.Subject -notlike '*-cipolicytest') {
                $signed++
                Write-Progress -Activity $activityName -Status "signing $filePath" -PercentComplete (100*$current/$total)
                $null=Set-AuthenticodeSignature -Certificate $cert -FilePath $filePath
            }
        }
        Write-Progress -Activity $activityName -Completed
        Write-Verbose "signed:$signed; total: $total" -Verbose
    }
}

function Test-IsElevated {
    $IsElevated = $false
    if ( $IsWindows ) {
        # on Windows we can determine whether we're executing in an
        # elevated context
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $windowsPrincipal = New-Object 'Security.Principal.WindowsPrincipal' $identity
        if ($windowsPrincipal.IsInRole("Administrators") -eq 1) {
            $IsElevated = $true
        }
    }
    else {
        # on Linux, tests run via sudo will generally report "root" for whoami
        if ( (whoami) -match "root" ) {
            $IsElevated = $true
        }
    }
    return $IsElevated
}

function Invoke-SignProject {
    param(
        $ProjectPath
    )
    $files = @()
    $files += Get-ChildItem "$ProjectPath\*" -Recurse | Where-Object { $_.Extension -in '.dll', '.exe' -or $_.Extension -like '.ps*'}
    $files  | Set-AuthenticodeSignatureForCiPolicy
}
