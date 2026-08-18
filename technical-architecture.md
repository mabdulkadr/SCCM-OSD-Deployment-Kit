# 📐 SCCM OSD Deployment Kit — Technical Architecture

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-WinPE%20%2B%20Full%20OS-lightgrey.svg)
![GUI](https://img.shields.io/badge/GUI-WPF-purple.svg)
![LDAP](https://img.shields.io/badge/LDAP-.NET%20LdapConnection-orange.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

---

## 🧭 Table of Contents

- [📐 SCCM OSD Deployment Kit — Technical Architecture](#-sccm-osd-deployment-kit--technical-architecture)
  - [🧭 Table of Contents](#-table-of-contents)
  - [🏗 Architecture](#-architecture)
    - [📁 File Organization](#-file-organization)
  - [🔀 Data Flow](#-data-flow)
  - [🧠 Script State Machine](#-script-state-machine)
    - [🔄 State Transitions](#-state-transitions)
  - [🔐 Credential Flow](#-credential-flow)
  - [📝 Task Sequence Variables](#-task-sequence-variables)
  - [🔧 Functions (12)](#-functions-12)
    - [🖥 WPF / UI Helpers](#-wpf--ui-helpers)
    - [🌐 Network / Data Helpers](#-network--data-helpers)
    - [📥 Data Retrieval](#-data-retrieval)
    - [🔑 Authentication / Output](#-authentication--output)
  - [📡 LDAP Browsing (WinPE-Compatible)](#-ldap-browsing-winpe-compatible)
    - [❓ Why LdapConnection instead of DirectorySearcher?](#-why-ldapconnection-instead-of-directorysearcher)
    - [🔄 LDAP Bind Strategy](#-ldap-bind-strategy)
  - [🎨 Design System](#-design-system)
    - [🖥 Window Layout](#-window-layout)
    - [📐 Component Specifications](#-component-specifications)
  - [🎨 Color Palette](#-color-palette)
  - [🐛 Error Handling](#-error-handling)
  - [💻 WinPE Requirements](#-winpe-requirements)
    - [🔧 Prerequisites](#-prerequisites)
    - [⚙️ Configuration Notes](#️-configuration-notes)
  - [⚡ Performance Considerations](#-performance-considerations)
    - [🚀 Optimizations Applied](#-optimizations-applied)
  - [📜 License](#-license)
  - [👤 Author](#-author)

---

## 🏗 Architecture

```
Single .ps1 file (embedded all-in-one design)
├── param() — 9 configurable parameters
├── Parse software config ("Name|TSVar|Checked" → hashtable)
├── Add-Type — PresentationFramework, PresentationCore, WindowsBase,
│              System.DirectoryServices, System.DirectoryServices.Protocols
├── [xml]$XAML = @" ... "@ — XAML string with PS variable interpolation
├── XamlReader.Load → WPF Window object (Topmost=True)
├── Control binding — $Window.FindName() for all named elements
├── 12 Functions (helpers, data, UI, auth, output)
├── 6 Event Handlers (login, search, selection, refresh, deploy, cancel)
├── try/catch on all dialogs with MessageBox fallback (WinPE-safe)
└── Window.ShowDialog() — Modal event loop entry point
```

### 📁 File Organization

```
SCCM-OSD-Deployment-Kit/
├── README.md
├── autounattend.xml
├── autounattend.md
├── technical-architecture.md       # This technical reference
├── DeploymentWizard/
│   ├── DeploymentWizard.ps1        # Main WPF wizard (~1550 lines)
│   ├── Start-DeploymentWizard.ps1  # SCCM Task Sequence wrapper
│   ├── DeploymentWizard.md
│   └── Start-DeploymentWizard.md
├── Post-OSD-Enrollment/
│   ├── Post-OSD-Enrollment-Accelerator.ps1
│   ├── Schedule-PostOSD-Enrollment.ps1
│   ├── Post-OSD-Enrollment-Accelerator.md
│   └── Schedule-PostOSD-Enrollment.md
├── SCCM-OSD-PreStaging/
│   ├── SCCM-OSD-PreStaging.ps1
│   ├── SCCM-OSD-PreStaging.exe
│   ├── SCCM-OSD-PreStaging.md
│   ├── README.md
│   └── Helpdesk OSD Pre-Staging Operator.xml
├── Report/
│   ├── Get-OSDDeploymentReport.ps1
│   ├── Send-QUExchangeMail.psm1
│   └── Send-QUExchangeMail.md
└── Remove-StaleADComputer.ps1
```

---

## 🔀 Data Flow

```
┌───────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT FLOW                            │
│                                                                   │
│  param()                    ┌─────────────────┐                   │
│  ┌──────────┐               │   USER INPUT     │                  │
│  │ Defaults │──────────────▶│   (WPF Controls) │                 │
│  │ or CLI   │               │                   │                 │
│  └──────────┘               │ UsernameBox       │                 │
│                             │ PasswordBox       │                 │
│  ┌──────────┐               │ ComputerNameBox   │                 │
│  │ Software │──────────────▶│ OUSearchBox      │                 │
│  │ Array    │               │ OUDataGrid        │                  │
│  └──────────┘               │ SoftwarePanel     │                  │
│                             │    (CheckBoxes)   │                  │
│  ┌──────────┐               └────────┬──────────┘                  │
│  │ LDAP      │                        │                            │
│  │ LdapConn. │──────────────▶ Update-OUList                        │
│  │ + creds   │               (auto on load + after sign-in)       │
│  └──────────┘                        │                            │
│                                      ▼                            │
│                           ┌──────────────────┐                    │
│                           │   VALIDATION      │                  │
│                           │ (Deploy button)   │                  │
│                           │                   │                  │
│                           │ ✓ Authenticated?  │                  │
│                           │ ✓ Name not empty? │                  │
│                           │ ✓ Valid chars?    │                  │
│                           │ ✓ ≤ 15 chars?    │                   │
│                           │ ✓ OU selected?    │                  │
│                           └────────┬─────────┘                   │
│                                    ▼                             │
│              ┌──────────────────────────────────────┐            │
│              │    Write-SCCMVariables               │            │
│              │    COM Microsoft.SMS.TSEnvironment   │            │
│              │                                      │            │
│              │  OSDComputerName    = computer name  │            │
│              │  OSDDomainName      = domain FQDN    │            │
│              │  OSDDomainOUName    = selected OU DN │            │
│              │  OSDJoinAccount     = domain\user    │            │
│              │  OSDJoinPassword    = **** (masked)  │            │
│              │  OSDRegisteredOrgName = org name     │            │
│              │  App_*             = TRUE            │            │
│              └──────────────────────────────────────┘            │
│                                    ▼                             │
│              ┌──────────────────────────────────────┐            │
│              │    Result Dialog (Back / Deploy)     │            │
│              │    Back → return to wizard           │            │
│              │    Deploy → Window.Close()           │            │
│              └──────────────────────────────────────┘            │
└───────────────────────────────────────────────────────────────────┘
```

---

## 🧠 Script State Machine

| Variable | Type | States | Description |
|----------|------|--------|-------------|
| `$script:IsLoggedIn` | `[bool]` | `$false` → `$true` | Authentication state |
| `$script:JoinPass` | `[string]` | `""` → `plaintext` | Stored domain join password (also used for LDAP bind) |
| `$script:AuthAttempts` | `[int]` | `0` → `5` (lockout) | Failed sign-in counter |
| `$script:Closing` | `[bool]` | `$false` → `$true` | Window shutdown guard |
| `$script:OUData` | `[array]` | `$null` → populated | Cached LDAP query results |
| `$script:SoftCbs` | `[CheckBox[]]` | Generated at init | Dynamic software checkboxes |

### 🔄 State Transitions

```
              ┌──────────┐
              │  START    │
              └────┬─────┘
                   │ Window.Loaded → load OU list (anonymous bind)
                   ▼
    ┌──────────────────────────────┐
    │   READY  (Status: orange)    │
    │   OU: "Sign in to load"      │ (if anonymous fails)
    └──────────┬───────────────────┘
               │ User clicks [Sign In]
               ├── Auth FAIL  → AuthAttempts++
               │                Attempts ≥ 5? → LOCKED (red)
               │                Else → back to READY
               │   Auth OK    → AuthAttempts = 0
               │                Update-OUList with credentials
               ▼
    ┌──────────────────────────────────────────┐
    │  AUTHENTICATED (green) + OUs loaded      │
    │  Summary backgrounds: green when filled  │
    └──────────┬───────────────────────────────┘
               │ User fills name + OU + software
               ▼
    ┌──────────────────────────────────────────┐
    │  VALIDATED  (Deploy click)               │
    │  → Write TS variables                    │
    │  → Result dialog (Back / Deploy)         │
    │  → Deploy: Window.Close()                │
    └──────────────────────────────────────────┘
```

---

## 🔐 Credential Flow

```
PasswordBox.Password → [Sign In] → ValidateCredentials
       ↓ success
$script:JoinPass = password  (plaintext, in-memory only)
       ↓
       ├── Update-OUList (LDAP bind with NetworkCredential)
       │    ↓
       │   AD returns OU list → DataGrid populated
       │
       ↓
[Deploy] → Write-SCCMVariables → COM TSEnvironment
       ↓
┌──────────────────────────────────────────────────────────┐
│ $tsenv.Value("OSDJoinAccount")  = domain\user           │
│ $tsenv.Value("OSDJoinPassword") = password (hidden var) │
│ $tsenv.Value("OSDDomainName")   = domain FQDN           │
│ $tsenv.Value("OSDDomainOUName") = selected OU DN        │
│ $tsenv.Value("OSDComputerName") = new computer name     │
│ $tsenv.Value("OSDRegisteredOrgName") = org name         │
│ $tsenv.Value("App_*")           = TRUE / not set        │
└──────────────────────────────────────────────────────────┘
```

**🛡 Security:** Password stored only in `$script:JoinPass` (never written to disk or log). The SCCM variable `OSDJoinPassword` is flagged as hidden. Max 5 failed auth attempts before lockout. Credentials also reused for authenticated LDAP bind in WinPE.

---

## 📝 Task Sequence Variables

| PS Value / Control | TS Variable | Type | Auto-Consumed? |
|--------------------|-------------|------|----------------|
| `$ComputerNameBox.Text` | `OSDComputerName` | Built-in | Yes |
| `$script:Domain` | `OSDDomainName` | Built-in | Yes |
| `$sel.DN` | `OSDDomainOUName` | Built-in | Yes |
| `$UsernameBox.Text` | `OSDJoinAccount` | Built-in | Yes |
| `$script:JoinPass` | `OSDJoinPassword` | Built-in | Yes |
| `$script:Org` | `OSDRegisteredOrgName` | Built-in | Yes |
| Checkbox (checked) | `App_*` | Custom | No — use `%VarName%` |

---

## 🔧 Functions (12)

### 🖥 WPF / UI Helpers

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `New-Brush` | `-Hex` | Creates frozen SolidColorBrush from #RRGGBB |
| `Write-UiLog` | `-M`, `-L` | Thread-safe color-coded Message Center log entry |
| `Show-AuthBanner` | `-Type`, `-M` | Displays color-coded authentication result banner |
| `Hide-AuthBanner` | — | Collapses the authentication banner |
| `Show-CustomDialog` | `-Type`, `-T`, `-M` | Styled modal dialog with MessageBox fallback; XML-escaped parameters |

### 🌐 Network / Data Helpers

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `Test-TcpReach` | `-H`, `-P`, `-TO` | Async TCP port test (LDAP 389, Kerberos 88) with timeout |
| `ConvertTo-FriendlyOUPath` | `-DN` | DN → "Top / Parent / Child" human-readable path |

### 📥 Data Retrieval

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `Update-OUList` | — | LdapConnection → DataGrid; authenticated bind if logged in, anonymous fallback |
| `Filter-OUDataGrid` | `-F` | Client-side live search (Arabic-compatible Unicode matching via `-like`) |
| `Update-Summary` | — | Refreshes all 5 summary pills; individual green/red backgrounds per row |

### 🔑 Authentication / Output

| Function | Parameters | Purpose |
|----------|-----------|---------|
| `Test-ADAuthentication` | `-U`, `-P` | PrincipalContext.ValidateCredentials; returns hashtable |
| `Write-SCCMVariables` | `-CN`, `-OU`, `-OUN`, `-DN`, `-JU`, `-JP`, `-Apps` | COM TSEnvironment → writes all variables |

---

## 📡 LDAP Browsing (WinPE-Compatible)

### ❓ Why LdapConnection instead of DirectorySearcher?

| | DirectorySearcher (old) | LdapConnection (current) |
|---|---|---|
| **Underlying technology** | ADSI COM (adsldp.dll) | Pure .NET TCP socket |
| **Works in WinPE?** | No — `0x80005000` / `E_ADS_ERROR` | Yes |
| **Assembly** | System.DirectoryServices | System.DirectoryServices.Protocols |
| **Bind mode** | Implicit via COM | Explicit: anonymous or NetworkCredential |
| **Search API** | FindAll() | SendRequest(SearchRequest) |
| **Result parsing** | ResultPropertyCollection | SearchResultEntry.Attributes → DirectoryAttribute.GetValues([string]) |

### 🔄 LDAP Bind Strategy

```
Window.Loaded
    ├── Not logged in → Anonymous bind
    │   ├── Success (domain-joined Windows) → OUs loaded
    │   └── Fail (WinPE) → "Sign in to load OUs" (orange)
    │
    └── After Sign In → Update-OUList called again
        └── NetworkCredential(Username, JoinPass, Domain) bind
            └── Success → 137 OUs loaded, DataGrid populated
```

---

## 🎨 Design System

### 🖥 Window Layout

```
┌──────────────────────────────────────────────────────────────┐
│ HEADER: Navy bar │ Logo │ Title + subtitle │ Status dot     │ 52px
├───────────────────────┬──────────────────────────────────────┤
│ LEFT COLUMN           │ RIGHT COLUMN                         │
│ ┌───────────────────┐ │ ┌──────────────────────────────────┐ │
│ │ Authentication    │ │ │ Deployment Summary               │ │
│ │ (Gold accent)     │ │ │ (Gold accent)                    │ │
│ │ - Username        │ │ │ Computer:  [value] 🟢/🔴         │ │
│ │ - Password        │ │ │ Target OU: [value] 🟢/🔴         │ │
│ │ - [Sign In]       │ │ │ Domain:    [value] 🟢            │ │
│ └───────────────────┘ │ │ Software:  [value] 🟢/🔴         │ │
│ ┌───────────────────┐ │ │ User:      [value] 🟢/🔴         │ │
│ │ Computer Name     │ │ └──────────────────────────────────┘ │
│ │ (Navy accent)     │ │ ┌──────────────────────────────────┐ │
│ │ - [TextBox]       │ │ │ Software Installation            │ │
│ └───────────────────┘ │ │ (Navy accent)                    │ │
│ ┌───────────────────┐ │ │ - [✓] App1   [ ] App2           │ │
│ │ Target OU         │ │ └──────────────────────────────────┘ │
│ │ (Gold accent)     │ │ ┌──────────────────────────────────┐ │
│ │ - 🔍 [Search____] │ │ │ Message Center                   │ │
│ │ - DataGrid (3 col)│ │ │ (Navy accent, dark bg)           │ │
│ │   (horiz scroll)  │ │ │ [INFO] Ready. Domain: momar... │ │
│ │ - Selected OU     │ │ └──────────────────────────────────┘ │
│ └───────────────────┘ │                                      │
├───────────────────────┴──────────────────────────────────────┤
│ FOOTER: [Refresh] │ v1.0 | Company | [Cancel] [Deploy]     │ 36px
└──────────────────────────────────────────────────────────────┘
```

🟢 = green background when filled    🔴 = red background when empty

### 📐 Component Specifications

| Element | Spec |
|---------|------|
| **Cards** | White background, #E4E9F0 border, 5px radius, CardShadow, Base font 12px |
| **Accent Bars** | 5×20px color-coded vertical bars (Gold = Auth/OU/Summary, Navy = Computer/Software/Message Center) |
| **Buttons** | BtnBase 28px height, SemiBold, 12px font → BtnPrimary/Blue/Green/Red variants |
| **DataGrid** | 140px height, horizontal scrollbar Auto, fixed column widths (130+170+260) |
| **Message Center** | #1F2D3A background, Consolas 11px, [LEVEL] prefix, auto-scroll |
| **Summary** | Individual value borders: GreenBg (#ECFDF3) when filled, RedBg (#FEF2F2) when empty |
| **Dialogs** | try/catch on XamlReader.Load, MessageBox.Show() fallback for WinPE safety |

---

## 🎨 Color Palette

| Role | Hex Code | Usage |
|------|----------|-------|
| **Navy** | `#031926` | Header background, Computer/Software/Message Center accent bars |
| **Gold** | `#C9A23D` | Logo badge, Auth/OU/Summary accent bars |
| **Green** | `#28A745` | Success states, Deploy button, green summary backgrounds |
| **Red** | `#DC3545` | Error banners, error dialogs, red summary backgrounds |
| **Orange** | `#F59E0B` | Warning states, initial status indicator, Cancel/Warning dialogs |
| **SoftBlue** | `#EEF2FF` | Software panel, selected OU indicator, summary pills |
| **AccentBlue** | `#1D4ED8` | Software checkbox text, info dialogs, accent text |
| **GreenBg** | `#ECFDF3` | Success green background |
| **RedBg** | `#FEF2F2` | Error red background |
| **PageBg** | `#F6F8FB` | Window background |
| **TextDark** | `#1F2D3A` | Primary text, headings |
| **TextMuted** | `#7C8BA1` | Subtitles, hints, muted text |
| **Border** | `#E4E9F0` | Card borders, input borders |

---

## 🐛 Error Handling

| Scenario | Detection | Response | User Impact |
|----------|-----------|----------|-------------|
| Empty username/password | `Test-ADAuthentication` | Red auth banner | Blocked — can retry |
| Wrong credentials | `ValidateCredentials` returns false | Red auth banner | Blocked — can retry (to a limit) |
| DC unreachable | Exception | Red auth banner: "Cannot reach domain" | Blocked |
| Auth lockout | `AuthAttempts ≥ 5` | Red auth banner + Sign In disabled | Blocked — must restart |
| Anonymous LDAP fail (WinPE) | `Update-OUList` catch + `!$IsLoggedIn` | Orange: "Sign in to load OUs" | Non-fatal — sign in to proceed |
| Authenticated LDAP fail | `Update-OUList` catch + `$IsLoggedIn` | Red: "Cannot load OUs" + error log | UI degraded |
| No OU selected | Deploy click: `!$sel.DN` | Warning dialog (MessageBox fallback) | Blocked |
| Invalid computer name | Regex: `[\/:*?"<>|]` | Warning dialog | Blocked |
| Name > 15 chars | Length check | Warning dialog | Blocked |
| Not signed in | Deploy click: `!$IsLoggedIn` | Warning dialog | Blocked |
| TSEnvironment unavailable | COM object creation fails | Red dialog: "Not inside Task Sequence" | Non-fatal |
| XamlReader.Load fails (WinPE) | try/catch around all dialog Load() | MessageBox.Show() fallback | Degraded — still functional |
| Wizard file not found | `Start-DeploymentWizard.ps1`: `Test-Path` | Log: "[ERROR] file not found" | Fatal — exit 1 |
| Invalid parameters | `Start-DeploymentWizard.ps1`: `IsNullOrWhiteSpace` | Log: "[ERROR] required param" | Fatal — exit 1 |

---

## 💻 WinPE Requirements

### 🔧 Prerequisites

```
WinPE-PowerShell   ~45 MB   — PowerShell execution
WinPE-NetFX        ~195 MB  — WPF, AD auth, LDAP protocols
System.DirectoryServices.Protocols — loaded via Add-Type at script init
─────────────────────────
Total              ~240 MB
```

> 💡 WinPE-WMI is no longer required (device info + connectivity tests removed).

### ⚙️ Configuration Notes

- Add components via SCCM Console → Software Library → Boot Images
- After adding, update Distribution Points
- Anonymous LDAP will fail in WinPE (expected) — user must sign in to load OUs
- Sign-in credentials are reused for authenticated LDAP bind
- Dialog fallback to MessageBox ensures functionality even if XAML rendering fails

---

## ⚡ Performance Considerations

| Operation | Estimated Time | Note |
|-----------|---------------|------|
| WPF window load | < 100 ms | XAML parsing (one-time) |
| AD authentication | 1-5 seconds | DC load + network |
| LDAP OU query (authenticated) | 2-10 seconds | Direct TCP to DC, paging removed for reliability |
| TS variable write | < 50 ms | Local COM call |
| Client-side OU filter | < 10 ms | Where-Object on cached data |

### 🚀 Optimizations Applied

- **Frozen brushes**: All SolidColorBrush instances frozen for thread safety
- **Async TCP test**: BeginConnect/EndConnect with timeout
- **Client-side OU filtering**: Where-Object on cached `$script:OUData` array
- **Closing guard**: `$script:Closing` flag prevents stale UI dispatches
- **Direct LDAP**: No ADSI COM overhead — pure .NET TCP socket
- **Topmost window**: Always visible above other windows during deployment

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).

---

## 👤 Author

**Mohammad Abdulkader Omar**
Website: https://momar.tech
LinkedIn: https://www.linkedin.com/in/mabdulkadr/

---

v1.0 | August 2026
Momar Tech — IT Operations
