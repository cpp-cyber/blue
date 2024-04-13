param (
    [string]$Ip,
    [string]$Webroot = ".",
    [int]$Port = 8080
)

if (-not (Test-Path -Path $webroot -PathType Container)) {
    Write-Host "Webroot folder not found. Please provide a valid path."
    exit
}

Set-Location $webroot


$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://$ip`:$port/")
$listener.Start()

Write-Host "HTTP server started. Listening on http://$ip`:$port/" -ForegroundColor Green


try {
    
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $response = $context.Response
        $requestedPath = $context.Request.Url.LocalPath
        $fullPath = Join-Path $webroot $requestedPath

        if (Test-Path -Path $fullPath) {
            if ((Get-Item $fullPath).Attributes -eq 'Directory') {
                $files = Get-ChildItem $fullPath
                $directoryListing = "<html><body><h1>Directory Listing</h1><ul>"
                foreach ($file in $files) {
                    if ($requestedPath -ne "/") {
                        $fileLink = "<li><a href='http://$ip`:$port$requestedPath/$($file.Name)'>$($file.Name)</a></li>"
                    } else {
                        $fileLink = "<li><a href='http://$ip`:$port$requestedPath$($file.Name)'>$($file.Name)</a></li>"
                    }
                    $directoryListing += $fileLink
                }
                $directoryListing += "</ul></body></html>"
                $directoryBytes = [System.Text.Encoding]::UTF8.GetBytes($directoryListing)
                $response.ContentType = "text/html"
                $response.ContentLength64 = $directoryBytes.Length
                $response.OutputStream.Write($directoryBytes, 0, $directoryBytes.Length)
            } else {
                $fileBytes = [System.IO.File]::ReadAllBytes($fullPath)
                $response.ContentLength64 = $fileBytes.Length
                $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
            }
        } else {
            $response.StatusCode = 404
            $response.StatusDescription = "Not Found"
            $errorPage = "<html><body><h1>404 - File or Directory Not Found</h1></body></html>"
            $errorBytes = [System.Text.Encoding]::UTF8.GetBytes($errorPage)
            $response.ContentType = "text/html"
            $response.ContentLength64 = $errorBytes.Length
            $response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
        }

        $response.Close()
    }
}
catch {
    Write-Host "Stopping HTTP server..."
}
$listener.Stop()
$listener.Close()
