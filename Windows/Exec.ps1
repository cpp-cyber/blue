if ($Env:PROCESSOR_ARCHITECTURE -eq "AMD64") {
    Start-Process powershell -ArgumentList ""
    Start-Process powershell -ArgumentList ""
}
else {
    Start-Process powershell -ArgumentList ""
    Start-Process powershell -ArgumentList ""
}
Write-Output "$Env:ComputerName [INFO] Executed "