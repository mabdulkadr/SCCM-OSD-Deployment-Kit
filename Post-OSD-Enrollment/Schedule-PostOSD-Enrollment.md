# ⏰ Schedule-PostOSD-Enrollment.ps1

The retry + cleanup scheduler for the Post-OSD enrollment pipeline. Registers a post-logon task that re-runs the accelerator every 5 minutes for 30 minutes, then self-destructs everything at +35 min.

> **Why this exists:** Some operations (Entra ID join, MDM enrollment) take longer than the Task Sequence runtime. This script bridges that gap by scheduling retries after the user logs in.

---

## How It's Used

**In SCCM Console:**

1. Open your Task Sequence
2. Add Step → **Run PowerShell Script**
3. Configure:
   - **Script name:** `Schedule-PostOSD-Enrollment.ps1`
   - **Execution policy:** `Bypass`
   - **Package:** `SCCM-OSD-Deployment-Kit`
4. **Placement:** Second-to-last step in the Task Sequence (just before `Post-OSD-Enrollment-Accelerator.ps1`)

```
TS Step Order:
   ...
   → Schedule-PostOSD-Enrollment.ps1    ← Registers retry tasks
   → Post-OSD-Enrollment-Accelerator.ps1 ← Runs one final time in TS
   (end)
```

---

## Configuration

All parameters have sensible defaults — you usually don't need to change anything:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-MainScriptPath` | `.\Post-OSD-Enrollment-Accelerator.ps1` | Accelerator to copy + schedule |
| `-TaskName` | `PostOSD-Enrollment` | Retry task name |
| `-CleanupTaskName` | `PostOSD-Cleanup` | Cleanup task name |
| `-WorkDir` | `C:\Windows\Temp\PostOSD` | Stable directory (outside SCCM cache) |
| `-RepeatIntervalMinutes` | `5` | Minutes between retry attempts |
| `-RepeatDurationMinutes` | `30` | Total retry window (aligns with AAD Connect sync) |
| `-CleanupDelayMinutes` | `35` | When the cleanup task fires |
| `-RebootDelaySeconds` | `60` | Seconds before reboot on exit `3010` |
| `-LogPath` | `C:\IntuneLogs` | Log directory |

---

## Timeline

```
T+0     TS runs this script
        → Copies accelerator to C:\Windows\Temp\PostOSD\
        → Registers PostOSD-Enrollment task (AtLogOn, every 5 min × 30 min)
        → Registers PostOSD-Cleanup task (once at T+35)
        → Accelerator runs one final time in TS context

T+~5    First user logon → PostOSD-Enrollment fires
        → Accelerator runs
        → If IPv6 changed → exit 3010 → RebootDone.flag → reboot

T+10    Retry fires (5 min later)
        → Accelerator runs (everything already applied → exits 0)
        → Repeats at T+15, T+20, T+25, T+30

T+35    PostOSD-Cleanup fires
        → Deletes both tasks + copied script + flag
        → Folder C:\Windows\Temp\PostOSD\ is empty
```

---

## What It Creates and Cleans Up

| Item | Created | Deleted |
|------|---------|---------|
| `PostOSD-Enrollment` task (Task Scheduler) | ✅ At T+0 | ✅ At T+35 |
| `PostOSD-Cleanup` task (Task Scheduler) | ✅ At T+0 | ✅ At T+35 (self-delete) |
| `C:\Windows\Temp\PostOSD\Post-OSD-Enrollment-Accelerator.ps1` | ✅ At T+0 | ✅ At T+35 |
| `C:\Windows\Temp\PostOSD\RebootDone.flag` | ✅ At T+~5 (if reboot needed) | ✅ At T+35 |

---

## Key Behaviors

| Behavior | Description |
|----------|-------------|
| **Idempotent** | Skips if `PostOSD-Enrollment` task already exists — safe to run multiple times |
| **Never blocks TS** | Always exits `0`, even if scheduling fails — the TS continues normally |
| **Single reboot guard** | `RebootDone.flag` prevents infinite reboot loops |
| **Self-cleaning** | Zero files or tasks left behind after T+35 |
| **Cache-independent** | Copies the accelerator out of the SCCM package cache to a stable location |

---

## Why Copy the Script?

The SCCM package cache is ephemeral — SCCM deletes packages after the Task Sequence completes. A scheduled task pointing to a script in the package cache would break the first time SCCM cleans up. This script copies the accelerator to `C:\Windows\Temp\PostOSD\` which is outside the cache and survives reboots.

---

## The 3010 Reboot Wrapper

The retry task doesn't just run the accelerator — it wraps it with a reboot handler:

```powershell
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\Windows\Temp\PostOSD\Post-OSD-Enrollment-Accelerator.ps1'

if ($LASTEXITCODE -eq 3010 -and -not (Test-Path 'C:\Windows\Temp\PostOSD\RebootDone.flag')) {
    Set-Content -LiteralPath 'C:\Windows\Temp\PostOSD\RebootDone.flag' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    shutdown.exe /r /t 60 /c 'PostOSD IPv6 change - rebooting' /d p:0:0
}
```

This means the accelerator can safely signal "reboot needed for IPv6" without causing infinite reboot loops.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Task not registered | Verify PowerShell 5.1 is available (with `ScheduledTasks` module) |
| No reboot after 3010 | Delete `RebootDone.flag` manually from `C:\Windows\Temp\PostOSD\` |
| Leftover files after 35 min | Machine was off/asleep — manually delete tasks and `C:\Windows\Temp\PostOSD\` |
| "Task already registered" log | Old task from previous TS run — expected, idempotent |

---

## Related Documentation

- [Post-OSD-Enrollment-Accelerator.md](Post-OSD-Enrollment-Accelerator.md) — The provisioning engine this script schedules
