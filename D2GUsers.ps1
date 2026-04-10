[CmdletBinding()]
Param()
#$debug = $true
Import-Module ActiveDirectory
$scriptDir = $MyInvocation.MyCommand.Source.Replace($MyInvocation.MyCommand.Name, '')
if (-not (Test-Path "$scriptDir\Reports")) {
	New-Item -ItemType Directory -Path "$scriptDir\Reports" | Out-Null
}

$adDomain = Get-ADDomain
$domain = $adDomain.Name
$domainDistinguishedName = $adDomain.DistinguishedName

$hostnameCustomer = (Hostname).Split('-')[0]
if ($hostnameCustomer -like "template") {
	Exit
}

$ipv4Addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
	Select-Object -ExpandProperty IPAddress
$isNewEnvironment = $ipv4Addresses | Where-Object { $_ -match '^10\.24\.' } | Select-Object -First 1

if ($isNewEnvironment) {
	$userSearchBase = "OU=User Accounts,$domainDistinguishedName"
	$emailCustomer = $hostnameCustomer
} else {
	$userSearchBase = "OU=customers,$domainDistinguishedName"
	$emailCustomer = $domain
}

$fileDate = Get-Date -Format "yyyy-MM-dd"
$fileName = "$scriptDir\Reports\Users-$hostnameCustomer-$fileDate.csv"
$healthCheckHostName = 'hc.desktops2go.net'
$healthCheckUrl = "https://$healthCheckHostName/ping/desktops2go/d2g-users-$($emailCustomer.ToLower())"
$hostsFilePath = 'C:\Windows\System32\drivers\etc\hosts'

try {
	$healthCheckIpAddress = Resolve-DnsName -Name $healthCheckHostName -Server '8.8.8.8' -Type A -ErrorAction Stop |
		Select-Object -ExpandProperty IPAddress -First 1
	$hostsFileLines = if (Test-Path $hostsFilePath) { Get-Content -Path $hostsFilePath } else { @() }
	$existingHealthCheckEntry = $hostsFileLines | Where-Object { $_ -match "^\s*$([regex]::Escape($healthCheckIpAddress))\s+$([regex]::Escape($healthCheckHostName))(\s+.*)?$" }

	if (-not $existingHealthCheckEntry) {
		$updatedHostsFileLines = $hostsFileLines | Where-Object { $_ -notmatch "(?i)(^|\s)$([regex]::Escape($healthCheckHostName))(\s|$)" }
		$updatedHostsFileLines += "$healthCheckIpAddress`t$healthCheckHostName"
		Set-Content -Path $hostsFilePath -Value $updatedHostsFileLines
	}
}
catch {
	Write-Warning "Unable to update hosts file entry for ${healthCheckHostName}: $($_.Exception.Message)"
}

