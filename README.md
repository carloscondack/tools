# Intune Autopilot Bootstrap (Phishing Resistant MFA)

This repository contains a bootstrap script designed to streamline the manual Intune enrollment of Windows devices in enterprise environments that enforce **Phishing Resistant MFA** (FIDO2 Security Keys, YubiKeys, Windows Hello for Business).

## The Problem
In high-security tenants, standard PowerShell-based enrollment methods often fail:
* **Legacy PowerShell (v5.1)** uses older web components (IE-based) for authentication popups.
* These legacy components often **cannot interface with hardware security keys (FIDO2)** or pass strict Conditional Access policies.
* Technicians are frequently unable to authenticate during the OOBE (Out of Box Experience) setup.

## The Solution
This script automates the transition to a modern authentication stack by:
1. **Downloading and installing PowerShell 7 (Core)** on the fly.
2. **Verifying integrity:** Downloads the official `.sha256` checksum file published by the PowerShell team alongside every release and hard-fails if the hashes don't match.
3. **Handing off** the enrollment process to PowerShell 7, which natively supports modern web authentication (including FIDO2/YubiKeys).

## System Requirements

* Windows 10 1809+ or Windows 11
* Windows PowerShell 5.1 (built-in)
* **Administrator privileges** (required for PowerShell 7 installation and PSGallery access)
* Internet access to:
  * `api.github.com` and `objects.githubusercontent.com` (PowerShell 7 download)
  * `www.powershellgallery.com` (Autopilot script)

## Usage (OOBE)

Perform these steps on a fresh Windows device during the initial setup screen.

1. Boot the device and proceed until you reach the **Wi-Fi / Network selection screen**.
2. **Connect to the internet** (Wi-Fi or Ethernet).
3. Press **`Shift + F10`** to open a Command Prompt (it opens as Administrator).
4. Run the following one-liner:

```cmd
powershell -ep bypass -c "irm https://tools.ccittech.solutions/intune/autopilot-enroll.ps1|iex"
```

A transcript log is written to `C:\Windows\Temp\IntuneBootstrap-<timestamp>.log` for troubleshooting.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| "must be run as Administrator" | Shell not elevated | Ensure you opened CMD via `Shift+F10` during OOBE, or right-click → Run as administrator |
| "Could not locate SHA256 checksum asset" | GitHub API rate limit or transient error | Wait 60 seconds and retry |
| "pwsh.exe not found" after install | Disk full or prior failed install left registry state | Check `C:\Windows\Temp\IntuneBootstrap-*.log` for the msiexec error |
| Browser window doesn't open for auth | WebView2 Runtime missing on thin/custom image | Install WebView2 Runtime manually before running the script |
| `Invoke-WebRequest` timeout | Slow or metered OOBE network | Connect to a faster network and retry |

## Under the Hood

This script acts as a wrapper to execute the **official Microsoft Hardware ID upload process** in a modern authentication environment.

It follows the guidelines listed in Microsoft's documentation: [**Manually register devices with Windows Autopilot**](https://learn.microsoft.com/en-us/autopilot/add-devices).

Once PowerShell 7 is installed, the script executes the following standard commands inside the secure session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
Install-Script -Name Get-WindowsAutopilotInfo -Force
Get-WindowsAutopilotInfo -Online
```
