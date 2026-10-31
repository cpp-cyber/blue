<#
.SYNOPSIS
    CCDC Universal Inventory & Baseline Engine (v11 - One User Per Line)
.DESCRIPTION
    Zero PS5+ dependencies. Compatible across Windows Server 2012 to 2025.
#>

# ====================================================================
# HELPER FUNCTIONS
# ====================================================================

function Show-SystemNetworkConfig {
    Write-Output "`n================================================================="
    Write-Output "               SYSTEM & NETWORK INTERFACE BASELINE               "
    Write-Output "================================================================="
    
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    
    Write-Output "`n[+] HOST CONFIGURATION"
    Write-Output ("Hostname        : {0}" -f $env:COMPUTERNAME)
    Write-Output ("Domain / Workgr : {0}" -f $cs.Domain)
    Write-Output ("OS Caption      : {0}" -f $os.Caption)
    Write-Output ("Version / Build : {0} (Build {1})" -f $os.Version, $os.BuildNumber)
    Write-Output ("Architecture    : {0}" -f $os.OSArchitecture)
    Write-Output ("Last Boot Time  : {0}" -f $os.LastBootUpTime)

    Write-Output "`n[+] NETWORK INTERFACES"
    $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue
    foreach ($nic in $adapters) {
        Write-Output "---------------------------------------------------------"
        Write-Output ("Adapter         : {0}" -f $nic.Description)
        Write-Output ("MAC Address     : {0}" -f $nic.MACAddress)
        Write-Output ("IPv4 Address    : {0}" -f ($nic.IPAddress -join ', '))
        Write-Output ("Subnet Mask     : {0}" -f ($nic.IPSubnet -join ', '))
        Write-Output ("Default Gateway : {0}" -f ($nic.DefaultIPGateway -join ', '))
        Write-Output ("DNS Servers     : {0}" -f ($nic.DNSServerSearchOrder -join ', '))
    }
}

function Show-UsersAndGroups {
    Write-Output "`n================================================================="
    Write-Output "               USERS AND PRIVILEGED GROUPS                       "
    Write-Output "================================================================="

    Write-Output "`n[+] LOCAL ACCOUNTS (MEMBER SERVERS / STANDALONE)"
    $localUsers = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction SilentlyContinue
    if ($localUsers) {
        Write-Output "[*] Local Accounts List (One Per Line):"
        foreach ($user in ($localUsers | Sort-Object Name)) {
            Write-Output $user.Name
        }
    } else {
        Write-Output "No local SAM accounts found (Standard behavior for Domain Controllers)."
    }

    Write-Output "`n[+] LOCAL / BUILTIN ADMINISTRATORS"
    try {
        $adminGroup = Get-CimInstance Win32_Group -Filter "LocalAccount=True AND SID='S-1-5-32-544'" -ErrorAction Stop
        $admins = Get-CimInstance -Query "ASSOCIATORS OF {Win32_Group.Domain='$($env:COMPUTERNAME)',Name='$($adminGroup.Name)'} WHERE ResultClass=Win32_UserAccount"
        foreach ($admin in $admins.Name) {
            Write-Output ("  - " + $admin)
        }
    } catch {
        $netAdmin = (net localgroup administrators | Select-Object -Skip 6) -notmatch "The command completed" | Where-Object { $_ -ne "" }
        foreach ($admin in $netAdmin) {
            Write-Output ("  - " + $admin.Trim())
        }
    }

    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        Write-Output "`n[+] ACTIVE DIRECTORY PRIVILEGED GROUPS"
        Write-Output "Domain Admins:"
        try {
            $da = Get-ADGroupMember -Identity "Domain Admins" -Recursive -ErrorAction Stop | Select-Object -ExpandProperty SamAccountName
            foreach ($u in $da) { Write-Output ("  - " + $u) }
        } catch {
            $netDA = (net group "Domain Admins" /domain 2>$null | Select-Object -Skip 6) -notmatch "The command completed" | Where-Object { $_ -ne "" }
            foreach ($u in $netDA) { Write-Output ("  - " + $u.Trim()) }
        }

        Write-Output "Enterprise Admins:"
        try {
            $ea = Get-ADGroupMember -Identity "Enterprise Admins" -Recursive -ErrorAction Stop | Select-Object -ExpandProperty SamAccountName
            foreach ($u in $ea) { Write-Output ("  - " + $u) }
        } catch {
            $netEA = (net group "Enterprise Admins" /domain 2>$null | Select-Object -Skip 6) -notmatch "The command completed" | Where-Object { $_ -ne "" }
            foreach ($u in $netEA) { Write-Output ("  - " + $u.Trim()) }
        }

        Write-Output "`n[+] ALL DOMAIN USERS (RECURSIVE SEARCH ACROSS ALL OUs)"
        $userObjects = @()

        # Method 1: ActiveDirectory module
        if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
            $userObjects = Get-ADUser -Filter * -Properties DistinguishedName, Enabled -ErrorAction SilentlyContinue | ForEach-Object {
                $ouPath = ($_.DistinguishedName -split ',', 2)[1]
                New-Object PSObject -Property @{
                    SamAccountName = $_.SamAccountName
                    Name           = $_.Name
                    Enabled        = $_.Enabled
                    OU             = $ouPath
                }
            }
        }
        
        # Method 2: ADSI Fallback (PowerShell 4.0 / 3.0 Compatible)
        if (-not $userObjects -or $userObjects.Count -eq 0) {
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
                    $dn = [string]$r.Properties["distinguishedname"]
                    $ouPath = ($dn -split ',', 2)[1]
                    $userAccountControl = [int]$r.Properties["useraccountcontrol"][0]
                    $isEnabled = (-not ($userAccountControl -band 2))
                    
                    $userObjects += New-Object PSObject -Property @{
                        SamAccountName = [string]$r.Properties["samaccountname"]
                        Name           = [string]$r.Properties["name"]
                        Enabled        = $isEnabled
                        OU             = $ouPath
                    }
                }
            } catch {}
        }

        if ($userObjects.Count -gt 0) {
            Write-Output "`n--- DOMAIN USERS LIST (ONE PER LINE) ---"
            foreach ($name in ($userObjects | Select-Object -ExpandProperty SamAccountName | Sort-Object)) {
                if ($name.EndsWith("$")) { continue }
                Write-Output $name
            }
            Write-Output "----------------------------------------"

            Write-Output ("`n{0,-25} {1,-8} {2}" -f "USER ACCOUNT", "ENABLED", "ORGANIZATIONAL UNIT / PATH")
            Write-Output ("{0,-25} {1,-8} {2}" -f "============", "=======", "===========================")
            
            foreach ($u in ($userObjects | Sort-Object OU, SamAccountName)) {
                if ($u.SamAccountName.EndsWith("$")) { continue }
                Write-Output ("{0,-25} {1,-8} {2}" -f $u.SamAccountName, $u.Enabled, $u.OU)
            }
        } else {
            Write-Output "Could not query Active Directory user accounts."
        }
    }
}

