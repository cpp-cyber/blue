<#
.SYNOPSIS
    CCDC Universal Domain Controller Firewall Engine (v4 - Friendly Service Names)
.DESCRIPTION
    Compatible across Windows Server 2012 through 2025. Pure ASCII.
    - Displays current profile states (Domain, Private, Public)
    - Enforces Default Inbound: BLOCK and Default Outbound: BLOCK
    - Disables all non-essential / pre-existing inbound AND outbound rules (kills C2 beacons)
    - Injects mirrored Inbound (localport) and Outbound (remoteport) Active Directory rules
    - Provides interactive custom rule opener that automatically mirrors outbound
    - Clean tabular output with human-readable SERVICE / ROLE descriptions
    - Full atomic backup and restore via .wfw snapshots
#>

$ErrorActionPreference = "SilentlyContinue"
$BackupDir = "C:\CCDC_Firewall_Backup"
$PreBackupFile = "$BackupDir\PreHardening_Firewall.wfw"
$HardenedBackupFile = "$BackupDir\Hardened_Firewall.wfw"

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

function Get-PortServiceDescription {
    param([string]$Port, [string]$RuleName)
    
    $portMap = @{
        "53"          = "DNS (Domain Name System)"
        "88"          = "Kerberos Authentication"
        "123"         = "Windows Time (NTP)"
        "135"         = "RPC Endpoint Mapper"
        "389"         = "LDAP Directory Service"
        "445"         = "SMB / AD SYSVOL & File Shares"
        "464"         = "Kerberos Password Change (kpasswd)"
        "636"         = "LDAPS (Secure LDAP)"
        "3268"        = "Active Directory Global Catalog"
        "3269"        = "Active Directory Global Catalog SSL"
        "3389"        = "RDP (Remote Desktop Management)"
        "5985"        = "WinRM (PowerShell Remoting HTTP)"
        "5986"        = "WinRM (PowerShell Remoting HTTPS)"
        "49152-65535" = "RPC Dynamic High Ports (AD Replication)"
        "80"          = "HTTP (Web Service)"
        "443"         = "HTTPS (Secure Web Service)"
        "80,443"      = "Web Browsing / GitHub (HTTP & HTTPS)"
        "1433"        = "Microsoft SQL Server"
        "3306"        = "MySQL Database"
    }

    if ($portMap.ContainsKey($Port)) {
        return $portMap[$Port]
    }

    # Extract name from custom rule format (e.g., CCDC_Custom_Keycloak_In -> Keycloak)
    if ($RuleName -match "CCDC_Custom_(.*)_(In|Out)") {
        return "Custom Service (" + $matches[1] + ")"
    }

    return "Custom Port ($Port)"
}

function Show-FirewallProfileStatus {
    Write-Output "`n================================================================="
    Write-Output "               CURRENT FIREWALL PROFILE STATUS                   "
    Write-Output "================================================================="
    
    $profiles = @("domainprofile", "privateprofile", "publicprofile")
    foreach ($p in $profiles) {
        $stateOut = cmd.exe /c "netsh advfirewall show $p state" 2>$null | Select-String "State"
        $policyOut = cmd.exe /c "netsh advfirewall show $p firewallpolicy" 2>$null | Select-String "Firewall Policy"
        
        $pName = $p.ToUpper().Replace("PROFILE", "")
        $state = if ($stateOut -match "ON") { "ON" } else { "OFF" }
        $policy = if ($policyOut) { ($policyOut.ToString() -split '\s+', 3)[-1] } else { "Unknown" }
        
        Write-Output ("Profile: {0,-10} | State: {1,-5} | Policy: {2}" -f $pName, $state, $policy)
    }
}

