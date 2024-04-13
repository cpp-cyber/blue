$Error.Clear()
$ErrorActionPreference = "Continue"

Write-Output "#########################"
Write-Output "#                       #"
Write-Output "#          SMB          #"
Write-Output "#                       #"
Write-Output "#########################"

Write-Output "#########################"
Write-Output "#    Hostname/Domain    #"
Write-Output "#########################"
Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem | Select-Object Name, Domain
Write-Output "#########################"
Write-Output "#          IP           #"
Write-Output "#########################"
Get-WmiObject Win32_NetworkAdapterConfiguration | ? { $_.IpAddress -ne $null } | % { $_.ServiceName + "`n" + $_.IPAddress + "`n" }
######### SMB #########
reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v SMB1 /t REG_DWORD /d 0 /f | Out-Null
reg add "HKLM\System\CurrentControlSet\Services\LanManWorkstation\Parameters" /v RequireSecuritySignature /t REG_DWORD /d 1 /f | Out-Null
reg add "HKLM\System\CurrentControlSet\Services\LanManWorkstation\Parameters" /v EnableSecuritySignature /t REG_DWORD /d 1 /f | Out-Null
reg add "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" /v RequireSecuritySignature /t REG_DWORD /d 1 /f | Out-Null
reg add "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" /v EnableSecuritySignature /t REG_DWORD /d 1 /f | Out-Null

#reg add "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" /v AutoShareServer /t REG_DWORD /d 0 /f | Out-Null
#reg add "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" /v AutoShareWks /t REG_DWORD /d 0 /f | Out-Null
#net share C$ /delete | Out-Null
#net share ADMIN$ /delete | Out-Null
Write-Output "$Env:ComputerName SMB settings applied`n"

# Define a list of shares that should be exempt from hardening
[string[]] $ExemptShares = "NETLOGON", "SYSVOL", "ADMIN$", "C$", "IPC$", "AdminUIContentPayload", "EasySetupPayload", "SCCMContentLib$", "SMS_CPSC$", "SMS_DP$", "SMS_OCM_DATACACHE", "SMS_SITE", "SMS_SUIAgent", "SMS_WWW", "SMSPKGC$", "SMSSIG$"

# Get each share, compare against list of exempt shares, and if no match set read-only
foreach ($Share in Get-SmbShare) {
    $Name = $Share.Name
    if ($ExemptShares.Contains($Name)) {
        Write-Output "The $Name SMB share is exempt`n"
    }
    else {
        $SmbShareAccess = Get-SmbShareAccess -Name $Name

        Write-Output "[HARDENING $Name SHARE]`n"

        foreach ($Entry in $SmbShareAccess) {
            Grant-SmbShareAccess -Name $Name -AccountName $($Entry.AccountName) -AccessRight Read -F | Out-Null
            
            Write-Output "$($Entry.AccountName)'s $Name access right set`n"
        }

        Write-Output "[$Name HARDENING COMPLETE]"
        Get-SmbShareAccess -Name $Name | Format-Table -AutoSize -Wrap
    }
}

Write-Output "[INFO] Set SMB share permissions"

if ($Error[0]) {
    Write-Output "`n#########################"
    Write-Output "#        ERRORS         #"
    Write-Output "#########################`n"


    foreach ($err in $error) {
        Write-Output $err
    }
}