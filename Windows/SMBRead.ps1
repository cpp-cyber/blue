$Error.Clear()
$ErrorActionPreference = "SilentlyContinue"

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
[string] $ExemptShares = "NETLOGON", "SYSVOL", "ADMIN$", "C$", "IPC$", "AdminUIContentPayload", "EasySetupPayload", "SCCMContentLib$", "SMS_CPSC$", "SMS_DP$", "SMS_OCM_DATACACHE", "SMS_SITE", "SMS_SUIAgent", "SMS_WWW", "SMSPKGC$", "SMSSIG$"


foreach ($Share in Get-SmbShare) {
    $Name = $Share.Name
    if ($ExemptShares.Contains($Name)) {
        Write-Output "`nThe $Name SMB share is exempt"
    }
    else {
        $SmbShareAccess = Get-SmbShareAccess -Name $Name

        Write-Output "`n[HARDENING $Name SHARE]"

        foreach ($Entry in $SmbShareAccess) {
            Grant-SmbShareAccess -Name $Name -AccountName $($Entry.AccountName) -AccessRight Read -F | Out-Null
            
            Write-Output "`n$($Entry.AccountName)'s $Name access right set"
        }

        Write-Output "`n[$Name HARDENING COMPLETE]`n"
        Get-SmbShareAccess -Name $Name
    }

}

Write-Output "`n[INFO] Set SMB share permissions"

if ($Error[0]) {
    Write-Output "`n#########################"
    Write-Output "#        ERRORS         #"
    Write-Output "#########################`n"


    foreach ($err in $error) {
        Write-Output $err
    }
}