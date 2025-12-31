param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile
)

function Read-File{
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (Test-Path $FilePath) {
        Get-Content $FilePath
    }
    else {
        Write-Error "File not found: $FilePath"
        exit 1
    }
}

# Read and parse usernames from file (remove empty lines and trim whitespace)
$users = Read-File -FilePath $InputFile | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() }

# Output file on C drive
$output = "C:\UserPasswords.csv"

# Create CSV header
"Username,Password" | Out-File $output

foreach ($user in $users) {

    # Generate a random password (16 characters with complexity)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
    $password = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })

    # Convert to secure string
    $securePass = ConvertTo-SecureString $password -AsPlainText -Force

    try {
        # Change the user's password
        Set-LocalUser -Name $user -Password $securePass
        # Output to CSV
        "$user,$password" | Out-File $output -Append
    }
    catch {
        Write-Output "Failed to bruhpdate $user — $($_.Exception.Message)"
    }
}

Write-Host "Password bruhpdate complete. Output saved to: $output"
