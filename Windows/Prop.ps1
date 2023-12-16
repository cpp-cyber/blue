param(
    [Parameter(Mandatory=$false)]
    [String]$Hosts = '',

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.PSCredential]$Cred = $Global:Cred,

    [Parameter(Mandatory=$false)]
    [Switch]$Purge
)
if (!$Purge -and $Hosts -ne '' -and $Cred -ne $null) {
    try {
        $Computers = Get-Content $Hosts
    }
    catch {
        Write-Host "[ERROR] Failed to get computers from file" -ForegroundColor Red
        exit
    }
    
    $DriveLetters = @()
    $DriveLetters = 65..90 | %{[char]$_}
    $i = 25
    
    foreach ($Computer in $Computers) {
        if ($i -ge 0) {
            try {
                New-PSDrive -Name $DriveLetters[$i] -PSProvider FileSystem -Root \\$Computer\C$ -Persist -Credential $Cred
                Robocopy.exe .\bins \\$Computer\C$\Windows\System32\bins /COMPRESS /MT:16 /R:1 /W:1 /UNILOG+:robo.log /TEE
            }
            catch {
                Write-Host "[ERROR] Failed to move bins to $Computer" -ForegroundColor Red
            }
            $i--
        }
        
    }
}
elseif ($Purge) {
    Get-PSDrive | ? {$_.DisplayRoot -ne $null} | Remove-PSDrive
    Write-Host "[INFO] Purged all drives" -ForegroundColor Yellow
}
elseif ($Hosts -eq '') {
    Write-Host "[ERROR] No hosts file specified" -ForegroundColor Red
}
elseif ($Cred -eq $null) {
    Write-Host "[ERROR] No credentials specified" -ForegroundColor Red
}
else {
    Write-Host "[ERROR] Unknown error" -ForegroundColor Red
}