function Backup-FirewallConfiguration {
    param([string]$FilePath, [string]$Description)
    Write-Output ("[*] Creating " + $Description + " in: " + $FilePath)
    cmd.exe /c "netsh advfirewall export `"$FilePath`"" 2>$null | Out-Null
    if (Test-Path $FilePath) {
        Write-Output ("  [+] Snapshot successfully saved (" + (Get-Item $FilePath).Length + " bytes).")
    } else {
        Write-Output "  [-] Failed to create firewall snapshot."
    }
}

function Restore-FirewallConfiguration {
    param([string]$FilePath, [string]$Description)
    Write-Output "`n================================================================="
    Write-Output ("               RESTORE: " + $Description.ToUpper())
    Write-Output "================================================================="
    
    if (-not (Test-Path $FilePath)) {
        Write-Output ("[-] Backup file not found: " + $FilePath)
        return
    }

    Write-Output ("[*] Importing firewall snapshot from: " + $FilePath)
    cmd.exe /c "netsh advfirewall import `"$FilePath`"" 2>$null | Out-Null
    Write-Output "  [+] Firewall rules and profile states restored successfully."
    Show-FirewallProfileStatus
}

function Add-CustomRule {
    Write-Output "`n================================================================="
    Write-Output "               ADD CUSTOM FIREWALL RULE                          "
    Write-Output "================================================================="
    $rName = Read-Host "Enter rule name (e.g. Keycloak or WebService)"
    if ([string]::IsNullOrWhiteSpace($rName)) {
        Write-Output "[-] Rule name cannot be empty."
        return
    }

    $proto = Read-Host "Enter protocol ([T]CP / [U]DP - Default: TCP)"
    $protocol = if ($proto -match "^[uU]") { "UDP" } else { "TCP" }

    $port = Read-Host "Enter port number(s) (e.g. 80 or 80,443 or 8080-8090)"
    if ([string]::IsNullOrWhiteSpace($port)) {
        Write-Output "[-] Port cannot be empty."
        return
    }

    $mirrorOut = Read-Host "Mirror this rule for Outbound traffic as well? ([Y]es / [N]o - Default: Y)"

    # 1. Add Inbound Rule (localport)
    $inName = "CCDC_Custom_" + $rName + "_In"
    Write-Output ("[*] Creating Inbound Rule: " + $inName + " (" + $protocol + " LocalPort: " + $port + ")...")
    cmd.exe /c "netsh advfirewall firewall add rule name=`"$inName`" dir=in action=allow protocol=$protocol localport=$port enable=yes profile=any" 2>$null | Out-Null
    Write-Output ("  [+] Inbound rule '" + $inName + "' active.")

    # 2. Add Mirrored Outbound Rule (remoteport)
    if ($mirrorOut -ne 'N' -and $mirrorOut -ne 'n') {
        $outName = "CCDC_Custom_" + $rName + "_Out"
        Write-Output ("[*] Creating Mirrored Outbound Rule: " + $outName + " (" + $protocol + " RemotePort: " + $port + ")...")
        cmd.exe /c "netsh advfirewall firewall add rule name=`"$outName`" dir=out action=allow protocol=$protocol remoteport=$port enable=yes profile=any" 2>$null | Out-Null
        Write-Output ("  [+] Mirrored outbound rule '" + $outName + "' active.")
    }
}

