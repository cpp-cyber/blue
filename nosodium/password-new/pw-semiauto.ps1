#Requires -Version 5.1
<#
.SYNOPSIS
    Reset explicitly selected local and/or Active Directory user passwords.
.DESCRIPTION
    Generates a unique AdjectiveAnimal##! passphrase for each selected account,
    previews all targets, and requires one explicit confirmation before changes.
    Successful credentials are written only to a timestamped file protected by
    an ACL for the current user and local Administrators.
    With no parameters, discovers local and Active Directory users and prompts
    y/n for each account to select targets for password reset.
.PARAMETER LocalUsers
    Local account names to reset. Can be combined with LocalUsersFile.
.PARAMETER DomainUsers
    Active Directory account identities (normally sAMAccountName) to reset.
    Can be combined with DomainUsersFile.
.PARAMETER LocalUsersFile
    UTF-8 text file containing one local account name per line.
.PARAMETER DomainUsersFile
    UTF-8 text file containing one AD account identity per line.
.PARAMETER ExcludeServiceAccounts
    Exclude AD users with one or more Service Principal Names (SPNs).
.PARAMETER AllExcept
    Discover all users except qualified names supplied as a comma-separated
    list or a text file path. Use Local\name (or .\name) and DOMAIN\name.
    Displays all remaining targets and requires one RESET confirmation.
.PARAMETER ForceChangeAtLogon
    Require each successfully reset AD user to change the password at next logon.
.PARAMETER SetPasswordNeverExpires
    Set PasswordNeverExpires for successfully reset AD users. Off by default.
.EXAMPLE
    .\pw-semiauto.ps1
.EXAMPLE
    .\pw-semiauto.ps1 -LocalUsers 'labuser1','labuser2'
.EXAMPLE
    .\pw-semiauto.ps1 -DomainUsersFile C:\CCDC\PCRs\domain-users.txt -ForceChangeAtLogon
.EXAMPLE
    .\pw-semiauto.ps1 -LocalUsers 'labuser1' -DomainUsers 'CORP\labuser2'
.EXAMPLE
    .\pw-semiauto.ps1 -AllExcept 'Local\Guest,CORP\scoring_svc' -ExcludeServiceAccounts
.EXAMPLE
    .\pw-semiauto.ps1 -AllExcept C:\CCDC\PCRs\exclude.txt
.NOTES
    Run elevated for local account changes. AD changes require the ActiveDirectory
    module, domain connectivity, and suitable delegated permissions. Passwords
    are plaintext in the protected output file; secure and transfer that file
    according to your organization's credential-handling process.
