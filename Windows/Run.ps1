param(
    [Parameter(Mandatory=$false)]
    [String]$Script = '',

    [Parameter(Mandatory=$false)]
    [String]$Out = '',

    [Parameter(Mandatory=$false)]
    [switch]$Connect,

    [Parameter(Mandatory=$false)]
    [switch]$Repair,

    [Parameter(Mandatory=$false)]
    [string[]]$Include,

    [Parameter(Mandatory=$false)]
    [string[]]$Exclude,

    [Parameter(Mandatory=$false)]
    [String]$Admin,

    [Parameter(Mandatory=$false)]
    [switch]$NonDomain,

    [Parameter(Mandatory=$false)]
    [String]$Hosts = '',

    [Parameter(Mandatory=$false)]
    [Int]$Timeout = 3000
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Web
function Get-Password {
    do {
        $p = [System.Web.Security.Membership]::GeneratePassword(14,4)
    } while ($p -match '[,;:|iIlLoO0]')
    return $p + "1!"
}

if ($Connect) {

    if (!$Repair) {
        Remove-Variable -Name Sessions -Scope Global -ErrorAction SilentlyContinue;
        Remove-Variable -Name Denied -Scope Global -ErrorAction SilentlyContinue;
        $global:Sessions = @()
        $global:Denied = @()
        Get-PSSession | Remove-PSSession
    }

    if ($NonDomain) {
        $global:Cred = Get-Credential

        if ($Repair) {
            if ($global:Sessions.Count -eq 0) {
                Write-Host "[ERROR] No sessions" -ForegroundColor Red
                exit
            }
            else {
                for ($i = 0; $i -lt $global:Sessions.count; $i++) {
                    if ($Sessions[$i].State -eq "Broken" -or $Sessions[$i].State -eq "Disconnected") {
                        $global:Sessions[$i] = New-PSSession -ComputerName $global:Sessions[$i].ComputerName -Credential $global:Cred
                        Write-Host "[INFO] Reconnected: $($global:Sessions[$i].ComputerName)" -ForegroundColor Green
                    }
                }
            }
        } else {
            try {
                $Computers = Get-Content $Hosts
            }
            catch {
                Write-Host "[ERROR] Failed to get computers from file" -ForegroundColor Red
                exit
            }

            $workingDir = $PWD | Select-Object -ExpandProperty Path

            foreach ($Computer in $Computers) {
                Start-Job -ScriptBlock {cd $Using:workingDir; Import-Module .\testport.ps1; Test-Port -Ip $Using:Computer -Port 5985}
            }
            $5985Table = Receive-Job * -Wait

            foreach ($Computer in $Computers) {
                Start-Job -ScriptBlock {cd $Using:workingDir; Import-Module .\testport.ps1; Test-Port -Ip $Using:Computer -Port 5986}
            }
            $5986Table = Receive-Job * -Wait
    
            foreach ($Computer in $Computers) {
                if ($5985Table.$Computer) {
                    $TestSession = New-PSSession -ComputerName $Computer -Credential $global:Cred
                    if ($TestSession) {
                        $global:Sessions += $TestSession
                        Write-Host "[INFO] Connected: $Computer" -ForegroundColor Green
                    }
                    else {
                        $global:Denied += $Computer
                        Write-Host "[ERROR] WinRM 5985 Failed: $Computer" -ForegroundColor Red
                    }
                }
                elseif ($5986Table.$Computer) {
                    $TestSession = New-PSSession -ComputerName $Computer -Credential $global:Cred -UseSSL -SessionOption @{SkipCACheck=$true;SkipCNCheck=$true;SkipRevocationCheck=$true}
                    if ($TestSession) {
                        $global:Sessions += $TestSession
                        Write-Host "[INFO] Connected SSL: $Computer" -ForegroundColor Green
                    }
                    else {
                        $global:Denied += $Computer
                        Write-Host "[ERROR] WinRM 5986 Failed: $Computer" -ForegroundColor Red
                    }
                }
                else {
                    $global:Denied += $Computer
                    Write-Host "[ERROR] WinRM Ports Closed: $Computer" -ForegroundColor Red
                }
                
            }
        }
    }
    else {
        if ($Repair) {
            if ($global:Sessions.Count -eq 0) {
                Write-Host "[ERROR] No sessions" -ForegroundColor Red
                exit
            }
            else {
                for ($i = 0; $i -lt $global:Sessions.count; $i++) {
                    if ($Session.State -eq "Broken" -or $Session.State -eq "Disconnected") {
                        $global:Sessions[$i] = New-PSSession -ComputerName $global:Sessions[$i].ComputerName
                        Write-Host "[INFO] Reconnected: $($global:Sessions[$i].ComputerName)" -ForegroundColor Green
                    }
                }
            }
        } else {
            try {
                $Computers = Get-ADComputer -filter * -Properties * | Where-Object OperatingSystem -Like "*Windows*" | Sort-Object | Select-Object -ExpandProperty Name
            }
            catch {
                Write-Host "[ERROR] Failed to get computers from AD" -ForegroundColor Red
                exit
            }
    
            Write-Host "[INFO] Found the following servers:" -ForegroundColor Green
            foreach ($Computer in $Computers) {
                Write-Host "$Computer"
            }

            $workingDir = $PWD | Select-Object -ExpandProperty Path

            foreach ($Computer in $Computers) {
                Start-Job -ScriptBlock {cd $Using:workingDir; Import-Module .\testport.ps1; Test-Port -Ip $Using:Computer -Port 5985}
            }
            $5985Table = Receive-Job * -Wait

            foreach ($Computer in $Computers) {
                Start-Job -ScriptBlock {cd $Using:workingDir; Import-Module .\testport.ps1; Test-Port -Ip $Using:Computer -Port 5986}
            }
            $5986Table = Receive-Job * -Wait

            foreach ($Computer in $Computers) {
                if ($5985Table.$Computer) {
                    $TestSession = New-PSSession -ComputerName $Computer -Credential $global:Cred
                    if ($TestSession) {
                        $global:Sessions += $TestSession
                        Write-Host "[INFO] Connected: $Computer" -ForegroundColor Green
                    }
                    else {
                        $global:Denied += $Computer
                        Write-Host "[ERROR] WinRM 5985 Failed: $Computer" -ForegroundColor Red
                    }
                }
                elseif ($5986Table.$Computer) {
                    $TestSession = New-PSSession -ComputerName $Computer -Credential $global:Cred -UseSSL -SessionOption @{SkipCACheck=$true;SkipCNCheck=$true;SkipRevocationCheck=$true}
                    if ($TestSession) {
                        $global:Sessions += $TestSession
                        Write-Host "[INFO] Connected SSL: $Computer" -ForegroundColor Green
                    }
                    else {
                        $global:Denied += $Computer
                        Write-Host "[ERROR] WinRM 5986 Failed: $Computer" -ForegroundColor Red
                    }
                }
                else {
                    $global:Denied += $Computer
                    Write-Host "[ERROR] WinRM Ports Closed: $Computer" -ForegroundColor Red
                }
                
            }
        }
    }
}

if (($Script -ne '') -and ($global:Sessions.Count -gt 0) -and ($Out -ne '')) {

    if (!(Test-Path $Out)) {
        mkdir $Out
    }
    $Jobs = @()
    do {
        $Extension = ""
        $Script = $Script.ToLower()
        $ScriptName = $Script.Split(".")[-2]
        $Extension += $ScriptName.Substring(1)
        $Extension += ".$(Get-Random -Maximum 1000)";
    } while (Test-Path "$Out\*.$Extension")

    foreach ($Session in $global:Sessions) {
        if ($Exclude -contains $Session.ComputerName) {
            Write-Host "[INFO] Excluded: $($Session.ComputerName)" -ForegroundColor Yellow
            continue
        }
        elseif ($Include.Count -gt 0 -and $Include -notcontains $Session.ComputerName) {
            Write-Host "[INFO] Did not Include: $($Session.ComputerName)" -ForegroundColor Yellow
            continue
        }
        if ($Script -match "Usr.ps1") {
            if ($Admin -eq '') {
                Write-Host "[ERROR] No admin name" -ForegroundColor Red
                exit
            }
            else {
                $P1 = Get-Password
                $P2 = Get-Password
                $ScriptJob = Invoke-Command -FilePath $Script -ArgumentList $Admin, $P1, $P2 -Session $Session -AsJob
                Write-Host "[INFO: $Script - $($Session.ComputerName)] Created $($Admin):$($P2)" -ForegroundColor Magenta
                Write-Host "[INFO: $Script - $($Session.ComputerName)] Changed all users to $P1" -ForegroundColor Magenta
                Write-Output ("$($Session.ComputerName):$($Admin):$($P2)") | Out-File $Out\usr_log.txt -Append -Encoding utf8
                Write-Output ("$($Session.ComputerName):All:$($P1)") | Out-File $Out\usr_log.txt -Append -Encoding utf8
            }
        }
        else {
            $ScriptJob = Invoke-Command -FilePath $Script -Session $Session -AsJob
        }
        $Jobs += $ScriptJob
        Write-Host "[INFO: $Script] Script invoked on $($Session.ComputerName)" -ForegroundColor Green
    }
    
    $Complete = @()
    $TotalJobs = $Jobs.count
    $IncompleteJobs = @()
    while ($Complete.Count -lt $TotalJobs) {
        for ($i = 0; $i -lt $Jobs.count; $i++) {
            if ($Jobs[$i].State -eq "Completed" -and $Complete -notcontains $Jobs[$i].Location) {
                $Jobs[$i] | Receive-Job | Out-File "$Out\$($Jobs[$i].Location).$Extension" -Encoding utf8
                Write-Host "[INFO: $Script] Script completed on $($Jobs[$i].Location) logged to $Extension" -ForegroundColor Green
                $Complete += $($Jobs[$i].Location)
                #Get-Job
            }
            elseif ($Jobs[$i].State -eq "Running" -and $Complete -notcontains $Jobs[$i].Location){
                $IncompleteJobs += $Jobs[$i]
            }
            elseif ($Jobs[$i].State -eq "Failed" -and $Complete -notcontains $Jobs[$i].Location){
                Write-Host "[ERROR: $Script] Script failed on $($Jobs[$i].Location)" -ForegroundColor Red
                $Complete += $($Jobs[$i].Location)
            }
        }
        if ($IncompleteJobs.Count -ge 1){
            $Jobs = $IncompleteJobs
            $IncompleteJobs = @()
            Start-Sleep -Milliseconds 25
        }
    }
    Get-Job | Remove-Job
}
if ($Sessions.Count -eq 0 -and !$Connect) {
    Write-Host "[ERROR] No sessions" -ForegroundColor Red
}
if ($Script -eq '' -and !$Connect) {
    Write-Host "[ERROR] No script" -ForegroundColor Red
}
if ($Out -eq '' -and !$Connect) {
    Write-Host "[ERROR] No output directory" -ForegroundColor Red
}
