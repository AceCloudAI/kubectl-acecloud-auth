# Installer for the AceCloud kubectl auth plugin (Windows).
#
#   irm https://raw.githubusercontent.com/AceCloudAI/kubectl-acecloud-auth/main/install.ps1 | iex
#
# Optional: set $env:VERSION to pin a release (e.g. "v1.2.3").

$ErrorActionPreference = "Stop"

$Repo   = "AceCloudAI/kubectl-acecloud-auth"
$Binary = "kubectl-acecloud_auth.exe"

# Resolve version
$Version = $env:VERSION
if (-not $Version) {
    Write-Host "==> Looking up latest release..."
    $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    $Version = $rel.tag_name
}
Write-Host "==> Installing $Binary $Version for windows/amd64"

$Asset = "kubectl-acecloud_auth-windows-amd64.exe"
$Url   = "https://github.com/$Repo/releases/download/$Version/$Asset"

# Install into %LOCALAPPDATA%\acecloud\bin
$InstallDir = Join-Path $env:LOCALAPPDATA "acecloud\bin"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$Dest = Join-Path $InstallDir $Binary

Write-Host "==> Downloading $Asset..."
Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Dest

# Verify checksum if available
try {
    $sums = (Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/releases/download/$Version/checksums.txt").Content
    $expected = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($Asset) }) -split '\s+' | Select-Object -First 1
    if ($expected) {
        $actual = (Get-FileHash -Algorithm SHA256 $Dest).Hash.ToLower()
        if ($expected -ne $actual) { throw "checksum mismatch — aborting" }
        Write-Host "==> Checksum verified"
    }
} catch { Write-Host "==> Skipping checksum verification" }

# Add install dir to the persistent user PATH if missing
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
    Write-Host "==> Added $InstallDir to your PATH"
}
# Also update THIS session so verification works without restarting the shell
if ($env:Path -notlike "*$InstallDir*") {
    $env:Path = "$env:Path;$InstallDir"
}

Write-Host "==> Installed to $Dest"
Write-Host ""
Write-Host "Verify with:  kubectl acecloud_auth version"
Write-Host "(New terminals pick up the PATH change automatically.)"
