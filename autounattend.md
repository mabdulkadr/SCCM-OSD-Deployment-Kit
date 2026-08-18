# 🚀 autounattend.xml (Windows Unattend Answer File)

![Platform](https://img.shields.io/badge/Platform-Windows%20Setup-lightgrey.svg)
![Pass](https://img.shields.io/badge/Passes-specialize%20%2B%20oobeSystem-blue.svg)
![OS](https://img.shields.io/badge/OS-Windows%2011-0078D6.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

---

## 📖 Overview

**autounattend.xml** is a Windows Setup **answer file** that automates the Out-Of-Box Experience (OOBE) during Windows 11 deployment.

Without this file, Windows 11 Setup presents multiple interactive screens — EULA acceptance, Microsoft account sign-in, network setup, OEM registration, wireless setup — that must be clicked through manually before the task sequence can proceed. On a zero-touch SCCM deployment, there's no one sitting at the machine to click these screens.

### SCCM Package Context

This file is part of the **SCCM-OSD-Deployment-Kit** package (Package ID: `QU100100`). The package contains all scripts and files used during OSD:

| File | Purpose |
|------|---------|
| `autounattend.xml` | Windows Setup answer file |
| `Start-DeploymentWizard.ps1` | WPF wizard entry point |
| `DeploymentWizard.ps1` | WPF wizard application |
| `Remove-StaleADComputer.ps1` | Stale AD object cleanup |
| `Schedule-PostOSD-Enrollment.ps1` | Post-OSD retry scheduler |

The file is linked in the **"Apply Operating System Image"** Task Sequence step, which applies it during image injection — before the first boot.

This file applies settings at **two points** in the Windows Setup lifecycle:

| Pass | Timing | Purpose |
|------|--------|---------|
| **specialize** | Runs before OOBE, during system configuration | Injects the `BypassNRO` registry key that **removes the Windows 11 network requirement** |
| **oobeSystem** | Runs during the OOBE phase (the user setup screens) | Hides EULA, OEM registration, Microsoft account, and wireless setup screens |

The complete XML:

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

## ✨ Core Features — Detailed Pass Walkthrough

### 🔹 specialize Pass — Windows 11 Network Bypass

**The problem:** Starting with Windows 11 22H2, Microsoft requires a network connection **and** a Microsoft account to complete OOBE. On a domain-joined enterprise deployment, there's no Microsoft account to sign in with, and the machine may not have internet access during imaging.

**What the specialize pass does:**

During the specialize pass, Windows runs synchronous commands defined in the `<RunSynchronous>` block. This file runs a single command:

```
cmd /c reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f
```

This writes a `DWORD` value `1` to the registry key `BypassNRO` **before** the OOBE screens begin loading.

**Effect:** When OOBE initializes, it reads this key. `BypassNRO = 1` tells Windows: "Do not require network (NRO = Network Requirement Option)." The "Let's connect you to a network" screen is **skipped entirely**. The user can proceed without internet, and crucially, can create a local account or proceed to domain join without a Microsoft account.

**Technical detail — why the specialize pass:**
- The specialize pass runs **after** the Windows image is applied but **before** OOBE
- Registry writes here persist through to OOBE
- The command is `<RunSynchronous>` — it runs and completes **before** the next phase starts
- The `/f` flag forces the write even if the key already exists (idempotent)

### 🔹 oobeSystem Pass — Hidden OOBE Screens

This pass configures `Microsoft-Windows-Shell-Setup\OOBE` to hide five standard OOBE pages:

| Setting | Value | Screen Hidden | Why |
|---------|-------|--------------|-----|
| `HideEULAPage` | `true` | "Please read the license terms" | EULA is accepted by the organization's licensing agreement, not per-machine |
| `HideOEMRegistrationScreen` | `true` | "Register your copy of Windows" | No OEM registration needed for volume-licensed enterprise deployments |
| `HideOnlineAccountScreens` | `true` | "Sign in with Microsoft" | Enterprise deployments use domain accounts, not Microsoft accounts |
| `HideWirelessSetupInOOBE` | `true` | "Let's connect you to a network" | Wireless setup is handled by group policy or SCCM after deployment |
| `ProtectYourPC` | `3` | Automatic Windows Update recommendations | `3` = "Use recommended settings" (install updates automatically) |

**Effect of hiding these screens:** After Windows boots for the first time, OOBE completes instantly with zero user interaction. The machine goes straight to the desktop (or, in the SCCM OSD case, straight to the task sequence configuration manager step).

---

## ⚙️ Requirements

| Requirement | Notes |
|-------------|-------|
| Windows 11 installation media/WIM | The file must be accessible to Windows Setup at the root of the media |
| amd64 architecture | Applies to standard x64 deployments (add an x86 variant for 32-bit) |
| SCCM/MDT/standalone media | Works with any Windows deployment method that uses `setup.exe` or boot images |

---

## 🚀 How to Use

### Option 1 — Installation Media Root (SCCM Boot Media, USB)

Place the file in the **root** of your Windows installation media:

```
D:\                           ← USB drive or mounted ISO / WIM root
├── autounattend.xml          ← HERE — Windows Setup auto-discovers this
├── sources\
│   ├── boot.wim
│   └── install.wim
├── boot\
└── efi\
```

Windows Setup (`setup.exe`) automatically searches the media root for this file. No command-line parameter needed.

### Option 2 — SCCM Task Sequence

**Method A — Inject into the boot image:**
1. Mount your boot WIM: `dism /Mount-Image /ImageFile:boot.wim /Index:1 /MountDir:C:\mount`
2. Copy `autounattend.xml` to `C:\mount\Windows\`
3. Unmount: `dism /Unmount-Image /MountDir:C:\mount /Commit`
4. Update distribution points in the SCCM console

**Method B — Use an SCCM package:**
1. Create an SCCM package containing `autounattend.xml`
2. Add a **Run Command Line** step early in your task sequence:
   ```
   cmd /c copy ".\autounattend.xml" "C:\Windows\System32\Sysprep\"
   ```
   (The Sysprep folder is an alternate location Windows Setup checks)

**Method C — Reference in the TS "Apply Operating System" step (Recommended):**

In the SCCM TS step **"Apply Operating System Image"**, there's an option to specify an unattend or sysprep answer file. Browse to your `autounattend.xml` from the SCCM package.

**How it works in the Task Sequence:**

```
Apply Operating System Image (TS Step)
    │
    ├── Image: install.wim (from SCCM package QU100100_SCCM-OSD-Deployment-Kit 1.0)
    ├── File name: autounattend.xml ← linked from the same package
    │
    └── During execution:
        1. SCCM applies the Windows image to the disk
        2. autounattend.xml is injected into the offline image
        3. On first boot, Windows Setup reads the answer file
        4. specialize pass → BypassNRO registry key (removes network requirement)
        5. oobeSystem pass → hides EULA, Microsoft account, wireless setup screens
        6. OOBE completes instantly → Task Sequence continues
```

This is the **recommended method** because:
- The answer file travels with the OS image in the same SCCM package
- No extra steps needed in the Task Sequence
- SCCM handles distribution to all Distribution Points automatically
- The file is applied during image injection — before the first boot

### Option 3 — MDT / Standalone

```powershell
# MDT: place in the Scripts folder of your deployment share
# Standalone: inject using DISM into the offline image
dism /Image:C:\mount\ /Apply-Unattend:autounattend.xml
```

---

## 🔄 How It Works — Full Windows Setup Lifecycle

```
1. Machine boots from media / PXE
   └─ Windows Setup (setup.exe) starts
   └─ Setup discovers autounattend.xml at the media root

2. Windows PE phase
   └─ Disk partitioning, image apply
   └─ autounattend.xml is parsed

3. Apply Operating System Image (SCCM TS Step)
   └─ SCCM applies install.wim to the disk
   └─ autounattend.xml is linked from the SCCM package
   └─ File is injected into the offline image before first boot

4. Specialize pass (system configuration)
   └─ <settings pass="specialize"> runs
   └─ <RunSynchronous> executes:
   └─ "reg add ... BypassNRO /d 1 /f" → registry key written
   └─ Windows now knows: "Don't force a network connection"

5. Machine reboots into Windows (first boot)

6. oobeSystem pass (user experience setup)
   └─ <settings pass="oobeSystem"> applies
   └─ OOBE checks: HideEULAPage = true? → Skip license screen
   └─ OOBE checks: HideOnlineAccountScreens = true? → Skip Microsoft sign-in
   └─ OOBE checks: HideWirelessSetupInOOBE = true? → Skip Wi-Fi setup
   └─ OOBE completes instantly → desktop (or SCCM TS config manager)

7. SCCM Task Sequence continues (if in OSD)
   └─ Domain join, app installs, deployment wizard, enrollment
```

**Critical:** The specialize pass runs **after** the image is applied to the disk. If you modify this file, you don't need to rebuild the WIM — just update the file and the next deployment uses the new settings.

---

## 📊 Operational Safeguards

- ✅ **Idempotent registry write** — uses `/f` (force) flag. Running multiple times is safe.
- ✅ **Architecture-specific** — `processorArchitecture="amd64"` ensures it only applies to x64 machines. No conflict with x86 media.
- ✅ **No reboot between passes** — specialize → oobeSystem flows automatically. No extra reboot needed.
- ✅ **Registry key survives Sysprep** — written in the specialize pass, persists through OOBE and first logon.
- ✅ **Auto-discovery** — Windows Setup finds the file automatically at the media root. No command-line parameter or script needed.

---

## 🐛 Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| **Network prompt still appears** | `autounattend.xml` is not at the media root | Place the file in the ROOT of the installation media (not inside `sources\`, not inside `Windows\`). |
| **OOBE still shows EULA** | `oobeSystem` pass not included or malformed | Verify the XML is well-formed. Check: `HideEULAPage` is a child of `<OOBE>`, which is a child of `<component>` under `<settings pass="oobeSystem">`. |
| **"Apply errors" in setupact.log** | Invalid or malformed XML | Validate against the Windows Unattend schema: open in Windows System Image Manager (SIM) and check for errors. A missing closing tag or namespace will break it. |
| **Only works on 64-bit media** | `processorArchitecture="amd64"` setting | If you need 32-bit support, add an identical component with `processorArchitecture="x86"`. For most deployments, amd64 is sufficient. |
| **BypassNRO had no effect** | Registry key was applied too late | The command must run in the **specialize** pass. Running it in oobeSystem is too late — OOBE has already checked for network requirements by then. |
| **File not found by Setup** | File must be named exactly `autounattend.xml` | Case-sensitive on some media formats. Verify the exact filename: `autounattend.xml` (lowercase 'a' is typically fine, but exact match is safest). |

---

## 🎯 SCCM Integration Checklist

### Recommended: Apply Operating System Image Step

1. **Create SCCM Package** — create a package containing `autounattend.xml` from the `SCCM-OSD-Deployment-Kit` folder
2. **Distribute to DPs** — distribute the package to all Distribution Points
3. **Link in TS Step** — in your Task Sequence, edit the **"Apply Operating System Image"** step:
   - Browse to the package containing `autounattend.xml`
   - Set **File name** to `autounattend.xml`
4. **Test on a VM** — deploy to a Hyper-V VM before rolling out to physical devices. Verify OOBE completes without prompts.
5. **No conflicts with other unattend files** — if your task sequence also specifies an unattend file in the "Apply Operating System" step, ensure they don't conflict. The specialize pass from this file + a separate oobeSystem file is a common configuration.

### Alternative Methods

| Method | When to Use |
|--------|-------------|
| **Inject into boot image** | When you want the file available in WinPE (before disk partitioning) |
| **SCCM Package + Run Command Line** | When you need to copy the file to a specific location during the TS |
| **MDT / Standalone** | When deploying outside SCCM (USB media, standalone setup) |

---

## 🛡 Design Principles

- **Minimal** — contains only the settings required for zero-touch OSD. No product key, no language packs, no disk layout — those are handled by the SCCM task sequence.
- **Pass-correct** — specialize pass for system configuration, oobeSystem pass for user experience. The timing is correct.
- **Org-agnostic** — no organization name, no branding, no domain-specific settings. This file works for any Windows 11 deployment.
- **Standalone** — works without SCCM. Can be placed on a USB stick for standalone Windows 11 installs.

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).

---

## 👤 Author

**Mohammad Abdulkader Omar**
Website: https://momar.tech
LinkedIn: https://www.linkedin.com/in/mabdulkadr/

---

## ⚠ Disclaimer

These scripts are provided as-is. Test them in a staging environment before applying them to production. The author is not responsible for any unintended outcomes resulting from their use.
