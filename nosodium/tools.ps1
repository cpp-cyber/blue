<#
.SYNOPSIS
    CCDC Sysinternals Blue Team Tool Downloader
.DESCRIPTION
    Barebones tool downloader. Zero external dependencies.
    Compatible across Windows Server 2012, 2012 R2, 2016, 2019, 2022, and 2025.
#>

$ErrorActionPreference = "SilentlyContinue"

# 1. Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 2. Target Directory
$toolsDir = "C:\CCDC\Tools"
if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
}

Write-Output "================================================================="
Write-Output "           DOWNLOADING CCDC BLUE TEAM SYSINTERNALS SUITE         "
Write-Output "================================================================="
Write-Output ("[*] Destination Folder: " + $toolsDir)

# 3. Pre-Accept Sysinternals EULA in Registry (Prevents GUI popup freezes)
$eulaKeys = @(
    "HKCU:\Software\Sysinternals",
    "HKLM:\SOFTWARE\Sysinternals"
)
foreach ($k in $eulaKeys) {
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name "EulaAccepted" -Value 1 -Type DWord -Force | Out-Null
}
Write-Output "[+] Sysinternals EULA pre-accepted in registry."

# 4. Critical Tool List
$tools = @(
    "autoruns.exe",
    "autorunsc.exe",
    "procexp.exe",
    "procmon.exe",
    "tcpview.exe",
    "sigcheck.exe",
    "pipelist.exe",
    "accesschk.exe",
    "handle.exe",
    "logonsessions.exe",
    "strings.exe"
)

$webClient = New-Object System.Net.WebClient

foreach ($tool in $tools) {
    $sourceUrl = "https://live.sysinternals.com/" + $tool
    $destPath  = Join-Path -Path $toolsDir -ChildPath $tool
    
    try {
        Write-Output ("[*] Downloading: " + $tool.PadRight(18) + " from live.sysinternals.com...")
        $webClient.DownloadFile($sourceUrl, $destPath)
        if (Test-Path $destPath) {
            Write-Output ("    -> [OK] " + $tool + " saved successfully.")
        } else {
            Write-Output ("    -> [FAIL] " + $tool + " could not be saved.")
        }
    } catch {
        Write-Output ("    -> [FAIL] Error downloading " + $tool + ": " + $_.Exception.Message)
    }
}

# 5. Add C:\CCDC\Tools to System PATH for Current Session
$env:Path += ";$toolsDir"

Write-Output "`n================================================================="
Write-Output "                  DOWNLOAD SEQUENCE COMPLETE                     "
Write-Output "================================================================="
Write-Output "[+] All tools are stored in C:\CCDC\Tools"
Write-Output "[+] Added C:\CCDC\Tools to the current session PATH."
Write-Output "[*] You can now run tools directly from any console (e.g., autorunsc, tcpview)."
