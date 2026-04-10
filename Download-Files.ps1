#!ps
if (-not (Test-Path -Path "C:\ISTools")) {
    New-Item -ItemType Directory -Path "C:\ISTools" | Out-Null
}
if (Test-Path "C:\ISTools\D2GUsers.ps1") {
    $files = ('https://raw.githubusercontent.com/DuaneAbrames/D2G-Reports/refs/heads/main/D2GUsers.ps1',
    'https://raw.githubusercontent.com/DuaneAbrames/D2G-Reports/refs/heads/main/DemoAudit.ps1')

    foreach ($file in $files) {
        Write-Host   "Downloading $file..."
        $fileName = Join-path "C:\ISTools" (Split-Path -Path $file -Leaf)
        Invoke-WebRequest -Uri $file -OutFile $fileName
    }
}
