#!ps
#timeout=999999

[CmdletBinding()]
Param()

$userPassword = "Y0u$h@llN0tP@ss+d2g"
$ownerName = 'DuaneAbrames'
$repositoryName = 'D2G-Reports'
$releaseApiUrl = "https://api.github.com/repos/$ownerName/$repositoryName/releases/latest"
$installDirectory = 'C:\ISTools'
$updaterScriptName = 'Update-And-Run-D2GUsers.ps1'
$scheduledTaskBaseName = 'D2G User Reports'

Import-Module ActiveDirectory

$adDomain = Get-ADDomain
$administratorUserName = "$($adDomain.NetBIOSName)\Administrator"
Write-Host "Using credentials for $administratorUserName to register scheduled tasks."
$credential = New-Object System.Management.Automation.PSCredential (
	$administratorUserName,
	(ConvertTo-SecureString -String $userPassword -AsPlainText -Force)
)

if (-not (Test-Path $installDirectory)) {
	New-Item -ItemType Directory -Path $installDirectory | Out-Null
}

function Get-LatestReleaseTag {
	param(
		[string]$ApiUrl
	)

	$release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ 'User-Agent' = 'D2GUsers-Deploy' } -ErrorAction Stop
	if ([string]::IsNullOrWhiteSpace($release.tag_name)) {
		throw 'Latest release did not include a tag name.'
	}

	return $release.tag_name
}

function Remove-LegacyD2GUserTasks {
	$taskService = New-Object -ComObject 'Schedule.Service'
	$taskService.Connect()
	$rootFolder = $taskService.GetFolder('\')

	foreach ($task in @($rootFolder.GetTasks(0))) {
		foreach ($taskAction in @($task.Definition.Actions)) {
			if ($taskAction.Path -match '(?i)powershell(\.exe)?$' -and $taskAction.Arguments -match '(?i)d2gusers\.ps1') {
				schtasks.exe /Delete /TN $task.Name /F | Out-Null
				break
			}
		}
	}
}

function Register-D2GUserTask {
	param(
		[string]$TaskName,
		[string[]]$ScheduleArguments,
		[string]$RunCommand,
		[string]$UserName,
		[string]$Password
	)

	$taskArguments = @(
		'/Create'
		'/TN', $TaskName
		'/TR', $RunCommand
		'/RU', $UserName
		'/RP', $Password
		'/RL', 'HIGHEST'
		'/F'
	) + $ScheduleArguments

	& schtasks.exe @taskArguments | Out-Null

	if ($LASTEXITCODE -ne 0) {
		throw "Failed to register scheduled task $TaskName."
	}
}

Remove-LegacyD2GUserTasks

$releaseTag = Get-LatestReleaseTag -ApiUrl $releaseApiUrl
$updaterDownloadUrl = "https://raw.githubusercontent.com/$ownerName/$repositoryName/$releaseTag/$updaterScriptName"
$updaterScriptPath = Join-Path -Path $installDirectory -ChildPath $updaterScriptName

Invoke-WebRequest -Uri $updaterDownloadUrl -OutFile $updaterScriptPath -Headers @{ 'User-Agent' = 'D2GUsers-Deploy' } -ErrorAction Stop

$taskRunCommand = "PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File `"$updaterScriptPath`""
$weeklyTaskName = "$scheduledTaskBaseName - Weekly"
$monthlyTaskName = "$scheduledTaskBaseName - Monthly"

schtasks.exe /Delete /TN $weeklyTaskName /F 2>$null | Out-Null
schtasks.exe /Delete /TN $monthlyTaskName /F 2>$null | Out-Null

Register-D2GUserTask -TaskName $weeklyTaskName -ScheduleArguments @('/SC', 'WEEKLY', '/D', 'THU', '/ST', '06:00') -RunCommand $taskRunCommand -UserName $credential.UserName -Password $userPassword
Register-D2GUserTask -TaskName $monthlyTaskName -ScheduleArguments @('/SC', 'MONTHLY', '/MO', '1', '/D', '1', '/ST', '05:00') -RunCommand $taskRunCommand -UserName $credential.UserName -Password $userPassword
