$downloadPath = "C:\advnetsol\softwarepatches"
$nppInstallPath = "${env:ProgramFiles}\Notepad++"
$apiUrl = "https://api.github.com/repos/notepad-plus-plus/notepad-plus-plus/releases/latest"
----------------------------------------------------------------------------------------------Line of Shame Do not touch anything below------------------------------------------------------
# Create if doesnt exist
if (-not (Test-Path $downloadPath)) {
    New-Item -ItemType Directory -Path $downloadPath -Force
}

function Get-InstalledNppVersion {
    if (Test-Path "$nppInstallPath\notepad++.exe") {
        $version = (Get-Item "$nppInstallPath\notepad++.exe").VersionInfo.FileVersion
        return $version.Trim()
    }
    return $null
}

function Get-LatestNppVersion {
    try {
        $latestRelease = Invoke-RestMethod -Uri $apiUrl
        $version = $latestRelease.tag_name.Replace('v', '')
        $downloadUrl = ($latestRelease.assets | Where-Object { $_.name -like '*x64.exe' }).browser_download_url
        return @{
            Version = $version
            Url = $downloadUrl
        }
    }
    catch {
        return "Failed to get latest version: $_"
        exit 1
    }
}

function Install-Npp {
    param ($downloadUrl)
    
    $installer = Join-Path $downloadPath "npp_installer.exe"
    
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installer
        Start-Process -FilePath $installer -ArgumentList "/S" -Wait
        Remove-Item $installer -Force
    }
    catch {
        return "Installation failed: $_"
        exit 1
    }
}

# Main script
$currentVersion = Get-InstalledNppVersion
$latest = Get-LatestNppVersion

if ($null -eq $currentVersion) {
    Install-Npp -downloadUrl $latest.Url
    return "Notepad++ was not installed. Installed version $($latest.Version)"
}
elseif ($currentVersion -ne $latest.Version) {
    Install-Npp -downloadUrl $latest.Url
    return "Updated Notepad++ from $currentVersion to $($latest.Version)"
}
else {
    return "No update needed - current version: $currentVersion"
}
