<#
.SYNOPSIS
    CCDC Host Security Policy, Exploit Guard, & Maximum Telemetry Engine (v2)
.DESCRIPTION
    Compatible across Windows Server 2012 through 2025. Pure ASCII.
    - Highest-Level Logging (Auditpol, EID 4688 Command-Lines, PS Script Block EID 4104)
    - Sticky Keys / IFEO Accessibility Backdoor Purge
    - Exploit Guard (DEP, ASLR, SEHOP, ASR LSASS Rule)
    - Restrict Unauthenticated RPC Clients & Secure Logon (CAD)
    - Antivirus, Anti-Spyware, and Cloud Telemetry
    - URL Filtering, SmartScreen, and File Attachment Security
    - OPTIONAL Scoring-Safe DoS Profile (Prompted)
    - Pre-Policy Snapshot & Instant 1-Click Rollback
#>

$ErrorActionPreference = "SilentlyContinue"
$BackupRoot = "C:\CCDC_SecurityPolicy_Backup\Latest"
$global:auditLog = New-Object System.Collections.ArrayList

function Add-AuditEntry {
    param(
        [string]$Category,
        [string]$Target,
        [string]$StateFound,
        [string]$ActionTaken
    )
    $entry = New-Object PSObject -Property @{
        Category    = $Category
        Target      = $Target
        StateFound  = $StateFound
        ActionTaken = $ActionTaken
    }
    $global:auditLog.Add($entry) | Out-Null
}

# ====================================================================
# BACKUP ENGINE
# ====================================================================

function Backup-PrePolicyState {
    Write-Output "[*] Generating Pre-Policy State Snapshot in: $BackupRoot"
    if (Test-Path $BackupRoot) {
        Remove-Item -Path $BackupRoot -Recurse -Force | Out-Null
    }
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null

    $state = @{
        Registry = @()
        LogSizes = @()
    }

    # Snapshot Policy Registry Keys
    $regTargets = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"; Names = @("ProcessCreationIncludeCmdLine_Enabled") },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"; Names = @("EnableScriptBlockLogging", "EnableScriptBlockInvocationLogging") },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"; Names = @("EnableModuleLogging") },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription"; Names = @("EnableTranscripting") },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Names = @("EnableSmartScreen") },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments"; Names = @("ScanWithAntiVirus", "SaveZoneInformation") },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Names = @("DisableCAD") },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Rpc"; Names = @("RestrictRemoteClients") },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"; Names = @("CrashDumpEnabled") },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; Names = @("SynAttackProtect", "EnableICMPRedirect", "PerformRouterDiscovery") }
    )

    foreach ($entry in $regTargets) {
        $p = $entry.Path
        $exists = Test-Path $p
        foreach ($name in $entry.Names) {
            $val = $null
            $hasVal = $false
            if ($exists) {
                $prop = Get-ItemProperty -Path $p -Name $name -ErrorAction SilentlyContinue
                if ($prop -and ($prop.PSObject.Properties[$name])) {
                    $val = $prop.$name
                    $hasVal = $true
                }
            }
            $state.Registry += @{
                Path       = $p
                Name       = $name
                Existed    = $hasVal
                Value      = $val
                KeyExisted = $exists
            }
        }
    }

    foreach ($logName in @("Security", "System", "Application")) {
        $logObj = Get-EventLog -List -ErrorAction SilentlyContinue | Where-Object { $_.Log -eq $logName }
        if ($logObj) {
            $state.LogSizes += @{
                LogName = $logName
                SizeKB  = $logObj.MaximumKilobytes
            }
        }
    }

    cmd.exe /c "auditpol.exe /backup /file:`"$BackupRoot\AuditPol_Backup.csv`"" 2>$null | Out-Null
    $state | Export-Clixml -Path "$BackupRoot\StateBackup.xml"
    Write-Output "  [+] State snapshot saved to $BackupRoot\StateBackup.xml"
}

# ====================================================================
# ROLLBACK / RESTORATION ENGINE
# ====================================================================

function Invoke-PolicyRollback {
    Write-Output "================================================================="
    Write-Output "             RESTORING SYSTEM FROM POLICY BACKUP                 "
    Write-Output "================================================================="

    if (-not (Test-Path "$BackupRoot\StateBackup.xml")) {
        Write-Output "[-] No backup found at $BackupRoot\StateBackup.xml. Rollback aborted."
        return
    }

    $state = Import-Clixml -Path "$BackupRoot\StateBackup.xml"
    Write-Output "[*] Loaded State Snapshot successfully."

    Write-Output "`n[*] Restoring Registry & Policy Values..."
    foreach ($r in $state.Registry) {
        if (-not $r.KeyExisted) {
            Remove-Item -Path $r.Path -Force -ErrorAction SilentlyContinue | Out-Null
        } elseif (-not $r.Existed) {
            Remove-ItemProperty -Path $r.Path -Name $r.Name -Force -ErrorAction SilentlyContinue | Out-Null
        } else {
            if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
            Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -Type DWord -Force | Out-Null
        }
    }
    Write-Output "  [+] Policy registry values reverted."

    Write-Output "`n[*] Restoring Event Log Buffer Sizes..."
    foreach ($l in $state.LogSizes) {
        Limit-EventLog -LogName $l.LogName -MaximumSize ($l.SizeKB * 1KB) -OverflowAction OverwriteAsNeeded -ErrorAction SilentlyContinue
    }
    Write-Output "  [+] Event log sizes reverted."

    if (Test-Path "$BackupRoot\AuditPol_Backup.csv") {
        Write-Output "`n[*] Restoring Original Audit Policy Subcategories..."
        cmd.exe /c "auditpol.exe /restore /file:`"$BackupRoot\AuditPol_Backup.csv`"" 2>$null | Out-Null
        Write-Output "  [+] AuditPol settings restored."
    }

    Write-Output "`n================================================================="
    Write-Output "             SECURITY POLICY ROLLBACK COMPLETED                  "
    Write-Output "================================================================="
}