#>
[CmdletBinding()]
param(
    [string[]] $LocalUsers = @(),
    [string[]] $DomainUsers = @(),
    [string] $LocalUsersFile,
    [string] $DomainUsersFile,
    [switch] $ExcludeServiceAccounts,
    [string] $AllExcept,
    [switch] $ForceChangeAtLogon,
    [switch] $SetPasswordNeverExpires
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$OutputDirectory = 'C:\CCDC\PCRs'
$script:Rng = $null
$Adjectives = @(
    'Sneaky','Brave','Clever','Swift','Mighty','Gentle','Fierce','Lucky','Sleepy','Grumpy',
    'Happy','Jolly','Quiet','Loud','Bold','Shy','Wild','Calm','Proud','Silly',
    'Frosty','Sunny','Stormy','Cosmic','Rusty','Shiny','Dusty','Fuzzy','Spicy','Salty',
    'Crimson','Golden','Silver','Amber','Violet','Scarlet','Teal','Ivory','Cobalt','Emerald',
    'Nimble','Rapid','Steady','Stubborn','Curious','Cheerful','Daring','Eager','Fearless','Graceful',
    'Honest','Humble','Jumpy','Kindly','Lively','Merry','Noble','Plucky','Restless','Witty'
)
$Animals = @(
    'Zebra','Tiger','Otter','Falcon','Badger','Panda','Koala','Moose','Lemur','Gecko',
    'Heron','Walrus','Bison','Cobra','Dolphin','Eagle','Ferret','Gazelle','Hedgehog','Iguana',
    'Jaguar','Kiwi','Llama','Marmot','Narwhal','Ocelot','Penguin','Quokka','Raven','Salmon',
    'Toucan','Urchin','Viper','Wombat','Yak','Beaver','Cougar','Dingo','Elk','Fox',
    'Giraffe','Hamster','Ibis','Jackal','Kestrel','Lynx','Mantis','Newt','Osprey','Puffin',
    'Rhino','Sparrow','Turtle','Vulture','Weasel','Mongoose','Pelican','Squirrel','Stork','Tapir'
)

function Get-RandomIndex {
    param([Parameter(Mandatory = $true)][int] $Maximum)

    $bytes = New-Object byte[] 4
    $range = [uint64]4294967296
    $limit = $range - ($range % [uint64]$Maximum)
    do {
        $script:Rng.GetBytes($bytes)
        $value = [BitConverter]::ToUInt32($bytes, 0)
    } while ([uint64]$value -ge $limit)
    return [int]($value % [uint32]$Maximum)
}

function New-GeneratedPassphrase {
    $adjective = $script:Adjectives[(Get-RandomIndex -Maximum $script:Adjectives.Count)]
    $animal = $script:Animals[(Get-RandomIndex -Maximum $script:Animals.Count)]
    $digits = '{0:D2}' -f (Get-RandomIndex -Maximum 100)
    return "$adjective$animal$digits!"
}

function Get-RequestedNames {
    param(
        [string[]] $Names,
        [string] $FilePath,
        [string] $Kind
    )

    $all = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $Names) {
        if ($null -ne $name) { $all.Add($name) }
    }
    if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
        if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
            throw "$Kind user list file not found: $FilePath"
        }
        foreach ($line in Get-Content -LiteralPath $FilePath) { $all.Add($line) }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $result = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $all) {
        $name = $item.Trim()
        if ($name.Length -eq 0 -or $name.StartsWith('#')) { continue }
        if ($name.Contains(',') -or $name.Contains("`r") -or $name.Contains("`n")) {
            throw "Invalid $Kind account name: account names cannot contain commas or line breaks."
        }
        if ($seen.Add($name)) { $result.Add($name) }
    }
    return $result.ToArray()
}

function Resolve-LocalUser {
    param([Parameter(Mandatory = $true)][string] $Name)

    $computer = [ADSI]"WinNT://$env:COMPUTERNAME"
    foreach ($child in $computer.Children) {
        if ($child.SchemaClassName -eq 'User' -and
            [string]::Equals([string]$child.Name, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ Name = [string]$child.Name; Path = [string]$child.Path }
        }
    }
    throw "Local user not found: $Name"
}

function Confirm-UserSelection {
    param([Parameter(Mandatory = $true)][string] $Prompt)

    while ($true) {
        $raw = Read-Host $Prompt
        $answer = if ($null -eq $raw) { '' } else { $raw.Trim() }
        if ($answer -match '^(y|yes)$') { return $true }
        if ($answer -match '^(n|no)$') { return $false }
        Write-Host "Please enter 'y' or 'n'." -ForegroundColor Yellow
    }
}

function Get-ExcludedAccounts {
    param([string] $Value, [object[]] $Discovered, [string] $DomainPrefix)

    if ([string]::IsNullOrWhiteSpace($Value)) { throw '-AllExcept needs a list or file path.' }
    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        $entries = @(Get-Content -LiteralPath $Value)
    } else {
        if ($Value -match '[:/]' -or $Value -match '\.txt$') {
            throw "Exclusion file not found: $Value"
        }
        $entries = @($Value -split ',')
    }

    $known = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($user in $Discovered) {
        $prefix = if ($user.Kind -eq 'Local') { 'Local' } else { $DomainPrefix }
        [void]$known.Add("$prefix\$($user.Name)")
    }
    $excluded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) {
        $name = $entry.Trim()
        if (-not $name -or $name.StartsWith('#')) { continue }
        if ($name -match '^\.\\(.+)$') { $name = "Local\$($Matches[1])" }
        if ($name -notmatch '^[^\\]+\\[^\\]+$') { throw "Exclusion must be qualified as Local\name or DOMAIN\name: $name" }
        if (-not $known.Contains($name)) { throw "Exclusion does not match a discovered account: $name" }
        [void]$excluded.Add($name)
    }
    if ($excluded.Count -eq 0) { throw '-AllExcept contains no account names.' }
    return ,$excluded
}