function Invoke-HardeningSequence {
    Show-FirewallProfileStatus

    # 1. Pre-Hardening Snapshot
    Backup-FirewallConfiguration -FilePath $PreBackupFile -Description "Pre-Hardening Baseline"

    # 2. Remote Access Safeguard Check
    Write-Output "`n[*] REMOTE ACCESS SAFEGUARD:"
    Write-Output "[!] If managing this server over RDP (3389) or WinRM (5985),"
    Write-Output "    disabling existing rules could terminate your active session."
    $allowRDP = Read-Host "Allow RDP (TCP 3389)? ([Y]es / [N]o - Default: Y)"
    $allowWinRM = Read-Host "Allow WinRM (TCP 5985)? ([Y]es / [N]o - Default: N)"

    Write-Output "`n[*] [1/6] Enabling Firewall on all profiles (Domain, Private, Public)..."
    cmd.exe /c "netsh advfirewall set allprofiles state on" 2>$null | Out-Null

    Write-Output "[*] [2/6] Enforcing Strict Default Policies: Inbound = BLOCK, Outbound = BLOCK..."
    cmd.exe /c "netsh advfirewall set allprofiles firewallpolicy blockinbound,blockoutbound" 2>$null | Out-Null

    Write-Output "[*] [3/6] Disabling all pre-existing Inbound and Outbound rules..."
    cmd.exe /c "netsh advfirewall firewall set rule name=all dir=in new enable=no" 2>$null | Out-Null
    cmd.exe /c "netsh advfirewall firewall set rule name=all dir=out new enable=no" 2>$null | Out-Null
    Write-Output "  [+] All pre-existing inbound and outbound rules disabled."

    Write-Output "[*] [4/6] Injecting Core Active Directory Inbound Rules (localport)..."

    $adRules = @(
        @{ Name = "CCDC_AD_DNS_UDP"; Proto = "UDP"; Port = "53" },
        @{ Name = "CCDC_AD_DNS_TCP"; Proto = "TCP"; Port = "53" },
        @{ Name = "CCDC_AD_Kerberos_UDP"; Proto = "UDP"; Port = "88" },
        @{ Name = "CCDC_AD_Kerberos_TCP"; Proto = "TCP"; Port = "88" },
        @{ Name = "CCDC_AD_Kerberos_kpasswd_UDP"; Proto = "UDP"; Port = "464" },
        @{ Name = "CCDC_AD_Kerberos_kpasswd_TCP"; Proto = "TCP"; Port = "464" },
        @{ Name = "CCDC_AD_LDAP_TCP"; Proto = "TCP"; Port = "389" },
        @{ Name = "CCDC_AD_LDAP_UDP"; Proto = "UDP"; Port = "389" },
        @{ Name = "CCDC_AD_LDAPS_TCP"; Proto = "TCP"; Port = "636" },
        @{ Name = "CCDC_AD_GlobalCatalog_TCP"; Proto = "TCP"; Port = "3268" },
        @{ Name = "CCDC_AD_GlobalCatalog_SSL_TCP"; Proto = "TCP"; Port = "3269" },
        @{ Name = "CCDC_AD_SMB_TCP"; Proto = "TCP"; Port = "445" },
        @{ Name = "CCDC_AD_RPC_EndpointMapper_TCP"; Proto = "TCP"; Port = "135" },
        @{ Name = "CCDC_AD_RPC_DynamicHighPorts_TCP"; Proto = "TCP"; Port = "49152-65535" },
        @{ Name = "CCDC_AD_W32Time_NTP_UDP"; Proto = "UDP"; Port = "123" }
    )

    foreach ($r in $adRules) {
        $inName = $r.Name + "_In"
        $desc = Get-PortServiceDescription -Port $r.Port -RuleName $inName
        cmd.exe /c "netsh advfirewall firewall delete rule name=`"$inName`"" 2>$null | Out-Null
        cmd.exe /c "netsh advfirewall firewall add rule name=`"$inName`" dir=in action=allow protocol=$($r.Proto) localport=$($r.Port) enable=yes profile=any" 2>$null | Out-Null
        Write-Output ("  [+] Inbound Allowed  : " + $inName.PadRight(35) + " (" + $r.Proto + " Port: " + $r.Port + " - " + $desc + ")")
    }

    Write-Output "`n[*] [5/6] Injecting Mirrored Outbound Rules (remoteport) for AD Operation..."
    foreach ($r in $adRules) {
        $outName = $r.Name + "_Out"
        $desc = Get-PortServiceDescription -Port $r.Port -RuleName $outName
        cmd.exe /c "netsh advfirewall firewall delete rule name=`"$outName`"" 2>$null | Out-Null
        cmd.exe /c "netsh advfirewall firewall add rule name=`"$outName`" dir=out action=allow protocol=$($r.Proto) remoteport=$($r.Port) enable=yes profile=any" 2>$null | Out-Null
        Write-Output ("  [+] Outbound Allowed : " + $outName.PadRight(35) + " (" + $r.Proto + " Port: " + $r.Port + " - " + $desc + ")")
    }

    if ($allowRDP -ne 'N' -and $allowRDP -ne 'n') {
        cmd.exe /c "netsh advfirewall firewall add rule name=`"CCDC_Mgmt_RDP_In`" dir=in action=allow protocol=TCP localport=3389 enable=yes profile=any" 2>$null | Out-Null
        cmd.exe /c "netsh advfirewall firewall add rule name=`"CCDC_Mgmt_RDP_Out`" dir=out action=allow protocol=TCP remoteport=3389 enable=yes profile=any" 2>$null | Out-Null
        Write-Output "  [+] Management Allowed : CCDC_Mgmt_RDP (In & Out TCP 3389 - Remote Desktop)"
    }
    if ($allowWinRM -eq 'Y' -or $allowWinRM -eq 'y') {
        cmd.exe /c "netsh advfirewall firewall add rule name=`"CCDC_Mgmt_WinRM_In`" dir=in action=allow protocol=TCP localport=5985 enable=yes profile=any" 2>$null | Out-Null
        cmd.exe /c "netsh advfirewall firewall add rule name=`"CCDC_Mgmt_WinRM_Out`" dir=out action=allow protocol=TCP remoteport=5985 enable=yes profile=any" 2>$null | Out-Null
        Write-Output "  [+] Management Allowed : CCDC_Mgmt_WinRM (In & Out TCP 5985 - WinRM Remoting)"
    }

    Write-Output "`n[*] [6/6] Creating Hardened Baseline Backup..."
    Backup-FirewallConfiguration -FilePath $HardenedBackupFile -Description "Hardened CCDC Baseline (Inbound/Outbound Strict)"

    Write-Output "`n================================================================="
    Write-Output "            FIREWALL HARDENING SEQUENCE COMPLETED                "
    Write-Output "================================================================="
    Show-FirewallProfileStatus
    Write-Output "[+] Pre-Hardening backup    : $PreBackupFile"
    Write-Output "[+] Hardened baseline backup: $HardenedBackupFile"
}

