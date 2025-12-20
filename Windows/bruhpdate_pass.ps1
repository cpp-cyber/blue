# List of users to bruhpdate
#Input your users usernames in quotations and separate them by comma and space
$users = @("User1", "User2", "User3", "User4", "User5")

# Output file on C drive
$outputFile = "C:\UserPasswords.csv"

# Create CSV header
"Username,Password" | Out-File $outputFile

foreach ($user in $users) {

    # Generate a random password (12 characters with complexity)
    $password = [System.Web.Security.Membership]::GeneratePassword(12,2)

    # Convert to secure string
    $securePass = ConvertTo-SecureString $password -AsPlainText -Force

    try {
        # Change the user's password
        Set-LocalUser -Name $user -Password $securePass

        # Output to console
        Write-Output "Updated: $user  | New Password: $password"

        # Output to CSV
        "$user,$password" | Out-File $outputFile -Append
    }
    catch {
        Write-Output "Failed to bruhpdate $user — $($_.Exception.Message)"
    }
}

Write-Host "Password bruhpdate complete. Output saved to: $outputFile"