function Set-CredentialFileAcl {
    param([Parameter(Mandatory = $true)][string] $Path)

    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRuleAll($rule) }

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $adminSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $inheritance = [Security.AccessControl.InheritanceFlags]::None
    $propagation = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $fullControl = [Security.AccessControl.FileSystemRights]::FullControl
    foreach ($sid in @($currentSid, $adminSid)) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, $fullControl, $inheritance, $propagation, $allow)
        [void]$acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

$localNames = @(Get-RequestedNames -Names $LocalUsers -FilePath $LocalUsersFile -Kind 'local')
$domainNames = @(Get-RequestedNames -Names $DomainUsers -FilePath $DomainUsersFile -Kind 'domain')
$targets = New-Object 'System.Collections.Generic.List[object]'
$allExceptMode = $PSBoundParameters.ContainsKey('AllExcept')
if ($allExceptMode -and ($PSBoundParameters.ContainsKey('LocalUsers') -or
        $PSBoundParameters.ContainsKey('DomainUsers') -or
        $PSBoundParameters.ContainsKey('LocalUsersFile') -or
        $PSBoundParameters.ContainsKey('DomainUsersFile'))) {
    throw '-AllExcept cannot be combined with explicit account names or account-list files.'
}
$discoveryMode = $PSBoundParameters.Count -eq 0 -or $allExceptMode -or
    ($PSBoundParameters.Count -eq 1 -and $PSBoundParameters.ContainsKey('ExcludeServiceAccounts'))

