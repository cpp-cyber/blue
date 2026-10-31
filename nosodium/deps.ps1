<#
.SYNOPSIS
    CCDC Service Account & Dependency Discovery Engine
.DESCRIPTION
    Maps domain user accounts to the services and applications that depend on them.
    Identifies Kerberos SPNs (Keycloak SSO, HTTP, SQL), Windows Services, 
    Scheduled Tasks, and Exchange System Mailboxes.
    Compatible across Windows Server 2012 through 2025. Pure ASCII.
#>

$ErrorActionPreference = "SilentlyContinue"

Write-Output "================================================================="
Write-Output "       CCDC SERVICE ACCOUNT & DEPENDENCY DISCOVERY ENGINE        "
Write-Output "================================================================="

# Cache local Windows Services by logon account
$serviceLogonMap = @{}
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.StartName -and $_.StartName -notmatch "LocalSystem|NT AUTHORITY") {
        $acc = ($_.StartName -split '\\')[-1].ToLower()
        if (-not $serviceLogonMap.ContainsKey($acc)) { $serviceLogonMap[$acc] = @() }
        $serviceLogonMap[$acc] += [PSCustomObject]@{
            Name        = $_.Name
            DisplayName = $_.DisplayName
            State       = $_.State
            PathName    = $_.PathName
        }
    }
}

# Cache Scheduled Tasks by logon account
$taskLogonMap = @{}
if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
        $userId = $_.Principal.UserId
        if ($userId -and $userId -notmatch "SYSTEM|LOCAL SERVICE|NETWORK SERVICE|^$") {
            $acc = ($userId -split '\\')[-1].ToLower()
            if (-not $taskLogonMap.ContainsKey($acc)) { $taskLogonMap[$acc] = @() }
            $taskLogonMap[$acc] += [PSCustomObject]@{
                TaskName = $_.TaskName
                TaskPath = $_.TaskPath
            }
        }
    }
}

function Show-AllServiceAccounts {
    Write-Output "`n[*] Scanning Active Directory for Service Accounts & Dependencies..."

    $userObjects = @()
    if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
        $userObjects = Get-ADUser -Filter * -Properties ServicePrincipalNames, Description, MemberOf -ErrorAction SilentlyContinue
    } else {
        # ADSI LDAP Fallback
        try {
            $rootDSE = [ADSI]"LDAP://RootDSE"
            $searcher = New-Object System.DirectoryServices.DirectorySearcher([ADSI]"LDAP://$($rootDSE.defaultNamingContext)")
            $searcher.Filter = "(&(objectCategory=person)(objectClass=user))"
            $searcher.PageSize = 1000
            $results = $searcher.FindAll()
            foreach ($r in $results) {
                $userObjects += [PSCustomObject]@{
                    SamAccountName        = [string]$r.Properties["samaccountname"]
                    ServicePrincipalNames = @($r.Properties["serviceprincipalname"])
                    Description           = [string]$r.Properties["description"]
                }
            }
        } catch {}
    }

    if (-not $userObjects -or $userObjects.Count -eq 0) {
        Write-Output "[-] Unable to query user objects from Active Directory."
        return
    }

    $discoveredList = @()

    foreach ($u in ($userObjects | Sort-Object SamAccountName)) {
        $uName = $u.SamAccountName
        if ($uName.EndsWith("$")) { continue } # Skip computer accounts

        $lowerName = $uName.ToLower()
        $spns = @($u.ServicePrincipalNames)
        $isServiceAccount = $false
        $type = "Standard User"
        $tiedApp = "None"
        $details = @()

        # 1. Check Exchange System Mailboxes
        if ($uName -match "^HealthMailbox") {
            $isServiceAccount = $true
            $type = "Exchange Internal"
            $tiedApp = "Exchange Active Monitoring (Health Mailbox)"
            $details += "DO NOT TOUCH / RESET (Exchange Managed Availability)"
        } elseif ($uName -match "^SM_") {
            $isServiceAccount = $true
            $type = "Exchange System"
            $tiedApp = "Exchange System / Arbitration Mailbox"
            $details += "Exchange setup & schema mailbox (Leave disabled)"
        }

        # 2. Check Kerberos SPNs (SSO, Keycloak, SQL, Web)
        if ($spns.Count -gt 0) {
            $isServiceAccount = $true
            $type = "Kerberos Service Account"
            foreach ($s in $spns) {
                if ($s -match "HTTP/(.*keycloak.*|.*sso.*)") {
                    $tiedApp = "Keycloak / SSO Authentication"
                    $details += "SPN: $s (Keycloak Single Sign-On)"
                } elseif ($s -match "HTTP/") {
                    if ($tiedApp -eq "None") { $tiedApp = "Web / HTTP Service (IIS/Apache)" }
                    $details += "SPN: $s"
                } elseif ($s -match "MSSQLSvc|SQL") {
                    $tiedApp = "Microsoft SQL Server"
                    $details += "SPN: $s"
                } else {
                    if ($tiedApp -eq "None") { $tiedApp = "Application Service" }
                    $details += "SPN: $s"
                }
            }
        }

        # 3. Check Windows Services (services.msc)
        if ($serviceLogonMap.ContainsKey($lowerName)) {
            $isServiceAccount = $true
            if ($type -eq "Standard User") { $type = "Windows Service Account" }
            foreach ($svc in $serviceLogonMap[$lowerName]) {
                if ($svc.DisplayName -match "Keycloak|SSO") {
                    $tiedApp = "Keycloak Service"
                } elseif ($tiedApp -eq "None") {
                    $tiedApp = $svc.DisplayName
                }
                $details += ("Service: " + $svc.Name + " (" + $svc.DisplayName + ") [State: " + $svc.State + "]")
            }
        }

        # 4. Check Scheduled Tasks
        if ($taskLogonMap.ContainsKey($lowerName)) {
            $isServiceAccount = $true
            if ($type -eq "Standard User") { $type = "Task Automation Account" }
            foreach ($t in $taskLogonMap[$lowerName]) {
                $details += ("Task: " + $t.TaskPath + $t.TaskName)
            }
        }

        # Display if it's a service account or has dependencies
        if ($isServiceAccount) {
            Write-Output "`n-----------------------------------------------------------------"
            Write-Output ("ACCOUNT NAME : " + $uName)
            Write-Output ("ACCOUNT TYPE : " + $type)
            Write-Output ("PRIMARY APP  : " + $tiedApp)
            Write-Output "DEPENDENCIES / DETAILS:"
            foreach ($d in $details) {
                Write-Output ("  -> " + $d)
            }
            $discoveredList += $uName
        }
    }

    Write-Output "`n================================================================="
    Write-Output ("TOTAL SERVICE ACCOUNTS IDENTIFIED: " + $discoveredList.Count)
    Write-Output ("ACCOUNTS LIST: " + ($discoveredList -join ', '))
    Write-Output "================================================================="
}

