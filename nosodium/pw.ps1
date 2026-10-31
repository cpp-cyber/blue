<#
.SYNOPSIS
    Interactive Controlled Credential Rotation (Unmasked Plain Text Input)
.DESCRIPTION
    Iterates through all Local Accounts and ALL Active Directory Domain Users.
    Displays typed passwords in plain text. Compatible across Windows Server 2012 to 2025.
#>

Import-Module ActiveDirectory -ErrorAction SilentlyContinue

function Set-UserCredentialPrompt {
    param(
        [string]$Username,
        [string]$Type
    )

    $choice = Read-Host "`nChange password for [$Type User: $Username]? ([Y]es / [S]kip / [Q]uit)"
    
    if ($choice -eq 'Q' -or $choice -eq 'q') { return $false }
    if ($choice -ne 'Y' -and $choice -ne 'y') { 
        [Console]::WriteLine("[-] Skipped $Username.")
        return $true 
    }

    # Plain text input so characters are fully visible on screen
    $passPlain = Read-Host "Enter new password for $Username"

    if ([string]::IsNullOrWhiteSpace($passPlain)) {
        [Console]::WriteLine("[-] Password cannot be empty. Skipped $Username.")
        return $true
    }

    # Convert plain text to SecureString for Active Directory cmdlet
    $passSecure = ConvertTo-SecureString $passPlain -AsPlainText -Force

    try {
        if ($Type -eq "Local") {
            $user = [ADSI]"WinNT://$env:COMPUTERNAME/$Username,user"
            $user.SetPassword($passPlain)
            $user.SetInfo()
            [Console]::WriteLine("[+] Local account '$Username' password updated successfully.")
        } elseif ($Type -eq "Domain") {
            Set-ADAccountPassword -Identity $Username -NewPassword $passSecure -Reset
            Set-ADUser -Identity $Username -PasswordNeverExpires $true
            [Console]::WriteLine("[+] Domain user '$Username' password updated successfully.")
        }
    } catch {
        [Console]::WriteLine("[-] Error setting password for $Username - " + $_.Exception.Message)
    }
    return $true
}

[Console]::WriteLine("=================================================================")
[Console]::WriteLine("             CCDC INTERACTIVE CREDENTIAL ROTATION                ")
[Console]::WriteLine("=================================================================")

# 1. Local Accounts (Member Servers & Standalone hosts)
$localUsers = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
if ($localUsers) {
    [Console]::WriteLine("[*] Checking Local Accounts...")
    foreach ($lUser in $localUsers) {
        $continue = Set-UserCredentialPrompt -Username $lUser -Type "Local"
        if (-not $continue) { break }
    }
}

# 2. ALL Active Directory Domain Users (Recursive across all OUs)
if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
    [Console]::WriteLine("[*] Enumerating All Domain Users from Active Directory...")
    $allDomainUsers = @()

    # Method A: Active Directory Module
    if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
        $allDomainUsers = Get-ADUser -Filter * -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName
    }

    # Method B: ADSI LDAP Fallback (Server 2012 / PS 4.0 compatible)
    if (-not $allDomainUsers -or $allDomainUsers.Count -eq 0) {
        try {
            $rootDSE = [ADSI]"LDAP://RootDSE"
            $defaultNamingContext = $rootDSE.defaultNamingContext
            $ldapRoot = [ADSI]"LDAP://$defaultNamingContext"
            $searcher = New-Object System.DirectoryServices.DirectorySearcher($ldapRoot)
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user))"
            $searcher.PageSize = 1000
            $searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
            
            $results = $searcher.FindAll()
            foreach ($r in $results) {
                $allDomainUsers += [string]$r.Properties["samaccountname"]
            }
        } catch {}
    }

    if ($allDomainUsers.Count -gt 0) {
        [Console]::WriteLine("[+] Discovered " + $allDomainUsers.Count + " total domain users.")
        foreach ($dUser in ($allDomainUsers | Sort-Object)) {
            if ($dUser.EndsWith("$")) { continue }

            $continue = Set-UserCredentialPrompt -Username $dUser -Type "Domain"
            if (-not $continue) { 
                [Console]::WriteLine("[!] Rotation aborted by user.")
                break 
            }
        }
    } else {
        [Console]::WriteLine("[-] No domain users found or unable to contact domain controller.")
    }
}

[Console]::WriteLine("`n[+] Credential rotation sequence complete.")