if ($localNames.Count -eq 0 -and $domainNames.Count -eq 0) {
    if ($discoveryMode) {
        Write-Host 'Discovering accounts...' -ForegroundColor Cyan
        $machineName = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { [Environment]::MachineName } else { $env:COMPUTERNAME }
        Write-Host "`nDiscovering local accounts on ${machineName}..." -ForegroundColor Cyan
        $discoveredLocal = @()
        try {
            $computer = [ADSI]"WinNT://$machineName"
            $discoveredLocal = @($computer.Children | Where-Object { $_.SchemaClassName -eq 'User' } |
                ForEach-Object {
                    [pscustomobject]@{
                        Kind     = 'Local'
                        Name     = [string]$_.Name
                        Identity = [string]$_.Path
                    }
                } |
                Sort-Object Name)
        } catch {
            if ($allExceptMode) { throw "Local user discovery failed; no accounts were changed. $($_.Exception.Message)" }
            Write-Warning "Could not enumerate local users: $($_.Exception.Message)"
        }

        $discoveredDomain = @()
        $partOfDomain = $false
        $domainCheckFailed = $false
        try { $partOfDomain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain }
        catch {
            if ($allExceptMode) { throw "Domain membership could not be determined; no accounts were changed. $($_.Exception.Message)" }
            $domainCheckFailed = $true
            Write-Warning "Could not determine domain membership: $($_.Exception.Message)"
        }
        $domainPrefix = $null
        if ($partOfDomain) {
            Write-Host "Discovering Active Directory users visible to this machine..." -ForegroundColor Cyan
            try {
                Import-Module ActiveDirectory -ErrorAction Stop
                $domainPrefix = (Get-ADDomain -ErrorAction Stop).NetBIOSName
                $discoveredDomain = @(Get-ADUser -Filter * -Properties Enabled,ServicePrincipalName -ErrorAction Stop |
                    ForEach-Object {
                        [pscustomobject]@{
                            Kind     = 'Domain'
                            Name     = $_.SamAccountName
                            Identity = $_.DistinguishedName
                            Enabled  = $_.Enabled
                            HasSPN   = [bool]$_.ServicePrincipalName
                        }
                    } |
                    Sort-Object Name)
            } catch {
                if ($allExceptMode) { throw "AD discovery failed; no accounts were changed. $($_.Exception.Message)" }
                Write-Warning "Could not enumerate AD users: $($_.Exception.Message)"
            }
        } elseif ($domainCheckFailed) {
            Write-Host "AD discovery skipped because domain membership could not be determined."
        } else {
            Write-Host "This machine is not domain-joined; AD users were not queried."
        }

        $allDiscovered = @($discoveredLocal) + @($discoveredDomain)
        if ($allDiscovered.Count -eq 0) {
            if ($allExceptMode) { throw 'No accounts were discovered; no passwords were changed.' }
            Write-Host "`nNo local or Active Directory users were discovered. No passwords were changed."
            return
        }

        $excluded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        if ($allExceptMode) {
            $excluded = Get-ExcludedAccounts -Value $AllExcept -Discovered $allDiscovered -DomainPrefix $domainPrefix
        }
        if ($ExcludeServiceAccounts) {
            $discoveredDomain = @($discoveredDomain | Where-Object { -not $_.HasSPN })
        }

        if ($allExceptMode) {
            foreach ($u in (@($discoveredLocal) + @($discoveredDomain))) {
                $prefix = if ($u.Kind -eq 'Local') { 'Local' } else { $domainPrefix }
                if (-not $excluded.Contains("$prefix\$($u.Name)")) { $targets.Add($u) }
            }
        } elseif ($discoveredLocal.Count -gt 0) {
            Write-Host "`nLocal accounts on ${machineName}:" -ForegroundColor Cyan
            foreach ($u in $discoveredLocal) {
                if (Confirm-UserSelection -Prompt "Change password for Local user '$($u.Name)'? [y/n]") {
                    $targets.Add([pscustomobject]@{ Kind = $u.Kind; Name = $u.Name; Identity = $u.Identity })
                }
            }
        }

        if (-not $allExceptMode -and $discoveredDomain.Count -gt 0) {
            Write-Host "`nActive Directory users:" -ForegroundColor Cyan
            foreach ($u in $discoveredDomain) {
                if (Confirm-UserSelection -Prompt "Change password for Domain user '$($u.Name)' (Enabled: $($u.Enabled))? [y/n]") {
                    $targets.Add([pscustomobject]@{ Kind = $u.Kind; Name = $u.Name; Identity = $u.Identity })
                }
            }
        }

        if ($targets.Count -eq 0) {
            Write-Host "`nNo accounts selected for password reset. No passwords were changed."
            return
        }
    } else {
        throw 'Select at least one account with -LocalUsers, -DomainUsers, or a user-list file.'
    }
} else {
    if ($ForceChangeAtLogon -and $localNames.Count -gt 0) {
        throw '-ForceChangeAtLogon applies only to AD users. Remove local users from this run or omit the switch.'
    }

    foreach ($name in $localNames) {
        $resolved = Resolve-LocalUser -Name $name
        $targets.Add([pscustomobject]@{ Kind = 'Local'; Name = $resolved.Name; Identity = $resolved.Path })
    }

    if ($domainNames.Count -gt 0) {
        Import-Module ActiveDirectory -ErrorAction Stop
        foreach ($name in $domainNames) {
            try {
                $user = Get-ADUser -Identity $name -Properties SamAccountName,ServicePrincipalName -ErrorAction Stop
            } catch {
                throw "Could not resolve AD user '$name': $($_.Exception.Message)"
            }
            if ($ExcludeServiceAccounts -and $user.ServicePrincipalName) { continue }
            $targets.Add([pscustomobject]@{
                Kind     = 'Domain'
                Name     = $user.SamAccountName
                Identity = $user.DistinguishedName
            })
        }
    }
}

