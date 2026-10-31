<#
.SYNOPSIS
    CCDC Automated Sysinternals Threat Hunting Engine
.DESCRIPTION
    Automates execution of Sysinternals tools in C:\CCDC\Tools.
    Zero manual flag typing required. Pure ASCII.
    Compatible across Windows Server 2012 through 2025.
#>

$ErrorActionPreference = "SilentlyContinue"
$toolsDir = "C:\CCDC\Tools"

# Verify tool suite exists
if (-not (Test-Path "$toolsDir\autorunsc.exe")) {
    Write-Output "[-] Sysinternals tools not found in $toolsDir."
    Write-Output "[*] Please run get-tools.ps1 first to download the tool suite."
    return
}

# Auto-accept EULA via registry
foreach ($k in @("HKCU:\Software\Sysinternals", "HKLM:\SOFTWARE\Sysinternals")) {
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name "EulaAccepted" -Value 1 -Type DWord -Force | Out-Null
}

function Hunt-Persistence {
    Write-Output "`n================================================================="
    Write-Output "       HUNTING PERSISTENCE (AUTORUNS - NON-MICROSOFT / UNSIGNED)  "
    Write-Output "================================================================="
    Write-Output "[*] Executing: autorunsc.exe -a * -m -s"
    Write-Output "[*] (Filtering out genuine Microsoft-signed entries...)"
    
    & "$toolsDir\autorunsc.exe" -accepteula -a * -m -s
}

function Hunt-UnsignedBinaries {
    Write-Output "`n================================================================="
    Write-Output "       HUNTING UNSIGNED BINARIES (SIGCHECK)                      "
    Write-Output "================================================================="
    $targetDir = Read-Host "Enter directory to scan (Press ENTER for C:\Windows\System32)"
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = "C:\Windows\System32" }

    if (-not (Test-Path $targetDir)) {
        Write-Output "[-] Directory not found: $targetDir"
        return
    }

    Write-Output "[*] Scanning $targetDir for UNSIGNED executable files..."
    Write-Output "[*] Executing: sigcheck.exe -u -e $targetDir"
    
    & "$toolsDir\sigcheck.exe" -accepteula -u -e $targetDir
}

function Hunt-NamedPipes {
    Write-Output "`n================================================================="
    Write-Output "       HUNTING C2 / COBALT STRIKE NAMED PIPES (PIPELIST)         "
    Write-Output "================================================================="
    Write-Output "[*] Scanning for default C2 Named Pipe patterns..."
    
    $pipeOutput = & "$toolsDir\pipelist.exe" -accepteula
    $c2Matches = $pipeOutput | Select-String -Pattern "msagent|status_|postex|mojo|cobalt|spoolss|psexec|netmon"

    if ($c2Matches) {
        Write-Output "[!] SUSPICIOUS NAMED PIPES DETECTED:"
        foreach ($m in $c2Matches) {
            Write-Output ("    -> " + $m.Line.Trim())
        }
    } else {
        Write-Output "[+] No known default C2 named pipe signatures detected."
    }

    Write-Output "`n--- FULL NAMED PIPE INVENTORY ---"
    $pipeOutput | ForEach-Object { Write-Output $_ }
}

function Hunt-BinaryStrings {
    Write-Output "`n================================================================="
    Write-Output "       EXTRACTING C2 STRINGS, IPs, & URLs (STRINGS)              "
    Write-Output "================================================================="
    $targetFile = Read-Host "Enter full path to suspicious executable"

    if (-not (Test-Path $targetFile)) {
        Write-Output "[-] File not found: $targetFile"
        return
    }

    Write-Output "[*] Extracting readable strings with minimum 8 characters..."
    $stringsOutput = & "$toolsDir\strings.exe" -accepteula -n 8 $targetFile

    Write-Output "`n[+] HIGH-RISK IOC EXTRACTION (IPs, URLs, Shell Commands):"
    $iocMatches = $stringsOutput | Select-String -Pattern "http|://|\.com|\.org|\.net|\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|cmd\.exe|powershell"
    
    if ($iocMatches) {
        foreach ($ioc in $iocMatches) {
            Write-Output ("    -> " + $ioc.Line.Trim())
        }
    } else {
        Write-Output "[-] No obvious IP or URL patterns found in binary."
    }
}

