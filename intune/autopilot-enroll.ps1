<#
.SYNOPSIS
    Bootstrap script for Intune Autopilot enrollment via PowerShell 7.

.DESCRIPTION
    Designed to run on Windows PowerShell 5.1 during OOBE. Installs PowerShell 7 if
    absent — downloading the latest MSI from GitHub and verifying its SHA256 integrity
    against the official checksum file published by the PowerShell team — then delegates
    Autopilot enrollment to PS7 so that phishing-resistant MFA (FIDO2 / YubiKey /
    Windows Hello for Business) works correctly.

    Requires administrator rights.
    Writes a transcript to C:\Windows\Temp\IntuneBootstrap-<timestamp>.log.

.NOTES
    Version : 1.2.2
    Ref     : https://learn.microsoft.com/en-us/autopilot/add-devices
#>

$ScriptVersion = '1.2.2'
$ErrorActionPreference = "Stop"

# --- 0. Header ---
Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║       Intune Autopilot Enrollment Bootstrap          ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  v$ScriptVersion  ·  github.com/carloscondack/tools" -ForegroundColor DarkGray
Write-Host ""

# --- 1. Verify Administrator Privileges ---
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "  [!] This script must be run as Administrator." -ForegroundColor Red
    Write-Host "      Re-launch from an elevated prompt." -ForegroundColor Red
    exit 1
}

# --- 2. Logging ---
$LogFile = "C:\Windows\Temp\IntuneBootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $LogFile -Append | Out-Null
Write-Host "  Log : $LogFile" -ForegroundColor DarkGray
Write-Host ""

# --- 3. TLS Setup ---
# Required for GitHub API and PSGallery connectivity on PS 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- 4. Check/Install PowerShell 7 ---
$PwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

