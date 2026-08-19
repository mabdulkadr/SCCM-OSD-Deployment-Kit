# ⚙️ Post-OSD Enrollment Accelerator

The silent provisioning engine that runs at the end of your Task Sequence. Performs six dependency-ordered steps that get the device fully managed — joined to Entra ID, enrolled in Intune, and co-managed with SCCM.

> **Run as:** SYSTEM account (automatic in Task Sequence)
> **Placement:** Last step in your Task Sequence, after `Schedule-PostOSD-Enrollment.ps1`
> **Companion script:** [`Schedule-PostOSD-Enrollment.ps1`](Schedule-PostOSD-Enrollment.md) handles retries and cleanup

---

## How It's Used

**In SCCM Console:**

1. Open your Task Sequence
2. Add Step → **Run PowerShell Script**
3. Configure:
   - **Script name:** `Post-OSD-Enrollment-Accelerator.ps1`
   - **Execution policy:** `Bypass`
   - **Package:** `SCCM-OSD-Deployment-Kit`
4. Optional: pass `-TimeZone` and `-LogPath` parameters

This step runs as the last step of your Task Sequence. It must run **after** domain join and SCCM client installation.

---

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-LogPath` | `C:\IntuneLogs` | Log directory (auto-overridden by `_SMSTSLogPath` inside a TS) |
| `-TimeZone` | `Arab Standard Time` | Windows time zone ID |

---

## What It Does

Six sections, executed in this exact order. Each depends on the previous one:

| # | Section | What It Does |
|---|---------|--------------|
| 1 | **Time Service** | Starts w32time, syncs from PDC, sets the configured time zone (skipped on DCs and servers) |
| 2 | **IPv6 Disable** | Disables IPv6 adapter binding + sets registry `0xFF`. Sets reboot flag only if changed. |
| 3 | **SCCM Actions** | Triggers 8 standard SCCM action GUIDs + `usoclient.exe` refresh |
| 4 | **Entra ID Join** | `dsregcmd /status` → `/join` for Hybrid Azure AD join |
| 5 | **MDM Enrollment** | Discovers tenant, configures MDM URLs, triggers `deviceenroller.exe /c /AutoEnrollMDM` |
| 6 | **Co-Management** | 3-tier detection (WMI → Registry → MDM policy) + 30s re-check |

### Why This Order?

- **Time first** — Kerberos needs clock sync within 5 minutes. TLS certs need accurate time.
- **IPv6 second** — Independent of everything else, fast, and it may trigger the reboot flag.
- **SCCM actions third** — Fire-and-forget; client may not be fully ready, retries handle that.
- **Entra fourth** — Required for MDM enrollment.
- **MDM fifth** — Requires Entra join + tenant info.
- **Co-Management last** — Confirms everything else worked.

---

## Exit Codes

| Code | Meaning | What Happens |
|------|---------|--------------|
| `0` | All sections completed, no reboot needed | TS continues normally |
| `3010` | IPv6 changed, reboot required | Scheduler handles the reboot (single reboot guard) |

---

## Logging

Writes a tab-separated log file:

```
C:\IntuneLogs\PostOSDEnrollmentAccelerator.log
```

When running inside a Task Sequence, the `_SMSTSLogPath` variable automatically redirects logs to the SCCM log directory.

---

## Requirements

| Requirement | Notes |
|-------------|-------|
| Windows 10 / 11 | PowerShell 5.1 (built-in) |
| LOCAL SYSTEM context | The TS step runs as SYSTEM automatically |
| SCCM client installed | Required for sections 3 (actions) and 6 (co-management detection) |
| AD domain membership | Required for sections 4 (Entra join) and 5 (MDM enrollment) |

### Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| `[wmiclass]` requires PowerShell 5.1 | Doesn't work in PS 7+ | SCCM Task Sequences always run PS 5.1 — no issue |
| IPv6 disable breaks DirectAccess / Always On VPN | Machines using these can't reach IPv6 services | Don't disable IPv6 if you use these features |
| Hybrid join requires AAD Connect sync | May not complete within TS runtime | The scheduler retries handle the sync gap |

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `SMS_Client trigger fails` | SCCM client not ready yet | Expected — retries happen via the scheduler |
| Hybrid join never completes | AAD Connect hasn't synced the AD object | AAD Connect syncs every 30 min — scheduler covers the window |
| MDM section skipped | Device not Entra-joined yet | Will work after section 4 succeeds |
| Co-management "Not Detected" | Cloud Attach not configured | Set up Cloud Attach in SCCM console first |
| Time service section skipped | Machine detected as DC or server | Expected — script only configures time on workstations |
| Repeated `3010` exits | Reboot guard not working | Verify `RebootDone.flag` in `C:\Windows\Temp\PostOSD\` |

---

## Related Documentation

- [Schedule-PostOSD-Enrollment.md](Schedule-PostOSD-Enrollment.md) — Retry + cleanup scheduler that runs this accelerator
