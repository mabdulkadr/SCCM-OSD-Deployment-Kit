# 📄 autounattend.xml

A minimal Windows Setup answer file that automates the Out-Of-Box Experience (OOBE) during Windows 11 deployment. Hides EULA, OEM registration, Microsoft account, and wireless setup screens. Bypasses the Windows 11 network requirement.

---

## What It Does

Windows 11 Setup normally shows several interactive screens before letting the user reach the desktop:

- "Please read the license terms" (EULA)
- "Register your copy of Windows" (OEM)
- "Sign in with Microsoft" (Online account)
- "Let's connect you to a network" (Wireless)
- "Choose privacy settings"

For a **zero-touch** enterprise deployment, there's no one sitting at the machine to click through these screens. This answer file hides them all so OOBE completes instantly.

---

## How It's Used

**In SCCM Console:**

1. Open your Task Sequence
2. Find the **Apply Operating System Image** step
3. In the step properties, browse to `autounattend.xml` in your SCCM package
4. Save the step

The file is applied during image injection — before the first boot. Windows Setup reads it automatically.

---

## What Each Pass Does

| Pass | Timing | Effect |
|------|--------|--------|
| **specialize** | Before OOBE (during system configuration) | Sets `BypassNRO = 1` registry key — removes Windows 11 network requirement |
| **oobeSystem** | During OOBE (user experience setup) | Hides EULA, OEM registration, Microsoft account, and wireless setup screens |

---

## XML

```xml
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="specialize">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>cmd /c reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" ^
                        /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                    <Description>Bypass Windows 11 Network Requirement</Description>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
        </component>
    </settings>
</unattend>
```

---

## Setup Lifecycle

```
1. SCCM applies install.wim to disk
2. autounattend.xml is injected (via the Apply OS Image step)
3. First boot → specialize pass runs → BypassNRO registry key written
4. OOBE starts → all screens hidden → completes instantly
5. Task Sequence continues (domain join, applications, etc.)
```

---

## Settings Reference

| Setting | Value | What It Hides |
|---------|-------|---------------|
| `HideEULAPage` | `true` | License terms screen |
| `HideOEMRegistrationScreen` | `true` | OEM registration screen |
| `HideOnlineAccountScreens` | `true` | Microsoft account sign-in screens |
| `HideWirelessSetupInOOBE` | `true` | Network connection screen |
| `ProtectYourPC` | `3` | "Use recommended settings" for Windows Update |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Network prompt still appears | File not linked in the TS step, or not at the media root |
| OOBE still shows EULA | XML is malformed — verify with Windows System Image Manager (SIM) |
| `BypassNRO` had no effect | Must be in the `specialize` pass, not `oobeSystem` |
| File not found by Setup | Filename must be exactly `autounattend.xml` |

---

## Notes

- This file is **architecture-specific** (`amd64`) — add an x86 variant if needed
- The `BypassNRO` command uses `/f` for idempotency (safe to run multiple times)
- This file is **org-agnostic** — works for any Windows 11 deployment without modification
