[CmdletBinding()]
Param()

Import-Module ActiveDirectory
$now = Get-Date -Format d

$disabledUsers = @()
$warningUsers = @()

$searchBase = "ou=customers,$((Get-ADDomain).DistinguishedName)"


$disableDays = 31
$warningDays = 30
$demoUsers = @(Get-ADGroupMember 'ServiceLevel - Demo Account' -Recursive | Get-ADUser)
$demoUsers += Get-ADUser -SearchBase $searchBase -Properties DisplayName, Company, Department, LastLogonTimestamp, WhenCreated -Filter { Enabled -eq $true } | Where-Object { ($_.Company -like "Demo*") -or ($_.DisplayName -like "*demo*") }
foreach ($demoUser in $demoUsers) {
	if ($null -eq $demoUser.LastLogonTimestamp)
	{
		Write-Verbose "$($demoUser.DisplayName) has never logged in."
		#creation time is returned as a dateTime.
		$lastLogonTime = $demoUser.WhenCreated
	}
	else {
		# logon time is in a different format, so 1600 years off.
		$lastLogonTime = $([datetime]$demoUser.LastLogonTimestamp).AddYears(1600).ToLocalTime()
	}
	if ($lastLogonTime -lt $((Get-Date).AddDays(-$disableDays))) {
		Write-Verbose "$($demoUser.DisplayName) has not logged in in over $disableDays days, disabling account."
		Set-ADUser $demoUser -Enabled $false -Description "Auto-Disabled by script on $now - last login $lastLogonTime"
		$disabledUsers += $demoUser
	}
	else
	{
		if ($lastLogonTime -lt $((Get-Date).AddDays(-$warningDays))) {
			Write-Verbose "$($demoUser.DisplayName) has not logged in in over $warningDays days, not disabling account YET."
			#here would go code to email a warning...
			$warningUsers += $demoUser
		}
		else
	{
		if ($lastLogonTime -ge $((Get-Date).AddDays(-$warningDays))) {
			Write-Verbose "$($demoUser.DisplayName) HAS logged in in the last $warningDays days."

		}
	}
	}
}

$disableDays = 7
$warningDays = 6
$testGroupMembers = Get-ADGroupMember 'ServiceLevel - Test Account' -Recursive
foreach ($testGroupMember in $testGroupMembers) {
	$testUser = Get-ADUser $testGroupMember -Properties DisplayName, LastLogonTimestamp, WhenCreated
	if ($null -eq $testUser.LastLogonTimestamp)
	{
		Write-Verbose "$($testUser.DisplayName) has never logged in."
		#creation time is returned as a dateTime.
		$lastLogonTime = $testUser.WhenCreated
	}
	else {
		# logon time is in a different format, so 1600 years off.
		$lastLogonTime = $([datetime]$testUser.LastLogonTimestamp).AddYears(1600).ToLocalTime()
	}
	if ($lastLogonTime -lt $((Get-Date).AddDays(-$disableDays))) {
		Write-Verbose "$($testUser.DisplayName) has not logged in in over $disableDays days, disabling account."
		Set-ADUser $testUser -Enabled $false -Description "Auto-Disabled by script on $now - last login $lastLogonTime"
		$disabledUsers += $testUser
	}
	else
	{
		if ($lastLogonTime -lt $((Get-Date).AddDays(-$warningDays))) {
			Write-Verbose "$($testUser.DisplayName) has not logged in in over $warningDays days, not disabling account YET."
			#here would go code to email a warning...
			$warningUsers += $testUser
		}
		else
	{
		if ($lastLogonTime -ge $((Get-Date).AddDays(-$warningDays))) {
			Write-Verbose "$($testUser.DisplayName) HAS logged in in the last $warningDays days."

		}
	}
	}
}


if ($disabledUsers) {
	Write-Host "======== Disabled ========="
	$disabledUsers | Format-Table DisplayName -HideTableHeaders
}
if ($warningUsers) {
	Write-Host "======== Warning ========="
	$warningUsers | Format-Table DisplayName -HideTableHeaders
}
