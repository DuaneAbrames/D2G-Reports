[CmdletBinding()]
Param(
	[Parameter(ValueFromRemainingArguments = $true)]
	[object[]]$ScriptArguments
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptName = 'D2GUsers.ps1'
$downloadFileNames = @(
	'D2GUsers.ps1',
	'DemoAudit.ps1'
)
$sidecarName = 'D2GUsers-version.json'
$ownerName = 'DuaneAbrames'
$repositoryName = 'D2G-Reports'
$releaseApiUrl = "https://api.github.com/repos/$ownerName/$repositoryName/releases/latest"

$scriptPath = Join-Path -Path $scriptDir -ChildPath $scriptName
$sidecarPath = Join-Path -Path $scriptDir -ChildPath $sidecarName

function Get-LocalVersionInfo {
	param(
		[string]$Path
	)

	if (-not (Test-Path $Path)) {
		return $null
	}

	try {
		return Get-Content -Path $Path -Raw | ConvertFrom-Json
	}
	catch {
		Write-Warning "Unable to read version sidecar $Path. The script will redownload the latest release."
		return $null
	}
}

function Save-LocalVersionInfo {
	param(
		[string]$Path,
		[string]$Version
	)

	$versionInfo = [PSCustomObject]@{
		version = $Version
		lastDownloadDate = (Get-Date).ToString('o')
	}

	$versionInfo | ConvertTo-Json | Set-Content -Path $Path
}

function Get-LatestReleaseInfo {
	param(
		[string]$ApiUrl,
		[string]$Owner,
		[string]$Repository
	)

	$release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ 'User-Agent' = 'D2GUsers-Updater' } -ErrorAction Stop
	$tagName = $release.tag_name

	if ([string]::IsNullOrWhiteSpace($tagName)) {
		throw 'Latest release did not include a tag name.'
	}

	return [PSCustomObject]@{
		version = $tagName
		baseDownloadUrl = "https://raw.githubusercontent.com/$Owner/$Repository/$tagName"
	}
}

function Update-ReleaseFile {
	param(
		[string]$DirectoryPath,
		[string]$FileName,
		[string]$BaseDownloadUrl
	)

	$destinationPath = Join-Path -Path $DirectoryPath -ChildPath $FileName
	$temporaryDownloadPath = Join-Path -Path $DirectoryPath -ChildPath "$FileName.download"
	$backupFilePath = Join-Path -Path $DirectoryPath -ChildPath "$FileName.bak"
	$downloadUrl = "$BaseDownloadUrl/$FileName"

	Invoke-WebRequest -Uri $downloadUrl -OutFile $temporaryDownloadPath -Headers @{ 'User-Agent' = 'D2GUsers-Updater' } -ErrorAction Stop

	if (Test-Path $backupFilePath) {
		Remove-Item -Path $backupFilePath -Force
	}

	if (Test-Path $destinationPath) {
		Move-Item -Path $destinationPath -Destination $backupFilePath -Force
	}

	Move-Item -Path $temporaryDownloadPath -Destination $destinationPath -Force
}

$localVersionInfo = Get-LocalVersionInfo -Path $sidecarPath
$shouldDownload = $false

try {
	$latestReleaseInfo = Get-LatestReleaseInfo -ApiUrl $releaseApiUrl -Owner $ownerName -Repository $repositoryName

	if (-not (Test-Path $scriptPath)) {
		$shouldDownload = $true
	}
	elseif ($null -eq $localVersionInfo) {
		$shouldDownload = $true
	}
	elseif ($localVersionInfo.version -ne $latestReleaseInfo.version) {
		$shouldDownload = $true
	}

	if ($shouldDownload) {
		Write-Host "Downloading release version $($latestReleaseInfo.version)..."
		foreach ($downloadFileName in $downloadFileNames) {
			Update-ReleaseFile -DirectoryPath $scriptDir -FileName $downloadFileName -BaseDownloadUrl $latestReleaseInfo.baseDownloadUrl
		}
		Save-LocalVersionInfo -Path $sidecarPath -Version $latestReleaseInfo.version
	}
}
catch {
	Write-Warning "Update check failed: $($_.Exception.Message)"

	foreach ($downloadFileName in $downloadFileNames) {
		$temporaryDownloadPath = Join-Path -Path $scriptDir -ChildPath "$downloadFileName.download"
		if (Test-Path $temporaryDownloadPath) {
			Remove-Item -Path $temporaryDownloadPath -Force
		}
	}
}

if (-not (Test-Path $scriptPath)) {
	throw "Unable to locate $scriptPath."
}

$launchArguments = @($ScriptArguments | Where-Object { $null -ne $_ })

if ($launchArguments.Count -gt 0) {
	& $scriptPath @launchArguments
} else {
	& $scriptPath
}
