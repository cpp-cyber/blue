Setup:
```shell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12; $u='https://raw.githubusercontent.com/cpp-cyber/blue/refs/heads/main/nosodium/setup.ps1?nocache='+(Get-Random); (New-Object System.Net.WebClient).DownloadFile($u, \"$env:TEMP\setup.ps1\"); & \"$env:TEMP\setup.ps1\""
```

```shell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/cpp-cyber/blue/refs/heads/main/nosodium/setup.ps1?v=' + (Get-Random), "$env:TEMP\setup.ps1"); & "$env:TEMP\setup.ps1"
```
