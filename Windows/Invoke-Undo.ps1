function Test-WinRM {
    $Computers = Get-ADComputer -filter * -Properties * | Where-Object OperatingSystem -Like "*Windows*" | Select-Object -ExpandProperty DNSHostname
    $Denied = @()
    foreach ($Computer in $Computers) {
        try {
            $session = New-PSSession -ComputerName $env:COMPUTERNAME
            $session | Remove-PSSession
        }
        catch {
            $Denied += $Computer
            Write-Host "[ERROR] Failed: $Computer" -ForegroundColor Red
        }
    }
    if ($Denied.Count -gt 0) {
        Write-Host "[INFO] All computers have WinRM enabled" -ForegroundColor Green
    } else {
        Write-Host "[INFO] The following computers have WinRM disabled:" -ForegroundColor Red
        $Denied | Out-String
    }
}