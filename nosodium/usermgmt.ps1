<#
.SYNOPSIS
    CCDC Active Directory User Management & Privileged Role Hardening Engine (v2)
.DESCRIPTION
    Compatible across Windows Server 2012 through 2025. Pure ASCII.
    - Snapshot backup of all users and group memberships
    - Audits and strips excessive administrative privileges (EA, SA, Operators, DnsAdmins)
    - Disables default/insecure accounts (Guest, DefaultAccount)
    - Option 4: Interactively cycles through all enabled accounts to disable unscored users
    - 1-Click Rollback restoration from snapshot
#>

$ErrorActionPreference = "SilentlyContinue"
$BackupDir = "C:\CCDC_User_Backup\Latest"
$SnapshotFile = "$BackupDir\UserState.xml"

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# ====================================================================
# BACKUP & ROLLBACK ENGINE
# ====================================================================

function Backup-UserState {
    Write-Output "`n[*] Generating User & Group Membership Snapshot in: $SnapshotFile"
    
    $users = Get-ADUser -Filter * -Properties MemberOf, Enabled, Description, ServicePrincipalNames -ErrorAction SilentlyContinue
    
    if (-not $users) {
        Write-Output "[-] Failed to enumerate Active Directory users. Ensure ActiveDirectory module is functional."
        return $false
    }

    $snapshotData = @()
    foreach ($u in $users) {
        $snapshotData += New-Object PSObject -Property @{
            SamAccountName = $u.SamAccountName
            DistinguishedName = $u.DistinguishedName
            Enabled = $u.Enabled
            MemberOf = @($u.MemberOf)
            Description = $u.Description
        }
    }

    $snapshotData | Export-Clixml -Path $SnapshotFile
    Write-Output ("  [+] Successfully snapshotted " + $snapshotData.Count + " user accounts to: " + $SnapshotFile)
    return $true
}