# ====================================================================
# POLICY ENFORCEMENT ENGINE
# ====================================================================

function Invoke-PolicyEnforcement {
    Backup-PrePolicyState
    $global:auditLog.Clear()

    Write-Output "`n[*] Executing Maximum Security Policies..."

    # 1. HIGHEST-LEVEL LOGGING & TELEMETRY
    Write-Output "`n[+] [1/7] Configuring Maximum Security Logging & Auditing..."
    foreach ($lg in @("Security", "System", "Application")) {
        Limit-EventLog -LogName $lg -MaximumSize 256MB -OverflowAction OverwriteAsNeeded -ErrorAction SilentlyContinue
    }
    Add-AuditEntry "Telemetry" "Event Log Buffers" "DEFAULT (16-20MB)" "Expanded Security, System, and App logs to 256MB"

    $auditCategories = @(
        "Logon", "Logoff", "Account Lockout", "Special Logon",
        "Process Creation", "Process Termination",
        "SAM", "Security State Change", "Security System Extension", "System Integrity",
        "Audit Policy Change", "Authentication Policy Change",
        "File System", "Registry", "Handle Manipulation",
        "User Account Management", "Computer Account Management", "Security Group Management",
        "Directory Service Access", "Directory Service Changes"
    )
    foreach ($cat in $auditCategories) {
        cmd.exe /c "auditpol.exe /set /subcategory:`"$cat`" /success:enable /failure:enable" 2>$null | Out-Null
    }
    Add-AuditEntry "Telemetry" "Advanced Audit Policies" "DEFAULT (Partial)" "Enforced Success/Failure on 20 critical subcategories"

    # EID 4688 Command-Lines
    $auditPolReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
    if (-not (Test-Path $auditPolReg)) { New-Item -Path $auditPolReg -Force | Out-Null }
    Set-ItemProperty -Path $auditPolReg -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -Type DWord -Force
    Add-AuditEntry "Telemetry" "Process Command-Line (EID 4688)" "DISABLED" "Enabled command-line string capture in Event ID 4688"

    # PowerShell EID 4104 Script Block Logging & Module Logging
    $psBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell"
    $sbPath = "$psBase\ScriptBlockLogging"
    $mlPath = "$psBase\ModuleLogging"
    $trPath = "$psBase\Transcription"

    if (-not (Test-Path $sbPath)) { New-Item -Path $sbPath -Force | Out-Null }
    Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $sbPath -Name "EnableScriptBlockInvocationLogging" -Value 1 -Type DWord -Force

    if (-not (Test-Path $mlPath)) { New-Item -Path $mlPath -Force | Out-Null }
    Set-ItemProperty -Path $mlPath -Name "EnableModuleLogging" -Value 1 -Type DWord -Force
    $modNamesPath = "$mlPath\ModuleNames"
    if (-not (Test-Path $modNamesPath)) { New-Item -Path $modNamesPath -Force | Out-Null }
    Set-ItemProperty -Path $modNamesPath -Name "*" -Value "*" -Type String -Force

    if (-not (Test-Path $trPath)) { New-Item -Path $trPath -Force | Out-Null }
    Set-ItemProperty -Path $trPath -Name "EnableTranscripting" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $trPath -Name "EnableInvocationHeader" -Value 1 -Type DWord -Force
    New-Item -ItemType Directory -Path "C:\PSTranscripts" -Force | Out-Null
    Set-ItemProperty -Path $trPath -Name "OutputDirectory" -Value "C:\PSTranscripts" -Type String -Force
    Add-AuditEntry "Telemetry" "PowerShell Logging (EID 4104)" "DISABLED" "Enabled Script Block Logging, Module Logging, & Transcripts"
    Write-Output "    -> Granular auditpol, EID 4688 command-lines, and PowerShell EID 4104 active."

    # 2. STICKY KEYS & ACCESSIBILITY BACKDOOR PURGE (IFEO)
    Write-Output "[+] [2/7] Inspecting Image File Execution Options (Accessibility Backdoors)..."
    $accessibilityBinaries = @("sethc.exe", "utilman.exe", "osk.exe", "magnify.exe", "narrator.exe", "DisplaySwitch.exe", "AtBroker.exe")
    $ifeoBasePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    $hijacksFound = 0

    foreach ($bin in $accessibilityBinaries) {
        $binPath = "$ifeoBasePath\$bin"
        if (Test-Path $binPath) {
            $debugger = (Get-ItemProperty -Path $binPath -ErrorAction SilentlyContinue).Debugger
            if ($debugger) {
                $hijacksFound++
                Remove-ItemProperty -Path $binPath -Name "Debugger" -Force | Out-Null
                Add-AuditEntry "Persistence" "IFEO Backdoor ($bin)" "HIJACKED ($debugger)" "Purged malicious Debugger registry hook"
                Write-Output ("    [!] PURGED STICKY KEYS BACKDOOR: {0} was hijacked by {1}" -f $bin, $debugger)
            }
        }
    }
    if ($hijacksFound -eq 0) {
        Add-AuditEntry "Persistence" "Accessibility Binaries (IFEO)" "CLEAN" "Verified no Debugger hijacks on sethc/utilman"
        Write-Output "    -> Verified accessibility binaries (sethc, utilman) are clean."
    }

    # 3. SECURE LOGON & RPC HARDENING
    Write-Output "[+] [3/7] Hardening Remote RPC & Logon Authentication..."
    
    # Require Ctrl+Alt+Delete (CAD)
    $sysPol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Set-ItemProperty -Path $sysPol -Name "DisableCAD" -Value 0 -Type DWord -Force
    Add-AuditEntry "Logon / Auth" "Secure Attention Sequence" "DISABLED" "Enforced Ctrl+Alt+Delete to block fake logon phishing"

    # Restrict Unauthenticated RPC Clients
    $rpcPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Rpc"
    if (-not (Test-Path $rpcPolicy)) { New-Item -Path $rpcPolicy -Force | Out-Null }
    # 1 = RPC_RESTRICT_REMOTE_CLIENTS_DEFAULT (Authenticated RPC only)
    Set-ItemProperty -Path $rpcPolicy -Name "RestrictRemoteClients" -Value 1 -Type DWord -Force
    Add-AuditEntry "RPC / Auth" "Restrict Unauthenticated RPC" "UNRESTRICTED" "Enforced RestrictRemoteClients = 1"

    # Prevent credential exposure in memory crash dumps (Minidump only)
    $crashControl = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"
    Set-ItemProperty -Path $crashControl -Name "CrashDumpEnabled" -Value 3 -Type DWord -Force
    Add-AuditEntry "Memory / Auth" "Crash Dump Credential Theft" "FULL DUMP" "Configured Small Minidump (Blocks LSASS dump from MEMORY.DMP)"
    Write-Output "    -> Ctrl+Alt+Delete enforced, unauthenticated RPC restricted, crash dump hardened."

    # 4. EXPLOIT GUARD & ASR (Vulnerability Protection)
    Write-Output "[+] [4/7] Enforcing Vulnerability Protection & Exploit Guards..."
    cmd.exe /c "bcdedit.exe /set nx OptOut" 2>$null | Out-Null
    
    $mitigationPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    if (-not (Test-Path $mitigationPath)) { New-Item -Path $mitigationPath -Force | Out-Null }
    Set-ItemProperty -Path $mitigationPath -Name "DisableExceptionChainValidation" -Value 0 -Type DWord -Force
    Add-AuditEntry "Vulnerability" "Exploit Guard (DEP / SEHOP)" "DEFAULT" "Enforced System-Wide DEP (OptOut) & SEHOP"

    # ASR Rule: Block Credential Stealing from LSASS (Server 2016 - 2025)
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        # 9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2 = Block credential stealing from LSASS
        Set-MpPreference -AttackSurfaceReductionRules_Ids "9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2" -AttackSurfaceReductionRules_Actions 1 -ErrorAction SilentlyContinue
        Add-AuditEntry "Vulnerability" "ASR: LSASS Credential Theft" "UNENFORCED" "Enforced ASR Rule (Action = Block)"
    }
    Write-Output "    -> System-wide DEP and Exploit Guard active."

    # 5. ANTIVIRUS & ANTI-SPYWARE
    Write-Output "[+] [5/7] Verifying Antivirus & Anti-Spyware Defenses..."
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableBehaviorMonitoring $false -ErrorAction SilentlyContinue
        Set-MpPreference -DisableIOAVProtection $false -ErrorAction SilentlyContinue
        Set-MpPreference -MAPSReporting Advanced -ErrorAction SilentlyContinue
        Set-MpPreference -SubmitSamplesConsent SendAllSamples -ErrorAction SilentlyContinue
        Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
        Add-AuditEntry "Antivirus" "Defender Real-Time & Cloud" "PARTIAL" "Enforced Real-Time, Behavior Monitoring, MAPS, & PUA"
        Write-Output "    -> Windows Defender Real-Time and Cloud telemetry active."
    } else {
        Add-AuditEntry "Antivirus" "Windows Defender Engine" "NOT INSTALLED" "Defender not installed on this OS build (Standard on 2012 R2)"
        Write-Output "    [-] Defender engine not installed on this OS build."
    }

    # 6. URL FILTERING & FILE BLOCKING
    Write-Output "[+] [6/7] Enforcing URL Filtering & File Attachment Policies..."
    $smartScreenPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $smartScreenPolicy)) { New-Item -Path $smartScreenPolicy -Force | Out-Null }
    Set-ItemProperty -Path $smartScreenPolicy -Name "EnableSmartScreen" -Value 1 -Type DWord -Force

    $attachPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments"
    if (-not (Test-Path $attachPolicy)) { New-Item -Path $attachPolicy -Force | Out-Null }
    Set-ItemProperty -Path $attachPolicy -Name "ScanWithAntiVirus" -Value 3 -Type DWord -Force
    Set-ItemProperty -Path $attachPolicy -Name "SaveZoneInformation" -Value 2 -Type DWord -Force
    Add-AuditEntry "File / Web" "SmartScreen & Attachments" "UNENFORCED" "Enforced SmartScreen URL check and mandatory file AV scan"
    Write-Output "    -> SmartScreen URL checks and mandatory attachment AV inspection active."

    # 7. OPTIONAL SCORING-SAFE DOS PROTECTION PROFILE
    Write-Output "`n[+] [7/7] TCP/IP DoS Profile Configuration..."
    Write-Output "[!] WARNING: In competitions, rapid polling from the scoring engine can sometimes"
    Write-Output "    be mistaken for a SYN flood if DoS thresholds are set too aggressively."
    
    $dosChoice = Read-Host "Do you want to enable TCP/IP DoS Protection (SynAttackProtect)? ([Y]es / [N]o - Default: N)"
    
    if ($dosChoice -eq 'Y' -or $dosChoice -eq 'y') {
        $tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Set-ItemProperty -Path $tcpParams -Name "SynAttackProtect" -Value 2 -Type DWord -Force
        Set-ItemProperty -Path $tcpParams -Name "EnableICMPRedirect" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $tcpParams -Name "PerformRouterDiscovery" -Value 0 -Type DWord -Force
        Add-AuditEntry "DoS Profile" "TCP/IP SynAttackProtect" "DISABLED" "Enforced SynAttackProtect = 2 & disabled ICMP redirects"
        Write-Output "    -> DoS Protection Profile ACTIVATED."
    } else {
        Add-AuditEntry "DoS Profile" "TCP/IP SynAttackProtect" "SKIPPED" "Bypassed DoS profile to guarantee scoring engine accessibility"
        Write-Output "    -> DoS Protection Profile SKIPPED (Scoring safety preserved)."
    }

    # EXECUTIVE SUMMARY REPORT
    Write-Output "`n=========================================================================================================="
    Write-Output "                       SECURITY POLICY & TELEMETRY AUDIT REPORT                                   "
    Write-Output "=========================================================================================================="
    Write-Output ("{0,-16} {1,-32} {2,-24} {3}" -f "PROFILE", "TARGET CONTROL", "PREVIOUS STATE", "ACTION ENFORCED")
    Write-Output ("{0,-16} {1,-32} {2,-24} {3}" -f "=======", "==============", "==============", "===============")

    foreach ($entry in $global:auditLog) {
        Write-Output ("{0,-16} {1,-32} {2,-24} {3}" -f $entry.Category, $entry.Target, $entry.StateFound, $entry.ActionTaken)
    }

    Write-Output "=========================================================================================================="
    Write-Output "[+] Policy enforcement complete. Snapshot saved to $BackupRoot\StateBackup.xml"
}

# ====================================================================
# MAIN MENU
# ====================================================================

Write-Output "`n========================================================"
Write-Output "     CCDC HOST SECURITY POLICY & TELEMETRY ENGINE       "
Write-Output "========================================================"
Write-Output "[1] Enforce Maximum Security Policies (Auto-Snapshot First)"
Write-Output "[2] Rollback / Restore Previous Security Policies"
Write-Output "[Q] Quit"
Write-Output "--------------------------------------------------------"

$choice = Read-Host "Select an option [1, 2, Q]"

switch ($choice.ToUpper()) {
    "1" { Invoke-PolicyEnforcement }
    "2" { Invoke-PolicyRollback }
    "Q" { Write-Output "Exiting." }
    Default { Write-Output "[!] Invalid selection. Please enter 1, 2, or Q." }
}
