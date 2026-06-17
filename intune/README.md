# Intune Scripts

One-liners for use during Windows OOBE — press `Shift+F10` at the network screen to open an elevated Command Prompt, then run the relevant command below.

| Script | Description | One-liner |
|---|---|---|
| [autopilot-enroll.ps1](autopilot-enroll.ps1) | Enroll a device into Intune via Autopilot with phishing-resistant MFA (FIDO2 / YubiKey / WHfB) | See below |

```cmd
powershell -ep bypass -c "irm https://tools.ccittech.solutions/intune/autopilot-enroll.ps1|iex"
```

> Logs are written to `C:\Windows\Temp\IntuneBootstrap-<timestamp>.log`

For full details on each script see its dedicated doc file linked in the table above.
