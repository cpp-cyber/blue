Write-Output "`n================================================================="
Write-Output "               POST-HARDENING INDEPENDENT AUDIT                  "
Write-Output "================================================================="
Write-Output ("{0,-32} {1,-10} {2}" -f "SECURITY CONTROL", "STATUS", "LIVE SYSTEM VALUE")
Write-Output ("{0,-32} {1,-10} {2}" -f "================", "======", "=================")

function Test-Check {
    param([string]$Name, [bool]$Condition, [string]$Value)
    $status = if ($Condition) { "[PASS]" } else { "[FAIL]" }
    Write-Output ("{0,-32} {1,-10} {2}" -f $Name, $status, $Value)
}

# 1. ZeroLogon (Netlogon FullSecureChannelProtection)
$netlogon = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters" -ErrorAction SilentlyContinue).FullSecureChannelProtection
Test-Check "ZeroLogon (FullSecureChannel)" ($netlogon -eq 1) "Registry Value = $netlogon (Expected: 1)"

# 2. Machine Account Quota (NoPac)
$quota = ([ADSI]"LDAP://$(([ADSI]'LDAP://RootDSE').defaultNamingContext)").Properties["ms-DS-MachineAccountQuota"].Value
Test-Check "NoPac (MachineAccountQuota)" ($quota -eq 0) "Domain Quota = $quota (Expected: 0)"

# 3. Kerberos AES Encryption
$enc = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" -ErrorAction SilentlyContinue).SupportedEncryptionTypes
Test-Check "Kerberos AES Only" ($enc -eq 24 -or $enc -eq 0x18) "SupportedEncryptionTypes = $enc (Expected: 24 / 0x18)"

# 4. SMBv1 Protocol
$smb1 = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -ErrorAction SilentlyContinue).SMB1
Test-Check "SMBv1 Disabled (EternalBlue)" ($smb1 -eq 0) "SMB1 Registry = $smb1 (Expected: 0)"

# 5. SMB Packet Signing
$smbSign = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -ErrorAction SilentlyContinue).RequireSecuritySignature
Test-Check "SMB Packet Signing Enforced" ($smbSign -eq 1) "RequireSecuritySignature = $smbSign (Expected: 1)"

# 6. LLMNR Multicast
$llmnr = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -ErrorAction SilentlyContinue).EnableMulticast
Test-Check "LLMNR Disabled (Responder)" ($llmnr -eq 0) "EnableMulticast = $llmnr (Expected: 0)"

# 7. NetBIOS over TCP/IP
$netbiosOpen = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" | Where-Object { $_.TcpipNetbiosOptions -ne 2 }
Test-Check "NetBIOS Disabled on All NICs" ($netbiosOpen -eq $null) "Active NICs with NetBIOS enabled = $($netbiosOpen.Count)"

# 8. LSASS Protection (RunAsPPL)
$ppl = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue).RunAsPPL
Test-Check "LSASS RunAsPPL (Anti-Mimikatz)" ($ppl -eq 1) "RunAsPPL = $ppl (Expected: 1)"

# 9. WDigest Cleartext Caching
$wdigest = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\SecurityProviders\WDigest" -ErrorAction SilentlyContinue).UseLogonCredential
Test-Check "WDigest Cleartext Disabled" ($wdigest -eq 0) "UseLogonCredential = $wdigest (Expected: 0)"

# 10. NTLMv2 Only (LmCompatibilityLevel)
$lm = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -ErrorAction SilentlyContinue).LmCompatibilityLevel
Test-Check "NTLMv2 Only Enforced" ($lm -eq 5) "LmCompatibilityLevel = $lm (Expected: 5)"

# 11. LDAP Server Integrity (Signing)
$ldapSign = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -ErrorAction SilentlyContinue).LDAPServerIntegrity
Test-Check "LDAP Signing Enforced" ($ldapSign -eq 2) "LDAPServerIntegrity = $ldapSign (Expected: 2)"

# 12. LDAP Channel Binding (CBT)
$ldapCBT = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -ErrorAction SilentlyContinue).LdapEnforceChannelBinding
Test-Check "LDAP Channel Binding (CBT)" ($ldapCBT -eq 2) "LdapEnforceChannelBinding = $ldapCBT (Expected: 2)"

# 13. Print Spooler Service
$spooler = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
$spoolerCim = Get-CimInstance Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue
Test-Check "Print Spooler Disabled" ($spooler.Status -eq "Stopped" -and $spoolerCim.StartMode -eq "Disabled") "Status: $($spooler.Status), Mode: $($spoolerCim.StartMode)"

# 14. Rogue OpenSSH Service
$ssh = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
$sshCim = Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
$sshOk = (-not $ssh) -or ($ssh.Status -eq "Stopped" -and $sshCim.StartMode -eq "Disabled")
Test-Check "Rogue SSH Backdoor Dead" $sshOk "Status: $($ssh.Status), Mode: $($sshCim.StartMode)"

# 15. Rogue Scheduled Tasks (ithelp4.me logic bomb)
$task1 = cmd.exe /c "schtasks.exe /query /tn `"Mozilla Update`"" 2>&1
$task2 = cmd.exe /c "schtasks.exe /query /tn `"Mozilla Monitor`"" 2>&1
$tasksGone = ($task1 -match "cannot find" -or $task1 -match "ERROR") -and ($task2 -match "cannot find" -or $task2 -match "ERROR")
Test-Check "Rogue Tasks Purged (ithelp4)" $tasksGone "Mozilla Update & Monitor purged"

# 16. Rogue WMI Consumers (Cozy Bear)
$consumers = Get-CimInstance -Namespace root\subscription -ClassName CommandLineEventConsumer -ErrorAction SilentlyContinue
Test-Check "WMI Persistence Purged" ($consumers -eq $null) "Rogue Consumers in root\subscription = $($consumers.Count)"

Write-Output "================================================================="