function Restore-UserState {
    Write-Output "`n================================================================="
    Write-Output "           RESTORING USERS & GROUP MEMBERSHIPS FROM BACKUP       "
    Write-Output "================================================================="

    if (-not (Test-Path $SnapshotFile)) {
        Write-Output "[-] Snapshot file not found at: $SnapshotFile"
        return
    }

    $snapshotData = Import-Clixml -Path $SnapshotFile
    Write-Output ("[*] Restoring state for " + $snapshotData.Count + " user accounts...")

    foreach ($u in $snapshotData) {
        $account = $u.SamAccountName
        
        # 1. Restore Enabled / Disabled status
        try {
            Set-ADUser -Identity $account -Enabled $u.Enabled -ErrorAction SilentlyContinue
            Write-Output ("  [+] Restored status for '{0}' -> Enabled: {1}" -f $account, $u.Enabled)
        } catch {}

        # 2. Restore Group Memberships
        if ($u.MemberOf) {
            foreach ($groupDN in $u.MemberOf) {
                try {
                    Add-ADGroupMember -Identity $groupDN -Members $account -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }

    Write-Output "`n[+] User state and group memberships restored to pre-hardening snapshot."
}

# ====================================================================
# ROLE AUDITING & PRIVILEGE STRIPPING
# ====================================================================

$HighRiskGroups = @(
    "Enterprise Admins",
    "Schema Admins",
    "Account Operators",
    "Backup Operators",
    "Server Operators",
    "DnsAdmins",
    "Print Operators",
    "Domain Admins",
    "Administrators"
)

function Show-PrivilegedRoles {
    Write-Output "`n================================================================="
    Write-Output "               PRIVILEGED AD ROLES & GROUP MEMBERSHIP            "
    Write-Output "================================================================="
    Write-Output ("{0,-22} {1}" -f "ROLE / GROUP NAME", "MEMBERS")
    Write-Output ("{0,-22} {1}" -f "==================", "=======")

    foreach ($grp in $HighRiskGroups) {
        try {
            $members = Get-ADGroupMember -Identity $grp -Recursive -ErrorAction Stop | Select-Object -ExpandProperty SamAccountName
            $memberStr = if ($members) { $members -join ', ' } else { "(Empty)" }
            Write-Output ("{0,-22} {1}" -f $grp, $memberStr)
        } catch {
            Write-Output ("{0,-22} {1}" -f $grp, "(Group Not Present on Domain)")
        }
    }
}

function Invoke-StripExcessiveRoles {
    Write-Output "`n================================================================="
    Write-Output "             STRIP EXCESSIVE ADMINISTRATIVE ROLES                "
    Write-Output "================================================================="
    Write-Output "[*] Auditing dangerous groups (Schema Admins, Enterprise Admins, Operators)..."
    Write-Output "[!] Core built-in 'Administrator' will remain protected in Domain Admins."

    Backup-UserState | Out-Null

    $stripTargets = @(
        "Schema Admins",
        "Enterprise Admins",
        "Account Operators",
        "Backup Operators",
        "Server Operators",
        "DnsAdmins",
        "Print Operators"
    )

    $strippedCount = 0

    foreach ($grp in $stripTargets) {
        try {
            $members = Get-ADGroupMember -Identity $grp -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName
            foreach ($m in $members) {
                if ($grp -eq "Administrators" -and $m -eq "Administrator") { continue }

                Remove-ADGroupMember -Identity $grp -Members $m -Confirm:$false -ErrorAction SilentlyContinue
                Write-Output ("  [!] REMOVED: User '{0}' was stripped from high-risk group '{1}'" -f $m, $grp)
                $strippedCount++
            }
        } catch {}
    }

    try {
        $daMembers = Get-ADGroupMember -Identity "Domain Admins" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SamAccountName
        foreach ($da in $daMembers) {
            if ($da -ne "Administrator") {
                $ans = Read-Host "User '$da' is a Domain Admin. Strip Domain Admin rights from '$da'? ([Y]es / [S]kip)"
                if ($ans -eq 'Y' -or $ans -eq 'y') {
                    Remove-ADGroupMember -Identity "Domain Admins" -Members $da -Confirm:$false -ErrorAction SilentlyContinue
                    Write-Output ("  [!] REMOVED: '$da' stripped from Domain Admins.")
                    $strippedCount++
                }
            }
        }
    } catch {}

    if ($strippedCount -eq 0) {
        Write-Output "`n[+] No excessive administrative privileges detected. Privileged groups are clean."
    } else {
        Write-Output ("`n[+] Stripped {0} dangerous privilege assignments." -f $strippedCount)
    }
}

function Disable-InsecureDefaultAccounts {
    Write-Output "`n[*] Disabling Default Insecure Accounts (Guest, DefaultAccount)..."
    $defaultAccounts = @("Guest", "DefaultAccount", "WDAGUtilityAccount")
    
    foreach ($acc in $defaultAccounts) {
        $u = Get-ADUser -Identity $acc -ErrorAction SilentlyContinue
        if ($u) {
            Set-ADUser -Identity $acc -Enabled $false -CannotChangePassword $true
            $scramble = "CcdcL0ckd0wn_!#" + (Get-Random)
            Set-ADAccountPassword -Identity $acc -NewPassword (ConvertTo-SecureString $scramble -AsPlainText -Force) -Reset
            Write-Output ("  [+] Account '{0}' is DISABLED and password scrambled." -f $acc)
        }
    }
}

# ====================================================================
# INTERACTIVE ACCOUNT LOCKDOWN CYCLE (OPTION 4)
# ====================================================================

function Disable-UnscoredAccounts {
    Write-Output "`n================================================================="
    Write-Output "               DISABLE UNSCORED USER ACCOUNTS                    "
    Write-Output "================================================================="
    Write-Output "[*] Automatically protecting: Administrator, krbtgt, and Exchange mailboxes."
    Write-Output "[1] Interactively cycle through ALL enabled accounts (One-by-One)"
    Write-Output "[2] Enter a single specific username to disable"
    Write-Output "[B] Back to Main Menu"

    $mode = Read-Host "Select lockdown mode [1, 2, B]"

    if ($mode -eq "1") {
        # Query all currently enabled accounts
        $enabledUsers = Get-ADUser -Filter {Enabled -eq $true} -Properties Description | Sort-Object SamAccountName
        
        Write-Output "`n[*] Starting interactive lockdown pass across all enabled accounts..."
        Write-Output "[!] Press 'Y' to Disable (Block Logon), 'S' to Skip (Keep Enabled), 'Q' to Stop.`n"
        
        $disabledCount = 0
        foreach ($u in $enabledUsers) {
            $uName = $u.SamAccountName
            
            # Built-in safeguards
            if ($uName -eq "Administrator" -or $uName -eq "krbtgt" -or $uName.EndsWith("$")) { continue }
            if ($uName -match "^HealthMailbox" -or $uName -match "^SM_") { continue }
            
            $promptText = "Disable account '$uName'"
            if ($u.Description) { $promptText += " (Desc: " + $u.Description + ")" }
            $promptText += "? ([Y]es / [S]kip / [Q]uit)"
            
            $ans = Read-Host $promptText
            
            if ($ans -eq 'Q' -or $ans -eq 'q') {
                Write-Output "[*] Interactive disable cycle stopped by user."
                break
            }
            if ($ans -eq 'Y' -or $ans -eq 'y') {
                try {
                    Set-ADUser -Identity $uName -Enabled $false -ErrorAction Stop
                    Write-Output ("  [+] DISABLED: User '{0}' is now disabled (Logon blocked)." -f $uName)
                    $disabledCount++
                } catch {
                    Write-Output ("  [-] Failed to disable '{0}': {1}" -f $uName, $_.Exception.Message)
                }
            } else {
                Write-Output ("  [-] SKIPPED: User '{0}' remains active." -f $uName)
            }
        }
        Write-Output ("`n[+] Interactive cycle complete. Disabled {0} accounts." -f $disabledCount)

    } elseif ($mode -eq "2") {
        $targetUser = Read-Host "Enter specific username to disable"
        if ([string]::IsNullOrWhiteSpace($targetUser)) { return }

        if ($targetUser -eq "Administrator" -or $targetUser -eq "krbtgt" -or $targetUser -match "^HealthMailbox") {
            Write-Output "[-] Safety block: Refusing to disable critical system account: $targetUser"
            return
        }

        try {
            Set-ADUser -Identity $targetUser -Enabled $false -ErrorAction Stop
            Write-Output ("  [+] User '{0}' is now DISABLED (Logon blocked)." -f $targetUser)
        } catch {
            Write-Output ("  [-] Failed to disable '{0}': {1}" -f $targetUser, $_.Exception.Message)
        }
    }
}

function Add-DomainUser {
    Write-Output "`n================================================================="
    Write-Output "                      ADD NEW DOMAIN USER                        "
    Write-Output "================================================================="
    $uName = Read-Host "Enter new username (sAMAccountName)"
    if ([string]::IsNullOrWhiteSpace($uName)) { return }

    $passPlain = Read-Host "Enter password for $uName (UNMASKED)"
    if ([string]::IsNullOrWhiteSpace($passPlain)) {
        Write-Output "[-] Password cannot be empty."
        return
    }
    $secPass = ConvertTo-SecureString $passPlain -AsPlainText -Force

    $desc = Read-Host "Enter description (Optional - Press ENTER to skip)"

    try {
        New-ADUser -Name $uName -SamAccountName $uName -AccountPassword $secPass -Enabled $true -PasswordNeverExpires $true -Description $desc -ErrorAction Stop
        Write-Output ("  [+] User '{0}' created successfully." -f $uName)

        $addAdmin = Read-Host "Add '$uName' to Domain Admins? ([Y]es / [N]o - Default: N)"
        if ($addAdmin -eq 'Y' -or $addAdmin -eq 'y') {
            Add-ADGroupMember -Identity "Domain Admins" -Members $uName
            Write-Output ("  [!] Added '{0}' to Domain Admins." -f $uName)
        }
    } catch {
        Write-Output ("  [-] Failed to create user: " + $_.Exception.Message)
    }
}

function Remove-DomainUser {
    Write-Output "`n================================================================="
    Write-Output "                    REMOVE / DELETE DOMAIN USER                  "
    Write-Output "================================================================="
    $uName = Read-Host "Enter username to delete"
    if ([string]::IsNullOrWhiteSpace($uName)) { return }

    $protected = @("Administrator", "Guest", "krbtgt", "DefaultAccount")
    if ($protected -contains $uName -or $uName.EndsWith("$") -or $uName -match "^HealthMailbox") {
        Write-Output ("[-] Safety block: Cannot delete protected or system account: " + $uName)
        return
    }

    $confirm = Read-Host "Are you SURE you want to delete '$uName'? This cannot be undone except by restore. ([Y]es / [N]o)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Output "[-] Deletion cancelled."
        return
    }

    try {
        Remove-ADUser -Identity $uName -Confirm:$false -ErrorAction Stop
        Write-Output ("  [+] User '{0}' deleted successfully." -f $uName)
    } catch {
        Write-Output ("  [-] Failed to delete user: " + $_.Exception.Message)
    }
}

# ====================================================================
# MAIN MENU
# ====================================================================

while ($true) {
    Write-Output "`n========================================================"
    Write-Output "       CCDC ACTIVE DIRECTORY USER MANAGEMENT            "
    Write-Output "========================================================"
    Write-Output "[1] Audit Privileged Roles & Group Memberships"
    Write-Output "[2] Strip Excessive Admin Roles (Schema, Enterprise, Operators)"
    Write-Output "[3] Disable Insecure Defaults (Guest, DefaultAccount)"
    Write-Output "[4] Disable Unscored User Accounts (Interactive Cycle)"
    Write-Output "[5] Add New Domain User"
    Write-Output "[6] Remove / Delete Domain User"
    Write-Output "[7] Create Manual User State Snapshot Backup"
    Write-Output "[8] Restore Users & Groups from Snapshot Backup"
    Write-Output "[Q] Quit"
    Write-Output "--------------------------------------------------------"

    $choice = Read-Host "Select an option [1-8, Q]"

    switch ($choice.ToUpper()) {
        "1" { Show-PrivilegedRoles }
        "2" { Invoke-StripExcessiveRoles }
        "3" { Disable-InsecureDefaultAccounts }
        "4" { Disable-UnscoredAccounts }
        "5" { Add-DomainUser }
        "6" { Remove-DomainUser }
        "7" { Backup-UserState }
        "8" { Restore-UserState }
        "Q" { Write-Output "Exiting user management engine."; return }
        Default { Write-Output "[!] Invalid choice. Please select 1-8, or Q." }
    }
}
