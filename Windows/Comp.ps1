$events = Get-WinEvent -FilterHashtable @{LogName='System';ID=7045}

    Write-Output "#########################"
    Write-Output "#    Service Creation   #"
    Write-Output "#########################"

foreach ($event in $events) {
    $properties = $event.Properties

    $creationDate = $event.TimeCreated
    $serviceName = $properties[0].Value
    $binaryPath = $properties[1].Value

    Write-Output "Creation Date: $creationDate"
    Write-Output "Service Name: $serviceName"
    Write-Output "Binary Path: $binaryPath"
    Write-Output ""
}

$events = Get-WinEvent -FilterHashtable @{LogName='Security';ID=4742}

Write-Output "#########################"
Write-Output "#    Password Change    #"
Write-Output "#########################"

foreach ($event in $events) {
    $properties = $event.Properties

    $creationDate = $event.TimeCreated

    Write-Output "Computer Name: $($properties[1].Value)"
    Write-Output "User: $($properties[5].Value)"
    Write-Output "Event Time: $creationDate"
    Write-Output ""
}