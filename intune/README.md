# Intune Scripts

Scripts for managing Windows devices with Intune.

---

## autopilot-enroll

Enroll a device into Intune via Autopilot with phishing-resistant MFA (FIDO2 / YubiKey / Windows Hello for Business).

[Full details](autopilot-enroll.md)

```cmd
powershell -ep bypass -c "irm https://tools.ccittech.solutions/intune/autopilot-enroll.ps1|iex"
```
