[CmdletBinding()]
Param()

$userPassword = "password"
$ownerName = 'DuaneAbrames'
$repositoryName = 'D2G-Reports'
$releaseApiUrl = "https://api.github.com/repos/$ownerName/$repositoryName/releases/latest"
$installDirectory = 'C:\ISTools'
$updaterScriptName = 'Update-And-Run-D2GUsers.ps1'
$scheduledTaskName = 'D2G User Reports'

Import-Module ScheduledTasks
Import-Module ActiveDirectory

$adDomain = Get-ADDomain
$administratorUserName = "$($adDomain.NetBIOSName)\Administrator"
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
	$tasksToRemove = Get-ScheduledTask | Where-Object {
		foreach ($taskAction in $_.Actions) {
			if ($null -ne $taskAction.Arguments -and $taskAction.Arguments -match '(?i)d2gusers\.ps1') {
				return $true
			}
		}

		return $false
	}

	foreach ($task in $tasksToRemove) {
		Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false
	}
}

Remove-LegacyD2GUserTasks

$releaseTag = Get-LatestReleaseTag -ApiUrl $releaseApiUrl
$updaterDownloadUrl = "https://raw.githubusercontent.com/$ownerName/$repositoryName/$releaseTag/$updaterScriptName"
$updaterScriptPath = Join-Path -Path $installDirectory -ChildPath $updaterScriptName

Invoke-WebRequest -Uri $updaterDownloadUrl -OutFile $updaterScriptPath -Headers @{ 'User-Agent' = 'D2GUsers-Deploy' } -ErrorAction Stop

$taskAction = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$updaterScriptPath`""
$weeklyTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Thursday -At 6:00AM
$monthlyTrigger = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At 5:00AM
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $credential.UserName -LogonType Password -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$taskDefinition = New-ScheduledTask -Action $taskAction -Trigger @($weeklyTrigger, $monthlyTrigger) -Principal $taskPrincipal -Settings $taskSettings

Register-ScheduledTask -TaskName $scheduledTaskName -InputObject $taskDefinition -User $credential.UserName -Password $userPassword -Force