if ($ForceChangeAtLogon -and @($targets | Where-Object Kind -eq 'Local').Count -gt 0) {
    throw '-ForceChangeAtLogon applies only to AD users. Remove local users or omit the switch.'
}
if ($targets.Count -eq 0) {
    Write-Host 'No accounts remain after filtering. No passwords were changed.'
    return
}

Write-Host "`nAccounts selected for password reset:" -ForegroundColor Cyan
$targets | Select-Object Kind, Name | Format-Table -AutoSize | Out-Host
$confirmation = Read-Host "Type RESET to change passwords for all $($targets.Count) selected account(s)"
if ($confirmation -cne 'RESET') {
    Write-Host 'No passwords were changed.'
    return
}

$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outputPath = Join-Path $OutputDirectory "pwreset_$timestamp.csv"
while (Test-Path -LiteralPath $outputPath) {
    $timestamp = '{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $outputPath = Join-Path $OutputDirectory "pwreset_$timestamp.csv"
}

$writer = $null
try {
    $fileStream = [IO.File]::Open($outputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $fileStream.Dispose()
    Set-CredentialFileAcl -Path $outputPath
    $writer = New-Object IO.StreamWriter($outputPath, $false, (New-Object Text.UTF8Encoding($false)))
    $script:Rng = [Security.Cryptography.RandomNumberGenerator]::Create()
} catch {
    if ($writer) { $writer.Dispose(); $writer = $null }
    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue }
    throw "Could not secure or prepare the credential output file; no password resets were started. $($_.Exception.Message)"
}

foreach ($target in $targets) {
    $password = $null
    $securePassword = $null
    $passwordWasSet = $false
    $rowStart = $writer.BaseStream.Position
    try {
        $password = New-GeneratedPassphrase
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $outputName = if ($target.Kind -eq 'Domain') { '{0}\{1}' -f (Get-ADDomain).NetBIOSName, $target.Name } else { $target.Name }
        $writer.WriteLine(('{0},{1}' -f $outputName, $password))
        $writer.Flush()

        if ($target.Kind -eq 'Local') {
            $localAccount = [ADSI]$target.Identity
            $localAccount.SetPassword($password)
            $passwordWasSet = $true
        } else {
            Set-ADAccountPassword -Identity $target.Identity -Reset -NewPassword $securePassword -ErrorAction Stop
            $passwordWasSet = $true
            if ($ForceChangeAtLogon) {
                try { Set-ADUser -Identity $target.Identity -ChangePasswordAtLogon $true -ErrorAction Stop }
                catch { Write-Warning "[warn] Password changed for '$($target.Name)', but force-change-at-logon could not be set: $($_.Exception.Message)" }
            }
            if ($SetPasswordNeverExpires) {
                try { Set-ADUser -Identity $target.Identity -PasswordNeverExpires $true -ErrorAction Stop }
                catch { Write-Warning "[warn] Password changed for '$($target.Name)', but PasswordNeverExpires could not be set: $($_.Exception.Message)" }
            }
        }

        Write-Host "[ok] $($target.Kind) user '$($target.Name)' password reset."
    } catch {
        if (-not $passwordWasSet) {
            try {
                $writer.BaseStream.SetLength($rowStart)
                $writer.BaseStream.Position = $rowStart
                $writer.Flush()
            } catch {
                Write-Warning "Could not roll back the pending credential row for '$($target.Name)'; inspect the protected output file."
            }
        }
        if (-not $passwordWasSet) {
            Write-Warning "[fail] $($target.Kind) user '$($target.Name)': $($_.Exception.Message)"
        }
    } finally {
        $password = $null
        $securePassword = $null
    }
}

$writer.Dispose()
if ($script:Rng) { $script:Rng.Dispose(); $script:Rng = $null }

Write-Host "Credential output saved to: $outputPath" -ForegroundColor Yellow