function Show-ActiveRules {
    Write-Output "`n========================================================================================================================"
    Write-Output "                                           ACTIVE CCDC FIREWALL ALLOW RULES                                             "
    Write-Output "========================================================================================================================"

    $rules = @()

    # Method 1: PowerShell NetSecurity Module
    if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
        $netRules = Get-NetFirewallRule -DisplayName "CCDC_*" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq 'True' }
        foreach ($nr in $netRules) {
            $pf = $nr | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            $dir = $nr.Direction.ToString().ToUpper()
            $proto = if ($pf.Protocol) { $pf.Protocol.ToString().ToUpper() } else { "ANY" }
            $port = if ($dir -eq "INBOUND") { $pf.LocalPort } else { $pf.RemotePort }
            if ([string]::IsNullOrWhiteSpace($port)) { $port = "Any" }

            $rules += New-Object PSObject -Property @{
                Name        = $nr.DisplayName
                Direction   = $dir
                Protocol    = $proto
                Port        = $port
                Description = (Get-PortServiceDescription -Port $port -RuleName $nr.DisplayName)
            }
        }
    }

    # Method 2: Block Parser Fallback for Netsh
    if ($rules.Count -eq 0) {
        $rawOutput = cmd.exe /c "netsh advfirewall firewall show rule name=all" 2>$null
        $cur = $null

        foreach ($line in $rawOutput) {
            $t = $line.Trim()
            if ($t -match "^Rule Name:\s*(CCDC_.*)") {
                if ($cur -and $cur.Enabled -eq "Yes") { 
                    $rules += New-Object PSObject -Property $cur 
                }
                $cur = @{ Name = $matches[1]; Enabled = ""; Direction = ""; Protocol = ""; Port = ""; Description = "" }
            } elseif ($cur) {
                if ($t -match "^Rule Name:") {
                    if ($cur.Enabled -eq "Yes") { $rules += New-Object PSObject -Property $cur }
                    $cur = $null
                } elseif ($t -match "^Enabled:\s*(.+)") {
                    $cur.Enabled = $matches[1]
                } elseif ($t -match "^Direction:\s*(.+)") {
                    $cur.Direction = if ($matches[1] -match "In") { "INBOUND" } else { "OUTBOUND" }
                } elseif ($t -match "^Protocol:\s*(.+)") {
                    $cur.Protocol = $matches[1].ToUpper()
                } elseif ($t -match "^LocalPort:\s*(.+)" -and $cur.Direction -eq "INBOUND") {
                    $cur.Port = $matches[1]
                    $cur.Description = Get-PortServiceDescription -Port $matches[1] -RuleName $cur.Name
                } elseif ($t -match "^RemotePort:\s*(.+)" -and $cur.Direction -eq "OUTBOUND") {
                    $cur.Port = $matches[1]
                    $cur.Description = Get-PortServiceDescription -Port $matches[1] -RuleName $cur.Name
                }
            }
        }
        if ($cur -and $cur.Enabled -eq "Yes") { 
            $rules += New-Object PSObject -Property $cur 
        }
    }

    # Table 1: Inbound Rules
    Write-Output "`n[+] INBOUND ALLOWED RULES (LOCAL PORTS LISTENING)"
    Write-Output ("{0,-6} {1,-14} {2,-38} {3}" -f "PROTO", "PORT", "SERVICE / ROLE", "RULE NAME")
    Write-Output ("{0,-6} {1,-14} {2,-38} {3}" -f "-----", "----", "--------------", "---------")
    $inRules = $rules | Where-Object { $_.Direction -eq "INBOUND" } | Sort-Object Protocol, Port
    if ($inRules) {
        foreach ($r in $inRules) {
            Write-Output ("{0,-6} {1,-14} {2,-38} {3}" -f $r.Protocol, $r.Port, $r.Description, $r.Name)
        }
    } else {
        Write-Output "No active CCDC inbound allow rules."
    }

    # Table 2: Outbound Rules
    Write-Output "`n[+] OUTBOUND ALLOWED RULES (REMOTE DESTINATION PORTS)"
    Write-Output ("{0,-6} {1,-14} {2,-38} {3}" -f "PROTO", "PORT", "SERVICE / ROLE", "RULE NAME")
    Write-Output ("{0,-6} {1,-14} {2,-38} {3}" -f "-----", "----", "--------------", "---------")
    $outRules = $rules | Where-Object { $_.Direction -eq "OUTBOUND" } | Sort-Object Protocol, Port
    if ($outRules) {
        foreach ($r in $outRules) {
            Write-Output ("{0,-6} {1,-14} {2,-38} {3}" -f $r.Protocol, $r.Port, $r.Description, $r.Name)
        }
    } else {
        Write-Output "No active CCDC outbound allow rules."
    }
    Write-Output "`n========================================================================================================================"
}

