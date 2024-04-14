function Test-Port {
    Param(
        [string]$Ip,
        [int]$Port,
        [int]$Timeout = 3000,
        [switch]$Verbose
    )

    $ErrorActionPreference = "SilentlyContinue"

    $tcpclient = New-Object System.Net.Sockets.TcpClient
    $iar = $tcpclient.BeginConnect($ip,$port,$null,$null)
    $wait = $iar.AsyncWaitHandle.WaitOne($timeout,$false)
    if (!$wait)
    {
        # Close the connection and report timeout
        $tcpclient.Close()
        if ($verbose) { Write-Host "[WARN] $($IP):$Port Connection Timeout " -ForegroundColor Yellow }
        return @{ $Ip = $false }
    }
    else {
        # Close the connection and report the error if there is one
        $error.Clear()
        $tcpclient.EndConnect($iar) | out-Null
        if (!$?) {
            if ($verbose) { Write-Host $error[0] -ForegroundColor Red };
            return @{ $Ip = $false }
        }
        $tcpclient.Close()
    }
    return @{ $Ip = $true }
}
