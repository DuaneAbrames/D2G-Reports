#!ps
#timeout=999999

if (Test-Path "C:\ISTools\D2GUsers.ps1") {
    $files = ('https://raw.githubusercontent.com/DuaneAbrames/D2G-Reports/refs/heads/main/D2GUsers.ps1',
    'https://raw.githubusercontent.com/DuaneAbrames/D2G-Reports/refs/heads/main/DemoAudit.ps1')

    foreach ($file in $files) {
        Write-Host   "Downloading $file..."
        $fileName = Join-path "C:\ISTools" (Split-Path -Path $file -Leaf)
        Invoke-WebRequest -Uri $file -OutFile $fileName
    }
    $schTask = (Get-ScheduledTask | Where-Object taskname -like "*d2g*user*").taskname
    Start-ScheduledTask -TaskName $schTask
    Write-Host "Scheduled Task $schTask has been started."
}
