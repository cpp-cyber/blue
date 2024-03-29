Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force

$Error.Clear()
$ErrorActionPreference = "SilentlyContinue"

#Hostname and IP
Write-Output "#### Start Hostname ####"
Get-WmiObject -Namespace root\cimv2 -Class Win32_ComputerSystem | Select-Object Name, Domain
Write-Output "#### End Hostname ####" 

Write-Output "#### Start IP ####" 
Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IpAddress -ne $null } | ForEach-Object { $_.IPAddress } | Where-Object { [System.Net.IPAddress]::Parse($_).AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork }
Write-Output "#### End IP ####"

Write-Output "`n#### Current Admin ####" 
whoami.exe

Write-Output "`n#### OS ####" 
(Get-WMIObject win32_operatingsystem).caption

$DC = Get-WmiObject -Query "select * from Win32_OperatingSystem where ProductType='2'"
if ($DC) {
    Write-Output "`n#### DC Detected ####"

    Write-Output "`n#### Start DNS Records ####"
    try {
        Get-DnsServerResourceRecord -ZoneName $($(Get-ADDomain).DNSRoot) | Where-Object { $_.RecordType -notmatch "SRV|NS|SOA" -and $_.HostName -notmatch "@|DomainDnsZones|ForestDnsZones" } | Format-Table
    }
    catch {
        Write-Output "[ERROR] Failed to get DNS records, DC likely too old"
    }
    Write-Output "#### End DNS Records ####"
}

function Get-SharePerms {
    param (
        [string]$ShareName
    )
    $SharePermissions = net share $ShareName | Select-Object -Skip 6 | Select-Object -SkipLast 3
    foreach ($SharePermission in $SharePermissions) {
        $SharePermission = $SharePermission -replace '\s+', '' -replace '.*Permission'
        $SharePermissionString += $SharePermission + "`n"
    }
    return $SharePermissionString
}

Write-Output "#### Start SMB Shares ####" 
$Shares = Get-WmiObject Win32_Share
$ShareInfo = @()
foreach ($Share in $Shares) {
    $ShareInfo += New-Object PSObject -Property @{
        "Name"        = $Share.Name
        "Path"        = $Share.Path
        "Description" = $Share.Description
        "Permissions" = (Get-SharePerms -ShareName $Share.Name)
    }
}
$ShareInfo | Select-Object Name, Path, Description, Permissions | Format-Table -AutoSize -Wrap
Write-Output "#### End SMB Shares ####" 

if (Get-Service -Name W3SVC -ErrorAction SilentlyContinue) {
    Write-Output "#### IIS Detected ####"
    Import-Module WebAdministration
    Write-Output "`n#### Start IIS Site Bindings ####"
    $websites = Get-ChildItem IIS:\Sites | Sort-Object name

    foreach ($site in $websites) {
        Write-Output "Website Name: $($site.Name)"
        Write-Output "Website Path: $($site.physicalPath)"
        $bindings = Get-WebBinding -Name $site.name
        foreach ($binding in $bindings) {
            Write-Output "    Binding Information:"
            Write-Output "        Protocol: $($binding.protocol)"
            Write-Output "        IP Address: $($binding.bindingInformation.split(":")[0])"
            Write-Output "        Port: $($binding.bindingInformation.split(":")[1])"
            Write-Output "        Hostname: $($binding.hostHeader)"
        }
        Write-Output ""
    }
    Write-Output "#### End IIS Site Bindings ####"
}

Write-Output "`n#### Start General Service Detection ####"
$Services = @()
$CheckServices = @("mssql", "mysql", "mariadb", "pgsql", "apache", "nginx", "tomcat", "httpd", "mongo", "ftp", "filezilla", "ssh", "vnc")
foreach ($CheckService in $CheckServices) {
    $SvcQuery = Get-WmiObject win32_service | Where-Object { $_.Name -like "*$CheckService*" }
    if ($null -ne $SvcQuery) {
        if ($SvcQuery.GetType().IsArray) {
            foreach ($Svc in $SvcQuery) {
                $Services += $Svc
                
            }
        }
        elseif ($SvcQuery) {
            $Services += $SvcQuery
        }
    }
    
}

$Services | Select-Object Name, DisplayName, State, PathName | Format-Table -AutoSize -Wrap

Write-Output "#### End General Service Detection ####"

Write-Output "`n#### Start NSSM Services ####"
Get-WmiObject win32_service | Where-Object { $_.PathName -like '*nssm*' } | Select-Object Name, DisplayName, State, PathName | Format-Table -AutoSize -Wrap
Write-Output "#### End NSSM Services ####"

Write-Output "`n#### Start TCP Connections ####"
function Get-TcpConnections {
    $connections = netstat -anop TCP | Where-Object { $_ -match '\s+TCP\s+' }
    $connectionInfo = @()

    foreach ($connection in $connections) {
        $cols = $connection -split '\s+'
        $localAddress = $cols[2].Split(":")[0]
        $localPort = $cols[2].Split(":")[-1]
        $remoteAddress = $cols[3].Split(":")[0]
        $remotePort = $cols[3].Split(":")[-1]
        $state = $cols[4]
        $processpid = $cols[-1]

        $connectionInfo += New-Object PSObject -Property @{
            "LocalAddress"  = $localAddress
            "LocalPort"     = $localPort
            "RemoteAddress" = $remoteAddress
            "RemotePort"    = $remotePort
            "State"         = $state
            "PID"           = $processpid
            "ProcessName"   = (Get-Process -Id $processpid).ProcessName
        }
    }

    return $connectionInfo
}
$TCPConnections = Get-TcpConnections