function Hunt-LockedFiles {
    Write-Output "`n================================================================="
    Write-Output "       FINDING PROCESSES LOCKING A FILE / FOLDER (HANDLE)        "
    Write-Output "================================================================="
    $targetName = Read-Host "Enter name of file, folder, or extension to search (e.g. VulnApp)"

    if ([string]::IsNullOrWhiteSpace($targetName)) {
        Write-Output "[-] Search target cannot be empty."
        return
    }

    Write-Output "[*] Searching open handles for: $targetName..."
    & "$toolsDir\handle.exe" -accepteula $targetName
}

function Launch-GUIDashboards {
    Write-Output "`n[*] Spawning Process Explorer (procexp.exe)..."
    Start-Process -FilePath "$toolsDir\procexp.exe"

    Write-Output "[*] Spawning TCPView (tcpview.exe)..."
    Start-Process -FilePath "$toolsDir\tcpview.exe"
    
    Write-Output "[+] Dashboards running. Monitor live processes and network beacons."
}

function Run-AutomatedTriage {
    $reportFile = "C:\CCDC\TriageReport_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt"
    Write-Output "`n[*] Executing Automated Rapid Triage pass..."
    Write-Output "[*] Output will be saved to: $reportFile"

    $report = New-Object System.Text.StringBuilder

    [void]$report.AppendLine("=================================================================")
    [void]$report.AppendLine("                   CCDC RAPID TRIAGE REPORT                      ")
    [void]$report.AppendLine("=================================================================")
    [void]$report.AppendLine("Hostname  : $env:COMPUTERNAME")
    [void]$report.AppendLine("Timestamp : $(Get-Date)")
    [void]$report.AppendLine("")

    [void]$report.AppendLine("--- 1. NON-MICROSOFT AUTOSTARTS (AUTORUNS) ---")
    $ar = & "$toolsDir\autorunsc.exe" -accepteula -a * -m -s
    foreach ($line in $ar) { [void]$report.AppendLine($line) }

    [void]$report.AppendLine("`n--- 2. SUSPICIOUS C2 NAMED PIPES ---")
    $pipes = & "$toolsDir\pipelist.exe" -accepteula
    $c2Pipes = $pipes | Select-String -Pattern "msagent|status_|postex|mojo|cobalt"
    if ($c2Pipes) {
        foreach ($p in $c2Pipes) { [void]$report.AppendLine($p.Line) }
    } else {
        [void]$report.AppendLine("None detected.")
    }

    [void]$report.AppendLine("`n--- 3. UNSIGNED EXECUTABLES IN SYSTEM32 ---")
    $unsigned = & "$toolsDir\sigcheck.exe" -accepteula -u -e C:\Windows\System32
    foreach ($u in $unsigned) { [void]$report.AppendLine($u) }

    $report.ToString() | Out-File -FilePath $reportFile -Encoding ASCII
    Write-Output $report.ToString()

    Write-Output "`n================================================================="
    Write-Output "[+] Rapid triage complete. Report saved to: $reportFile"
    Write-Output "================================================================="
}

# ====================================================================
# MAIN INTERACTIVE MENU
# ====================================================================

while ($true) {
    Write-Output "`n========================================================"
    Write-Output "       CCDC SYSINTERNALS THREAT HUNTING ENGINE          "
    Write-Output "========================================================"
    Write-Output "[1] Hunt Persistence (Autoruns - Non-Microsoft & Unsigned)"
    Write-Output "[2] Hunt Unsigned Binaries (Sigcheck - System32 / Temp)"
    Write-Output "[3] Hunt C2 Named Pipes (PipeList - Cobalt Strike / Beacons)"
    Write-Output "[4] Extract Strings & C2 IPs from File (Strings)"
    Write-Output "[5] Find Process Locking File or Folder (Handle)"
    Write-Output "[6] Launch GUI Dashboards (Process Explorer & TCPView)"
    Write-Output "[A] Run Automated Rapid Triage (All Scans -> File & Screen)"
    Write-Output "[Q] Quit"
    Write-Output "--------------------------------------------------------"

    $choice = Read-Host "Select a threat-hunting action [1-6, A, Q]"

    switch ($choice.ToUpper()) {
        "1" { Hunt-Persistence }
        "2" { Hunt-UnsignedBinaries }
        "3" { Hunt-NamedPipes }
        "4" { Hunt-BinaryStrings }
        "5" { Hunt-LockedFiles }
        "6" { Launch-GUIDashboards }
        "A" { Run-AutomatedTriage }
        "Q" { Write-Output "Exiting threat hunting engine."; return }
        Default { Write-Output "[!] Invalid choice. Please select 1-6, A, or Q." }
    }
}