if (-not (Test-Path $PwshPath)) {
    Write-Host "  [>] PowerShell 7 not found — fetching latest release info..." -ForegroundColor Cyan

    $TempMsi = $null
    try {
        # Fetch Release Info from GitHub API
        $LatestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -TimeoutSec 30

        # 1. Detect architecture and find the matching MSI asset
        $Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $MsiAsset = $LatestRelease.assets | Where-Object { $_.name -like "*-win-$Arch.msi" } | Select-Object -First 1
        if (-not $MsiAsset) { throw "Could not find $Arch MSI asset in latest release." }

        $SizeMB = [math]::Round($MsiAsset.size / 1MB, 1)
        Write-Host "  [>] Found : $($MsiAsset.name) ($SizeMB MB)" -ForegroundColor Cyan

        # 2. Fetch the official SHA256 checksum file published alongside the MSI.
        #    The PowerShell team ships a consolidated "hashes.sha256" file per release
        #    (not individual per-file checksums) formatted as "<hash>  <filename>" per line.
        $HashAsset = $LatestRelease.assets | Where-Object { $_.name -eq "$($MsiAsset.name).sha256" } | Select-Object -First 1
        if (-not $HashAsset) {
            $HashAsset = $LatestRelease.assets | Where-Object { $_.name -eq 'hashes.sha256' } | Select-Object -First 1
        }
        if ($HashAsset) {
            Write-Host "  [>] Fetching SHA256 checksum..." -ForegroundColor DarkGray
            # Read raw bytes to handle the UTF-16 LE BOM the PowerShell team uses
            $RawBytes = (Invoke-WebRequest -Uri $HashAsset.browser_download_url -TimeoutSec 30 -UseBasicParsing).RawContentStream.ToArray()
            if ($RawBytes.Length -ge 2 -and $RawBytes[0] -eq 0xFF -and $RawBytes[1] -eq 0xFE) {
                $HashFileContent = [System.Text.Encoding]::Unicode.GetString($RawBytes)
            } else {
                $HashFileContent = [System.Text.Encoding]::UTF8.GetString($RawBytes)
            }
            # Split on \r\n or \n; match the MSI filename anywhere on the line (case-insensitive)
            $MsiNamePattern = [regex]::Escape($MsiAsset.name)
            $MatchingLine = ($HashFileContent -split '\r?\n') | Where-Object { $_ -imatch $MsiNamePattern } | Select-Object -First 1
            if (-not $MatchingLine) {
                throw "SHA256 checksum for '$($MsiAsset.name)' not found inside '$($HashAsset.name)'. Aborting."
            }
            $ExpectedHash = ($MatchingLine.Trim() -split '\s+')[0].Trim().ToUpper()
        }
        else {
            throw "Could not locate a SHA256 checksum asset for $($MsiAsset.name). Aborting."
        }

        # 3. Download the MSI
        $TempMsi = "$env:TEMP\$($MsiAsset.name)"
        Write-Host "  [>] Downloading $($MsiAsset.name) ($SizeMB MB)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $MsiAsset.browser_download_url -OutFile $TempMsi -TimeoutSec 120

        # 4. Verify Integrity
        Write-Host "  [>] Verifying SHA256 integrity..." -ForegroundColor Cyan
        $CalculatedHash = (Get-FileHash -Path $TempMsi -Algorithm SHA256).Hash

        if ($CalculatedHash -ne $ExpectedHash) {
            Write-Host "  [!] HASH MISMATCH" -ForegroundColor Red
            Write-Host "      Expected : $ExpectedHash" -ForegroundColor Red
            Write-Host "      Actual   : $CalculatedHash" -ForegroundColor Red
            throw "Security verification failed. The file may be corrupted or tampered with."
        }
        Write-Host "  [OK] Integrity verified." -ForegroundColor Green

        # 5. Install Silently
        Write-Host "  [>] Installing PowerShell 7 — please wait..." -ForegroundColor Cyan
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$TempMsi`" /quiet /norestart" -Wait

        # 6. Verify the binary exists — msiexec /quiet can exit 0 on soft failures
        if (-not (Test-Path $PwshPath)) {
            throw "msiexec completed but pwsh.exe not found at '$PwshPath'. Check logs for msiexec failure."
        }
        Write-Host "  [OK] PowerShell 7 installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host "  [!] Critical failure installing PowerShell 7:" -ForegroundColor Red
        Write-Host "      $_" -ForegroundColor Red
        exit 1
    }
    finally {
        # Always remove the downloaded MSI regardless of success or failure
        if ($TempMsi -and (Test-Path $TempMsi)) {
            Remove-Item -Path $TempMsi -ErrorAction SilentlyContinue
        }
    }
}
else {
    Write-Host "  [OK] PowerShell 7 already installed." -ForegroundColor Green
}

Write-Host ""

# --- 5. Check/Install WebView2 Runtime ---
# Required for PS7's modern authentication browser window (FIDO2/YubiKey/WHfB)
$WebView2RegPaths = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'HKCU:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
)

if ($WebView2RegPaths | Where-Object { Test-Path $_ }) {
    Write-Host "  [OK] WebView2 Runtime already installed." -ForegroundColor Green
} else {
    Write-Host "  [>] WebView2 Runtime not found — installing..." -ForegroundColor Cyan
    $WebView2Installer = "$env:TEMP\MicrosoftEdgeWebView2Setup.exe"
    try {
        Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $WebView2Installer -TimeoutSec 60

        # Verify Authenticode signature — more robust than a hardcoded hash since
        # the bootstrapper updates frequently but is always signed by Microsoft.
        $Sig = Get-AuthenticodeSignature -FilePath $WebView2Installer
        if ($Sig.Status -ne 'Valid') {
            throw "WebView2 installer signature invalid (Status: $($Sig.Status)). Aborting."
        }
        if ($Sig.SignerCertificate.Subject -notmatch 'Microsoft') {
            throw "WebView2 installer is not signed by Microsoft. Aborting."
        }
        Write-Host "  [OK] Signature verified." -ForegroundColor DarkGray

        Start-Process -FilePath $WebView2Installer -ArgumentList '/silent /install' -Wait
        Write-Host "  [OK] WebView2 Runtime installed." -ForegroundColor Green
    }
    finally {
        if (Test-Path $WebView2Installer) { Remove-Item -Path $WebView2Installer -ErrorAction SilentlyContinue }
    }
}

Write-Host ""

# --- 6. Prepare the Autopilot Payload ---
$PayloadFile = "$env:TEMP\IntuneEnrollment.ps1"

# Single-quoted here-string prevents variable expansion in the payload.
$PayloadContent = @'
Write-Host "  [>] Configuring enrollment environment..." -ForegroundColor Cyan
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force

# 1. Install NuGet Provider (Required for Install-Script)
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "  [>] Installing NuGet Provider..." -ForegroundColor Cyan
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
}

# 2. Ensure PSGallery is registered and trusted
if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
    Write-Host "  [>] Registering PSGallery..." -ForegroundColor Cyan
    Register-PSRepository -Default -ErrorAction SilentlyContinue
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# 3. Install or Locate Autopilot Script
$ScriptName = "Get-WindowsAutopilotInfo"
$ScriptInfo = Get-InstalledScript -Name $ScriptName -ErrorAction SilentlyContinue

if (-not $ScriptInfo) {
    Write-Host "  [>] Installing Get-WindowsAutopilotInfo from PSGallery..." -ForegroundColor Cyan
    Install-Script -Name $ScriptName -Force -Scope CurrentUser -Repository PSGallery | Out-Null
    $ScriptInfo = Get-InstalledScript -Name $ScriptName -ErrorAction SilentlyContinue
}

# 3. Execute using the Full Path (Fixes PATH visibility issues)
if ($ScriptInfo) {
    $ScriptPath = "$($ScriptInfo.InstalledLocation)\$ScriptName.ps1"

    Write-Host "  [>] Starting authentication — a browser window will open shortly." -ForegroundColor Yellow

    & $ScriptPath -Online
}
else {
    Write-Host "  [!] Failed to locate the Autopilot script after installation." -ForegroundColor Red
}
'@

Set-Content -Path $PayloadFile -Value $PayloadContent

# --- 7. Handoff to PowerShell 7 ---
Write-Host "  [>] Launching modern auth flow via PowerShell 7..." -ForegroundColor Cyan
Write-Host ""
& $PwshPath -ExecutionPolicy Bypass -File $PayloadFile

# --- 8. Cleanup ---
if (Test-Path $PayloadFile) {
    Remove-Item -Path $PayloadFile -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║               Enrollment Complete                    ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Log saved to: $LogFile" -ForegroundColor DarkGray
Write-Host ""
Stop-Transcript