function Get-OldEnvironmentOuInfo {
	param(
		[string]$DistinguishedName
	)

	$distinguishedNameParts = $DistinguishedName -split '(?<!\\),'
	$organizationalUnits = @(
		$distinguishedNameParts |
		Where-Object { $_ -like 'OU=*' } |
		ForEach-Object { $_.Substring(3).Replace('\,', ',').Replace('\\', '\') }
	)
	$customersIndex = [Array]::IndexOf($organizationalUnits, 'Customers')

	if ($customersIndex -le 0) {
		return [PSCustomObject]@{
			Company = $hostnameCustomer
			Subfolder = ''
		}
	}

	return [PSCustomObject]@{
		Company = $organizationalUnits[$customersIndex - 1]
		Subfolder = if ($customersIndex -ge 2) { $organizationalUnits[0] } else { '' }
	}
}

if ($debug -ne $true -and (Test-Path c:\ISTools\DemoAudit.ps1)) {
	#This calls the demo audit script, which disables inactive demo accounts.
	Write-Progress -Status "Checking for inactive demo accounts" -Activity "Preliminary Checks" -PercentComplete -1
	& c:\ISTools\DemoAudit.ps1
	Start-Sleep -Seconds 5
}


## New report - looks for SPLA groups
$groupIndex = 0
$spla = @()
$splaIndex = @{}
$groups = Get-ADGroup -SearchBase "OU=Licensing Security Groups,$domainDistinguishedName" -Filter *
$splaGroupNames = @()
foreach ($group in $groups) {
	$splaGroupNames += $group.Name
	Write-Progress -Status "$($group.Name)" -Activity "Enumerating SPLA License Groups" -PercentComplete -1
	$members = @()
	Get-ADGroupMember -Recursive $group | ForEach-Object { $members += $_.DistinguishedName }
	$spla += ,$members
	$splaIndex.Add($group.Name, $groupIndex)
	$groupIndex++
}
$splaGroups = $splaGroupNames | Sort-Object -Unique

$admins = Get-ADGroupMember 'Domain Admins' | Select-Object -ExpandProperty DistinguishedName
Write-Progress -Status "Please Wait..." -Activity "Gathering the list of users" -PercentComplete -1
$output = @()
$users = Get-ADUser -SearchBase $userSearchBase -Properties DisplayName, Company, Department, DistinguishedName -Filter { Enabled -eq $true } | Sort-Object Company, DisplayName
foreach ($user in $users) {

	if ($admins -contains ($user.DistinguishedName)) {
		#Skiping Domain Admin.
	} else {
		if ($isNewEnvironment) {
			$companyName = $hostnameCustomer
			$subfolderName = ''
		} else {
			$ouInfo = Get-OldEnvironmentOuInfo -DistinguishedName $user.DistinguishedName
			$companyName = $ouInfo.Company
			$subfolderName = $ouInfo.Subfolder
		}

		Write-Progress -Status $user.Name -Activity "$emailCustomer " -PercentComplete -1
		$userReport = New-Object PSObject
		$userReport | Add-Member -Type NoteProperty -Name "Domain" -Value $domain
		$userReport | Add-Member -Type NoteProperty -Name "Name" -Value $user.DisplayName
		$userReport | Add-Member -Type NoteProperty -Name "Company" -Value $companyName
		$userReport | Add-Member -Type NoteProperty -Name "Subfolder" -Value $subfolderName
		$userReport | Add-Member -Type NoteProperty -Name "Type" -Value ''
		$userReport | Add-Member -Type NoteProperty -Name "Notes" -Value ''
		foreach ($splaGroupName in $splaGroups) {
			$userReport | Add-Member -Type NoteProperty -Name "$splaGroupName" -Value ''
		}
		$serviceLevels = 0
		$demoTestOrService = 0
		$office = 0
		$desktop = 0
		Write-Progress -Status "$($user.Name) ." -Activity "$emailCustomer " -PercentComplete -1
		foreach ($splaIndexEntry in $splaIndex.GetEnumerator()) {
			$shortName = $splaIndexEntry.Name
			if (($spla[$splaIndexEntry.Value]) -contains $user.DistinguishedName) {
				$userReport.($shortName) = 1
				if ($shortName -like "ServiceLevel*")
				{
					$userReport.Type += $shortName.Replace('ServiceLevel - ', '')
					$serviceLevels++
				}
				if ($shortName -like "SPLA - Office*")
				{
					$office++
				}
				if ($shortName -like "*demo*")
				{
					$demoTestOrService++
				}
				if ($shortName -like "*test*")
				{
					$demoTestOrService++
				}
				if ($shortName -like "*service account*")
				{
					$demoTestOrService++
				}
				if ($shortName -like "*Desktops2Go Basic*" -or $shortName -like "*Desktops2Go Standard*" -or $shortName -like "*Desktops2Go Premium*" -or $shortName -like "*Desktops2Go Extreme*" -or $shortName -like "*Desktops2Go VDI*")
				{
					$desktop++
				}
			}
		}
		if ($serviceLevels -ne 1) {
			$userReport.Notes += "Service Level Error. "
		}
		if ($demoTestOrService -gt 0 -and $office -gt 0) {
			$userReport.Notes += "Service/Test/Demo Account has Office."
		}
		if ($desktop -gt 0 -and $office -lt 1) {
			$userReport.Notes += "Full Desktop Account has No Office."
		}

		Write-Progress -Status "$($user.Name) .." -Activity "$emailCustomer " -PercentComplete -1
		$output += $userReport
	}
}
Write-Progress -Status "Sorting..." -Activity "Finishing Up" -PercentComplete -1
$output = $output | Sort-Object Company,Name

Write-Progress -Status "Writing CSV Report" -Activity "Finishing Up" -PercentComplete -1
$output | Export-Csv $fileName -NoTypeInformation


$mailServer = (Resolve-DnsName -Type MX nettek.com).NameExchange | Sort-Object | Select-Object -First 1

$recipients = @("purchasing@nettek.com", "dabrames@nettek.com", "jalmeter@nettek.com")
Start-Sleep -Seconds 3
if ($debug -eq $true) {
	$recipients = @("dabrames@nettek.com")
}

$allEmailsSent = $true
foreach ($recipient in $recipients) {
	Write-Progress -Status "Sending Email to $recipient" -Activity "Finishing Up" -PercentComplete -1
	try {
		Send-MailMessage -Attachments $fileName -From Administrator@nettek.com -SmtpServer $mailServer -To $recipient -Subject "Desktops2Go Users - $emailCustomer" -ErrorAction Stop
	}
	catch {
		$allEmailsSent = $false
		Write-Error "Failed to send email to $recipient via ${mailServer}: $($_.Exception.Message)"
	}
	Start-Sleep -Seconds 2
}

if ($allEmailsSent) {
	try {
		Invoke-RestMethod -Uri $healthCheckUrl -Method Get -ErrorAction Stop | Out-Null
	}
	catch {
		Write-Error "Failed to invoke health check URL ${healthCheckUrl}: $($_.Exception.Message)"
	}
}
