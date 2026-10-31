<#
.SYNOPSIS
    CCDC Master Blue Team Deployment & Orchestration Engine (v4 - UserMgmt Integrated)
.DESCRIPTION
    Smart local caching. Only downloads on first run or when [R] is pressed.
    Organized strictly by operational priority.
    Creates C:\menu.bat for instant re-opening. Pure ASCII.
#>

$ErrorActionPreference = "SilentlyContinue"

# 1. Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 2. Directories
$ScriptsDir = "C:\CCDC\Scripts"
$BackupDir  = "C:\CCDC\Scripts\Backup"

if (-not (Test-Path $ScriptsDir)) { New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null }
if (-not (Test-Path $BackupDir))  { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

$BaseUrl = "https://raw.githubusercontent.com/cpp-cyber/blue/refs/heads/main/nosodium/"
$ScriptList = @(
    "inv.ps1",
    "deps.ps1",
    "pw.ps1",
    "usermgmt.ps1",
    "fw.ps1",
    "harden.ps1",
    "secpol.ps1",
    "auditpost.ps1",
    "tools.ps1",
    "thrunt.ps1"
)

function Sync-ScriptsFromGitHub {
    Write-Output "`n[*] Synchronizing scripts from GitHub repository..."
    $webClient = New-Object System.Net.WebClient

    # Safely trim trailing slash for clean URL concatenation
    $cleanBase = $BaseUrl.TrimEnd('/')

    foreach ($scriptName in $ScriptList) {
        $sourceUrl = $cleanBase + "/" + $scriptName + "?nocache=" + (Get-Random)
        $destPath  = Join-Path -Path $ScriptsDir -ChildPath $scriptName
        $bakPath   = Join-Path -Path $BackupDir -ChildPath $scriptName

        try {
            Write-Output ("  [>] Fetching: " + $scriptName.PadRight(16) + "...")
            $webClient.DownloadFile($sourceUrl, $destPath)
            
            if (Test-Path $destPath) {
                Copy-Item -Path $destPath -Destination $bakPath -Force | Out-Null
                Write-Output ("      -> [OK] Saved & Backed up.")
            } else {
                Write-Output ("      -> [FAIL] File missing on disk.")
            }
        } catch {
            Write-Output ("      -> [FAIL] " + $_.Exception.Message)
        }
    }

    # Create quick shortcut C:\menu.bat
    "@echo off`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\CCDC\Scripts\setup.ps1`"" | Out-File -FilePath "C:\menu.bat" -Encoding ASCII -Force
    Write-Output "[+] Script synchronization complete. Shortcut created at C:\menu.bat"
}

# 3. Smart Cache Check (Skip downloading if files already exist)
$existingFiles = Get-ChildItem -Path $ScriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue
if (-not $existingFiles -or $existingFiles.Count -lt $ScriptList.Count) {
    Write-Output "[*] First-time setup detected. Downloading all scripts from repository..."
    Sync-ScriptsFromGitHub
} else {
    Write-Output "[+] All scripts already verified in $ScriptsDir."
    Write-Output "[*] Skipping download. Press [R] in the menu if you need to force re-download."
}

# ====================================================================
# PRIORITY EXECUTION MENU
# ====================================================================

while ($true) {
    Write-Output "`n========================================================"
    Write-Output "        CCDC DEFENSIVE OPERATIONS MENU (BY PRIORITY)    "
    Write-Output "========================================================"
    Write-Output "[1]  PRIORITY 1: Inventory & Baseline        (inv.ps1)"
    Write-Output "[2]  PRIORITY 2: Service Accounts & SSO Map  (deps.ps1)"
    Write-Output "[3]  PRIORITY 3: Credential Rotation         (pw.ps1)"
    Write-Output "[4]  PRIORITY 4: User Mgmt & Role Lockdown   (usermgmt.ps1)"
    Write-Output "[5]  PRIORITY 5: Firewall & Port Lockdown    (fw.ps1)"
    Write-Output "[6]  PRIORITY 6: AD & Exploit Hardening      (harden.ps1)"
    Write-Output "[7]  PRIORITY 7: Host Policies & Telemetry   (secpol.ps1)"
    Write-Output "[8]  PRIORITY 8: Post-Hardening Verification (auditpost.ps1)"
    Write-Output "--------------------------------------------------------"
    Write-Output "[9]  UTILITY: Download Sysinternals Suite    (tools.ps1)"
    Write-Output "[10] UTILITY: Threat Hunting Engine          (thrunt.ps1)"
    Write-Output "[R]  RE-SYNC: Force Refresh All Scripts from GitHub"
    Write-Output "[Q]  QUIT"
    Write-Output "--------------------------------------------------------"

    $choice = Read-Host "Select a priority phase to execute [1-10, R, Q]"

    switch ($choice.ToUpper()) {
        "1"  { if (Test-Path "$ScriptsDir\inv.ps1") { & "$ScriptsDir\inv.ps1" } }
        "2"  { if (Test-Path "$ScriptsDir\deps.ps1") { & "$ScriptsDir\deps.ps1" } }
        "3"  { if (Test-Path "$ScriptsDir\pw.ps1") { & "$ScriptsDir\pw.ps1" } }
        "4"  { if (Test-Path "$ScriptsDir\usermgmt.ps1") { & "$ScriptsDir\usermgmt.ps1" } }
        "5"  { if (Test-Path "$ScriptsDir\fw.ps1") { & "$ScriptsDir\fw.ps1" } }
        "6"  { if (Test-Path "$ScriptsDir\harden.ps1") { & "$ScriptsDir\harden.ps1" } }
        "7"  { if (Test-Path "$ScriptsDir\secpol.ps1") { & "$ScriptsDir\secpol.ps1" } }
        "8"  { if (Test-Path "$ScriptsDir\auditpost.ps1") { & "$ScriptsDir\auditpost.ps1" } }
        "9"  { if (Test-Path "$ScriptsDir\tools.ps1") { & "$ScriptsDir\tools.ps1" } }
        "10" { if (Test-Path "$ScriptsDir\thrunt.ps1") { & "$ScriptsDir\thrunt.ps1" } }
        "R"  { Sync-ScriptsFromGitHub }
        "Q"  { Write-Output "Exiting menu. To reopen anytime, run: C:\menu.bat or & C:\CCDC\Scripts\setup.ps1"; return }
        Default { Write-Output "[!] Invalid selection. Please enter 1-10, R, or Q." }
    }
}