function Show-CoreServices {
    Write-Output "`n================================================================="
    Write-Output "               CORE AD & INFRASTRUCTURE SERVICES                "
    Write-Output "================================================================="
    Write-Output ("{0,-20} {1,-12} {2,-12} {3}" -f "SERVICE NAME", "STATE", "START MODE", "FRIENDLY NAME")
    Write-Output ("{0,-20} {1,-12} {2,-12} {3}" -f "============", "=====", "==========", "=============")

    $coreTargets = @{
        "NTDS"               = "Active Directory Domain Services"
        "kdc"                = "Kerberos Key Distribution Center"
        "DNS"                = "DNS Server"
        "Netlogon"           = "Netlogon Service"
        "W32Time"            = "Windows Time (NTP)"
        "RpcSs"              = "Remote Procedure Call (RPC)"
        "DFSR"               = "DFS Replication"
        "LanmanServer"       = "Server (SMB Share Host)"
        "LanmanWorkstation"  = "Workstation (SMB Client)"
        "sshd"               = "OpenSSH SSH Server (BACKDOOR AUDIT)"
        "wuauserv"           = "Windows Update Service"
        "CertSvc"            = "Active Directory Certificate Services"
    }

    $startMap = @{
        0 = "Boot"
        1 = "System"
        2 = "Automatic"
        3 = "Manual"
        4 = "Disabled"
    }

    foreach ($svcName in ($coreTargets.Keys | Sort-Object)) {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
        
        if (Test-Path $regPath) {
            $regProps = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
            $friendlyName = $coreTargets[$svcName]
            $startDword = $regProps.Start
            $startMode = if ($startMap.ContainsKey($startDword)) { $startMap[$startDword] } else { "Unknown($startDword)" }

            $scOutput = cmd.exe /c "sc query $svcName" 2>$null | Select-String "STATE"
            $state = "STOPPED"
            if ($scOutput -match "RUNNING") {
                $state = "RUNNING"
            } elseif ($scOutput -match "PAUSED") {
                $state = "PAUSED"
            }

            $alert = ""
            if ($svcName -eq "sshd" -and $state -eq "RUNNING") {
                $alert = " [!] BACKDOOR RISK"
            }

            Write-Output ("{0,-20} {1,-12} {2,-12} {3}{4}" -f $svcName, $state, $startMode, $friendlyName, $alert)
        } else {
            Write-Output ("{0,-20} {1,-12} {2,-12} {3}" -f $svcName, "NOT PRESENT", "N/A", $coreTargets[$svcName])
        }
    }
}