function Search-Account {
    $searchName = Read-Host "Enter username or service keyword to inspect (e.g. keycloak, sql, svc_)"
    if ([string]::IsNullOrWhiteSpace($searchName)) { return }

    Write-Output "`n[*] Searching for accounts matching: $searchName..."
    
    # Check SPNs
    if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
        Get-ADUser -Filter "SamAccountName -like '*$searchName*' -or ServicePrincipalName -like '*$searchName*'" -Properties ServicePrincipalNames, Description | ForEach-Object {
            Write-Output "`n[+] FOUND MATCH: $($_.SamAccountName)"
            Write-Output "    Description: $($_.Description)"
            Write-Output "    SPNs       : $($_.ServicePrincipalNames -join ', ')"
        }
    }

    # Check Services
    Get-CimInstance Win32_Service | Where-Object { $_.StartName -match $searchName -or $_.Name -match $searchName -or $_.DisplayName -match $searchName } | ForEach-Object {
        Write-Output "`n[+] MATCHING SERVICE: $($_.Name) ($($_.DisplayName))"
        Write-Output "    Logon Account: $($_.StartName)"
        Write-Output "    State        : $($_.State)"
        Write-Output "    Binary Path  : $($_.PathName)"
    }
}

# ====================================================================
# MAIN MENU
# ====================================================================

while ($true) {
    Write-Output "`n========================================================"
    Write-Output "    CCDC SERVICE ACCOUNT & DEPENDENCY DISCOVERY MENU    "
    Write-Output "========================================================"
    Write-Output "[1] Map All Service Accounts Across Domain & Local Host"
    Write-Output "[2] Search Specific Account or Keyword (e.g. Keycloak/SQL)"
    Write-Output "[Q] Quit"
    Write-Output "--------------------------------------------------------"

    $choice = Read-Host "Select an option [1, 2, Q]"

    switch ($choice.ToUpper()) {
        "1" { Show-AllServiceAccounts }
        "2" { Search-Account }
        "Q" { Write-Output "Exiting dependency engine."; return }
        Default { Write-Output "[!] Invalid choice. Please select 1, 2, or Q." }
    }
}