$TCPConnections | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, PID, ProcessName | Format-Table -AutoSize
Write-Output "`n#### End TCP Connections ####"

Write-Output "`n#### Start Installed Programs ####" 
$programs = foreach ($UKey in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\Wow6432node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Wow6432node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
    foreach ($Product in (Get-ItemProperty $UKey -ErrorAction SilentlyContinue)) {
        if ($Product.DisplayName -and $Product.SystemComponent -ne 1) {
            $Product.DisplayName + " - " + $Product.DisplayVersion
        }
    }
}
$programs = $programs | sort.exe
Write-Output $programs
Write-Output "#### End Installed Programs ####" 

#Users and Groups
Write-Output "`n#### Start Group Membership ####" 
if ($DC) {
    $Groups = Get-ADGroup -Filter 'SamAccountName -NotLike "Domain Users"' | Select-Object -ExpandProperty Name
    $Groups | ForEach-Object {
        $Users = Get-ADGroupMember -Identity $_ | Select-Object -ExpandProperty Name
        if ($Users.Count -gt 0) {
            $Users = $Users | ForEach-Object { "   Member: $_" }
            Write-Output "Group: $_" $Users
        }
    }
}
else {
    # Get a list of all local groups
    $localGroups = [ADSI]"WinNT://localhost"

    # Iterate through each group
    $localGroups.psbase.Children | Where-Object { $_.SchemaClassName -eq 'group' } | ForEach-Object {

        $groupName = $_.Name[0]
        Write-Output "Group: $groupName"
        
        # List members of the current group
        $_.Members() | ForEach-Object {
            $memberPath = ([ADSI]$_).Path.Substring(8)
            Write-Output "    Member: $memberPath"
        }
    }
}
Write-Output "#### End Group Membership ####" 

Write-Output "`n#### Start ALL Users ####" 
Get-WmiObject win32_useraccount | ForEach-Object { $_.Name }
Write-Output "`n#### End ALL Users ####" 

Write-Output "`n#### Start DNS Servers ####" 
$dnsAddresses = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | 
Where-Object { $_.OperationalStatus -eq 'Up' -and $_.NetworkInterfaceType -ne 'Loopback' } | 
ForEach-Object { $_.GetIPProperties().DnsAddresses }

$dnsAddresses | Select-Object -ExpandProperty IPAddressToString
Write-Output "#### End DNS Servers ####"

Write-Output "`n#### Start Registry Startups ####" 
$regPath = @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", 
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnceEx", 
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce", 
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", 
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce", 
    "HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\AlternateShell", 
    "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\AlternateShells\AvailableShells", 
    "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components", 
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunServicesOnce", 
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunServicesOnce", 
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunServices", 
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunServices", 
    "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Userinit", 
    "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell", 
    "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows")
foreach ($item in $regPath) {
    try {
        $reg = Get-ItemProperty -Path $item -ErrorAction SilentlyContinue
        Write-Output "[Registry Startups] $item" 
        $reg | Get-Member -MemberType NoteProperty -ErrorAction SilentlyContinue | Select-Object -Expand Name | ForEach-Object {
            if ($_.StartsWith("PS") -or $_.StartsWith("VM")) {
                # Write-Output "[Startups: Registry Values] Default value detected"
            }
            else {
                Write-Output "   [$_] $($reg.$_)" 
            }
        }
    }
    catch {
        Write-Output "[Registry Startup] $item Not Found" 
    }
}
Write-Output "#### End Registry Startups ####" 

#Scheduled Tasks
Write-Output "`n#### Start Scheduled Tasks ####" 
$scheduledTasksXml = schtasks /query /xml ONE
$tasks = [xml]$scheduledTasksXml
$taskList = @()
for ($i = 0; $i -lt $tasks.Tasks.'#comment'.Count; $i++) {
    $taskList += [PSCustomObject] @{
        TaskName = $tasks.Tasks.'#comment'[$i]
        Task     = $tasks.Tasks.Task[$i]
    }
}
$filteredTasks = $taskList | Where-Object {
    ($_.Task.RegistrationInfo.Author -notlike '*.exe*') -and
    ($_.Task.RegistrationInfo.Author -notlike '*.dll*')
}
$filteredTasks | ForEach-Object {
    $taskName = $_.TaskName
    $fields = schtasks /query /tn $taskName.trim() /fo LIST /v | Select-String @('TaskName:', 'Author: ', 'Task to Run:')
    $fields | Out-String
}
Write-Output "#### End Scheduled Tasks ####" 

#Windows Features
Write-Output "`n#### Start Features ####" 
dism /online /get-features /Format:Table | Select-String Enabled | ForEach-Object { $_.ToString().Split(" ")[0].Trim() } | sort.exe
Write-Output "#### End Features ####"

if ($Error[0]) {
    Write-Output "`n#########################"
    Write-Output "#        ERRORS         #"
    Write-Output "#########################`n"

    foreach ($err in $error) {
        Write-Output $err
    }
}