function Show-ThirdPartyServices {
    Write-Output "`n================================================================="
    Write-Output "          THIRD-PARTY / NON-DEFAULT INSTALLED SERVICES           "
    Write-Output "================================================================="
    Write-Output "Identifies non-standard services, Red Team backdoors, and unquoted paths."
    Write-Output ("{0,-22} {1,-10} {2,-10} {3}" -f "SERVICE NAME", "STATE", "STARTMODE", "PATHNAME")
    Write-Output ("{0,-22} {1,-10} {2,-10} {3}" -f "============", "=====", "=========", "========")

    $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    $foundNonDefault = 0

    foreach ($s in $services) {
        $path = $s.PathName
        if ([string]::IsNullOrWhiteSpace($path)) { continue }

        $isWindowsCore = $path -match "^([A-Z]:\\Windows\\(system32|SysWOW64|WinSxS|servicing|ADWS|Microsoft\.NET)\b|system32\\)"

        if (-not $isWindowsCore) {
            $foundNonDefault++

            $isUnquoted = ($path -notmatch '^"') -and ($path -match '\.exe(\s|$)') -and ($path -match ' ')
            $unquotedTag = if ($isUnquoted) { " [!] UNQUOTED PATH VULN" } else { "" }
            
            Write-Output ("{0,-22} {1,-10} {2,-10} {3}{4}" -f $s.Name, $s.State, $s.StartMode, $path, $unquotedTag)
        }
    }

    if ($foundNonDefault -eq 0) {
        Write-Output "No non-default third-party services detected."
    }
}

function Show-InstalledAppsAndFeatures {
    Write-Output "`n================================================================="
    Write-Output "               INSTALLED APPLICATIONS & FEATURES                 "
    Write-Output "================================================================="

    Write-Output "`n[+] INSTALLED WINDOWS FEATURES (ACTIVE)"
    if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
        Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | ForEach-Object {
            Write-Output ("Feature: {0,-32} | {1}" -f $_.Name, $_.DisplayName)
        }
    } else {
        Write-Output "Get-WindowsFeature cmdlet not supported on this operating system."
    }

    Write-Host "`n[+] INSTALLED SOFTWARE (REGISTRY RUNTIME)"
    $regPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $installedApps = Get-ItemProperty $regPaths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
    if ($installedApps) {
        foreach ($app in $installedApps) {
            Write-Output ("App: {0,-40} | Version: {1,-15} | Publisher: {2}" -f $app.DisplayName, $app.DisplayVersion, $app.Publisher)
        }
    } else {
        Write-Output "No third-party MSI/registered application packages found."
    }
}

# ====================================================================
# MAIN INTERACTIVE MENU
# ====================================================================

while ($true) {
    Write-Output "`n========================================================"
    Write-Output "             CCDC SYSTEM AUDIT & INVENTORY MENU         "
    Write-Output "========================================================"
    Write-Output "[1] System & Network Configuration (IP, Gateway, DNS, MAC)"
    Write-Output "[2] Local & Domain Accounts / Privileged Groups / Users List"
    Write-Output "[3] Core Active Directory & Infrastructure Services Status"
    Write-Output "[4] Third-Party & Non-Default Services (Unquoted Paths)"
    Write-Output "[5] Installed Applications & Enabled Windows Features"
    Write-Output "[A] Run FULL Inventory (All Modules - for Copy-Pasting)"
    Write-Output "[Q] Quit"
    Write-Output "--------------------------------------------------------"
    
    $choice = Read-Host "Select an option [1-5, A, Q]"

    switch ($choice.ToUpper()) {
        "1" { Show-SystemNetworkConfig }
        "2" { Show-UsersAndGroups }
        "3" { Show-CoreServices }
        "4" { Show-ThirdPartyServices }
        "5" { Show-InstalledAppsAndFeatures }
        "A" {
            Show-SystemNetworkConfig
            Show-UsersAndGroups
            Show-CoreServices
            Show-ThirdPartyServices
            Show-InstalledAppsAndFeatures
            Write-Output "`n================================================================="
            Write-Output "                   FULL BASELINE COMPLETED                       "
            Write-Output "================================================================="
        }
        "Q" {
            Write-Output "`nExiting CCDC Inventory Tool."
            return
        }
        Default {
            Write-Output "`n[!] Invalid selection. Please enter 1-5, A, or Q."
        }
    }
}