# ====================================================================
# MAIN MENU
# ====================================================================

while ($true) {
    Write-Output "`n========================================================"
    Write-Output "    CCDC DOMAIN CONTROLLER FIREWALL ENGINE (STRICT)     "
    Write-Output "========================================================"
    Write-Output "[1] Enforce Inbound BLOCK / Outbound BLOCK + Mirrored AD Rules"
    Write-Output "[2] Add Custom Rule (Opens Inbound & Auto-Mirrors Outbound)"
    Write-Output "[3] Restore Pre-Hardening Backup (Rollback Original)"
    Write-Output "[4] Restore Hardened CCDC Baseline (Recover from Wipe)"
    Write-Output "[5] View Current Firewall Status & Active CCDC Rules"
    Write-Output "[Q] Quit"
    Write-Output "--------------------------------------------------------"

    $choice = Read-Host "Select an option [1-5, Q]"

    switch ($choice.ToUpper()) {
        "1" { Invoke-HardeningSequence }
        "2" { Add-CustomRule }
        "3" { Restore-FirewallConfiguration -FilePath $PreBackupFile -Description "Pre-Hardening Configuration" }
        "4" { Restore-FirewallConfiguration -FilePath $HardenedBackupFile -Description "Hardened CCDC Baseline" }
        "5" { 
            Show-FirewallProfileStatus 
            Show-ActiveRules
        }
        "Q" { Write-Output "Exiting firewall engine."; return }
        Default { Write-Output "[!] Invalid choice. Please enter 1-5, or Q." }
    }
}
