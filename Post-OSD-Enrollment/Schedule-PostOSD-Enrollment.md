# 🚀 Schedule-PostOSD-Enrollment.ps1 (Self-Cleaning Scheduler)

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)
![Account](https://img.shields.io/badge/Account-LOCAL%20SYSTEM-9C27B0.svg)
![Version](https://img.shields.io/badge/version-1.0-green.svg)

---

## 📖 Overview

**Schedule-PostOSD-Enrollment.ps1** is the **retry and cleanup engine** for the Post-OSD enrollment pipeline. It solves the fundamental problem of post-OSD timing: some operations (Entra ID join, MDM enrollment) simply take longer than the task sequence runtime.

Instead of blocking the TS for an unknown amount of time, this script:

- 📋 **Registers** a post-logon scheduled task that re-runs [`Post-OSD-Enrollment-Accelerator.ps1`](Post-OSD-Enrollment-Accelerator.md) every 5 minutes for 30 minutes after the first user logon
- 🔄 **Reboots once** if the accelerator signals `3010` (IPv6 change needed), with a guard that prevents infinite reboot loops
- 🧹 **Self-destructs** — a cleanup task deletes everything (both tasks, the script copy, markers, and this scheduler file) 35 minutes after registration

### The Timing Problem It Solves

```
Task Sequence runs:       [==== wizard ====][== apps ==][join domain][-- ACCELERATOR --]
                              (30-45 min total)
                         ↑                        ↑                     ↑
                         Device booted         Domain joined      Accelerator finishes
                         in WinPE              AAD Connect        BUT AAD Connect
                                               hasn't synced yet  may still be mid-sync!

Post-logon scheduler:     [logon]──[5min]──[5min]──[5min]──[5min]──[5min]──[cleanup]
                         ↑                      ↑
                         Accelerator runs       Now AAD Connect has synced
                         again                  Entra join succeeds
```

The retry window (30 minutes) neatly overlaps with the typical AAD Connect sync cycle (also 30 minutes by default).

> **Placement:** Run this as the **LAST step** of the task sequence (as SYSTEM), immediately before the accelerator itself. It copies the accelerator to a stable location and sets up retries. The accelerator then executes one final time as part of the task sequence.

---

## 🏗 Architecture

```
Schedule-PostOSD-Enrollment.ps1 (~170 lines)
├── param()                     # 8 configurable timing + path parameters
├── TS integration              # Detect TSEnv → set PostOSDScheduled = 1, override LogPath
│
├── IDEMPOTENCY CHECK           # If PostOSD-Enrollment task already exists → exit 0
├── SCRIPT COPY                 # Copy accelerator → C:\Windows\Temp\PostOSD\
│
├── POST-LOGON TASK             # PostOSD-Enrollment
│   ├── Principal: SYSTEM, RunLevel Highest
│   ├── Trigger: AtLogOn + Repetition (5 min × 30 min)
│   ├── Settings: TimeLimit 20 min, IgnoreNew, allow on battery
│   └── Action: powershell.exe → run accelerator → if 3010 && !flag → reboot
│
├── CLEANUP TASK                # PostOSD-Cleanup
│   ├── Principal: SYSTEM, RunLevel Highest
│   ├── Trigger: Once, 35 min after registration
│   └── Action: delete both tasks + copied script + scheduler file + flag
│
└── VERIFICATION                # Confirm PostOSD-Enrollment task exists
```

### Task Lifecycle Timeline

```
T=0   ── Scheduler runs in TS (last step)
          • Copies accelerator to stable location
          • Registers PostOSD-Enrollment (AtLogon)
          • Registers PostOSD-Cleanup (once at T+35 min)
          • Accelerator runs once more inside TS
          • TS exits, machine reboots

T=~3m ── AutoLogon after OSD → PostOSD-Enrollment fires
          • Accelerator runs
          • If IPv6 changed → exit 3010 → RebootDone.flag → shutdown /r

T=~8m ── After reboot, auto-logon → PostOSD-Enrollment fires again
          • Accelerator runs (IPv6 already disabled → exit 0)
          • Repeat every 5 min until T=30m

T=30m ── PostOSD-Enrollment repetition expires, stops running

T=35m ── PostOSD-Cleanup fires
          • Unregisters both tasks
          • Deletes: accelerator copy, scheduler file, RebootDone.flag
          • Folder C:\Windows\Temp\PostOSD\ is now empty (or can be manually deleted)
```

---

## ✨ Core Features

### 🔹 Stable Script Copy

The SCCM package cache is **ephemeral** — SCCM deletes packages after the task sequence completes, or they may be cleaned up by maintenance tasks. A scheduled task that references a file in the package cache **will break** when SCCM cleans up.

**How it solves this:**

```powershell
# Step 1: Create stable directory
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

# Step 2: Copy the accelerator out of the package cache
$StableMain = Join-Path $WorkDir 'Post-OSD-Enrollment-Accelerator.ps1'
Copy-Item -LiteralPath $MainScriptPath -Destination $StableMain -Force
```

The default `WorkDir` is `C:\Windows\Temp\PostOSD\`. This location:
- Lives outside the SCCM package cache
- Survives reboots
- Is persistent (Windows doesn't auto-clean `Windows\Temp`)

### 🔹 Post-Logon Retry Task (`PostOSD-Enrollment`)

**Task Registration Details:**

| Property | Value | Rationale |
|----------|-------|-----------|
| **Principal** | `SYSTEM`, `ServiceAccount`, `RunLevel Highest` | Accelerator needs SYSTEM for registry writes, WMI calls, and `dsregcmd` |
| **Trigger** | `AtLogOn` with repetition | Fires immediately on AutoLogon after OSD. Works with any account. |
| **Repetition** | Every 5 min for 30 min | 6 shots total. Aligned with the 30-min AAD Connect sync cycle. |
| **ExecutionTimeLimit** | 20 minutes | The accelerator takes 5-10 min. 20 min prevents a stuck run from blocking subsequent ones. |
| **MultipleInstances** | `IgnoreNew` | If the previous run is still active, don't start a new one. |
| **Allow on battery** | Yes | Laptops. The task should run regardless of power state. |
| **Do not stop if going on batteries** | Yes | Prevents the task from being killed when a laptop is unplugged. |

**The Wrapper Command:**

The action isn't just "run the script." It's a PowerShell wrapper that handles the `3010` reboot case:

```powershell
$wrapper  = "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$StableMain'; 
if (`$LASTEXITCODE -eq 3010 -and -not (Test-Path '$doneFlag')) { 
    Set-Content -LiteralPath '$doneFlag' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force; 
    shutdown.exe /r /t $RebootDelaySeconds /c 'PostOSD IPv6 change - rebooting' /d p:0:0 
}"
```

Broken down:
1. Run the accelerator
2. If `$LASTEXITCODE -eq 3010` (accelerator says "reboot needed for IPv6")
3. **AND** `RebootDone.flag` does NOT exist (we haven't rebooted yet)
4. Write the flag with the current timestamp
5. `shutdown /r /t 60` — reboot in 60 seconds with a clear comment

### 🔹 One-Time Reboot Guard

**The problem:** Without a guard, if the accelerator repeatedly returns `3010` (e.g., the IPv6 registry write fails but the flag check still passes), you get an infinite reboot loop. The machine keeps rebooting indefinitely.

**How the guard works:**

```
Run 1: LASTEXITCODE=3010, flag doesn't exist → write flag → reboot
       After reboot...
Run 2: LASTEXITCODE=3010, flag EXISTS → SKIP reboot → task finishes
Run 3: LASTEXITCODE=0 (IPv6 already disabled) → task finishes normally
```

The flag file `C:\Windows\Temp\PostOSD\RebootDone.flag` is the single source of truth. Once written, no more reboots. If you need another reboot cycle for any reason, delete the flag manually.

The shutdown comment (`/d p:0:0`) logs the reason in the system event log as "Planned" — this prevents Windows from interpreting it as an unexpected crash.

### 🔹 Self-Cleanup Task (`PostOSD-Cleanup`)

**Why 35 minutes:** The post-logon task's repetition interval is 30 minutes (5 min × 6). The cleanup task fires at 35 minutes to guarantee the retry window is over before cleaning up.

**What it deletes:**

```powershell
$cleanupCmd = "
    Start-Sleep -Seconds 5;
    Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false;
    Unregister-ScheduledTask -TaskName '$CleanupTaskName' -Confirm:`$false;
    Remove-Item -LiteralPath '$StableMain','$PSCommandPath','$doneFlag' -Force
"
```

In order:
1. 5-second safety sleep (ensure no task is mid-execution)
2. Unregister `PostOSD-Enrollment`
3. Unregister `PostOSD-Cleanup` (self-deletion)
4. Delete: the accelerator copy, this scheduler file (`$PSCommandPath`), and the reboot flag

**After cleanup:** `C:\Windows\Temp\PostOSD\` is empty (the scheduler `.ps1` file in the original package cache location may also be gone, depending on SCCM cache cleanup).

**Fallback trigger:** The cleanup task uses a one-time trigger based on the clock — NOT AtLogOn. This means cleanup happens even if **no user ever logs in**. A machine left at the logon screen for 35 minutes will still be cleaned up.

### 🔹 Idempotency

The script is safe to run multiple times:

```powershell
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-TSLog "Task '$TaskName' already registered - skipping (idempotent)."
    exit 0
}
```

If the post-logon task already exists (from a previous TS run, or a manual rerun), the script exits immediately with a log entry. No duplicate tasks are created.

### 🔹 Task Sequence Integration

```powershell
$tsenv = $null
try { $tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment } catch { }
if ($tsenv) {
    try {
        $tsLog = $tsenv.Value('_SMSTSLogPath')
        if ($tsLog) { $LogPath = $tsLog }
        $tsenv.Value('PostOSDScheduled') = '1'
    } catch { }
}
```

- Detects the TSEnvironment COM object (only available inside a task sequence)
- Overrides `$LogPath` with `_SMSTSLogPath` (routes logs to the SCCM directory)
- Sets `PostOSDScheduled = 1` as a TS variable — can be used in conditions by later steps

---

## ⚙️ Requirements

| Requirement | Notes |
|-------------|-------|
| Windows 10 / 11 | PowerShell 5.1+ |
| LOCAL SYSTEM account | The TS step should run as SYSTEM (or equivalent admin) |
| `Post-OSD-Enrollment-Accelerator.ps1` | Must exist at `-MainScriptPath` (default: same `Post-OSD-Enrollment/` folder) |
| ScheduledTasks module | Built into PowerShell 5.1 on Windows. No install needed. |
| Task Scheduler service | Running (enabled by default on all Windows editions) |

---

## 🚀 How to Run

### Option 1 — Task Sequence (Production)

Add as the **second-to-last** step of your OSD task sequence:

```
TS Step Order:
   ... 
   → Schedule-PostOSD-Enrollment.ps1    ← THIS script (as SYSTEM)
   → Post-OSD-Enrollment-Accelerator.ps1 ← Accelerator runs one more time in TS
   (end of task sequence)
```

Run command:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Schedule-PostOSD-Enrollment.ps1"
```

### Option 2 — Custom Paths + Timing

```powershell
.\Schedule-PostOSD-Enrollment.ps1 `
    -MainScriptPath "C:\Deploy\Post-OSD-Enrollment-Accelerator.ps1" `
    -WorkDir "C:\CustomPath\PostOSD" `
    -RepeatIntervalMinutes 10 `
    -RepeatDurationMinutes 60 `
    -CleanupDelayMinutes 65 `
    -LogPath "D:\Logs"
```

This example:
- Retries every 10 minutes for 1 hour (better for slow networks)
- Cleans up at 65 minutes (1 hour retry + 5 minutes buffer)

### Option 3 — Interactive (Testing)

```powershell
.\Schedule-PostOSD-Enrollment.ps1
```

Registers the tasks. Check Task Scheduler → `Task Scheduler Library` → `PostOSD-Enrollment` and `PostOSD-Cleanup`.

---

## ⚙️ Parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `-MainScriptPath` | `.\Post-OSD-Enrollment-Accelerator.ps1` | Path to the enrollment script to copy + schedule |
| `-TaskName` | `PostOSD-Enrollment` | Name of the post-logon retry task in Task Scheduler |
| `-CleanupTaskName` | `PostOSD-Cleanup` | Name of the self-cleanup task in Task Scheduler |
| `-WorkDir` | `C:\Windows\Temp\PostOSD` | Stable directory for script copy + marker files |
| `-RepeatIntervalMinutes` | `5` | Minutes between retry repetitions |
| `-RepeatDurationMinutes` | `30` | Total retry window (should cover AAD Connect sync) |
| `-CleanupDelayMinutes` | `35` | Minutes after registration before the cleanup task fires |
| `-RebootDelaySeconds` | `60` | Seconds of warning before `shutdown /r` on exit 3010 |
| `-LogPath` | `C:\IntuneLogs` | Log output directory (overridden by `_SMSTSLogPath` in TS) |

---

## 🔄 Full Lifecycle (Timeline)

```
T+0 min    ── TS step runs: Schedule-PostOSD-Enrollment.ps1
               • Script copies itself + accelerator to C:\Windows\Temp\PostOSD\
               • Registers task: PostOSD-Enrollment (AtLogOn, repeat every 5 min × 30 min)
               • Registers task: PostOSD-Cleanup (Once, +35 min)
               • Log: "Task 'PostOSD-Enrollment' registered."
               • Exits 0

T+1 min    ── TS step runs: Post-OSD-Enrollment-Accelerator.ps1
               • Runs in the TS context (SYSTEM) one final time
               • Does time, IPv6, SCCM, Entra, MDM, Co-mgmt
               • If IPv6 changed → exit 3010 (TS may handle reboot)

T+~5 min   ── Machine reboots (TS complete, Windows boots, AutoLogon)
               • PostOSD-Enrollment fires (AtLogOn trigger)
               • Accelerator runs
               • If 3010 + no flag → write flag + reboot
               • If 0 → done for this cycle

T+10 min   ── PostOSD-Enrollment fires again (5 min repetition)
               • Accelerator runs (all settings already applied → exits 0)
               • This repeats at T+15, T+20, T+25, T+30

T+30 min   ── PostOSD-Enrollment repetition duration expires
               • Task remains but no longer triggers

T+35 min   ── PostOSD-Cleanup fires
               • Sleep 5 sec
               • Unregister PostOSD-Enrollment
               • Unregister PostOSD-Cleanup (self)
               • Delete: accelerator copy, scheduler copy, RebootDone.flag
               • Folder C:\Windows\Temp\PostOSD\ is clean
```

---

## 📊 Operational Safeguards

- ✅ **Idempotent registration** — skips if `PostOSD-Enrollment` already exists. Safe to run the TS step multiple times.
- 🧹 **Full self-cleanup** — zero files or tasks left behind after the retry window closes.
- 🔄 **Single-reboot guard** — `RebootDone.flag` is checked before every shutdown call. Exactly one reboot per deployment (if IPv6 changed).
- 👑 **Runs as SYSTEM** — no user account password needed. No credential prompts.
- ⏱ **Execution time limits** — 20 min for the retry task, 5 min for cleanup. Prevents stuck tasks from accumulating.
- 🔁 **`MultipleInstances = IgnoreNew`** — prevents stacking instances if a run takes longer than the 5-minute interval.
- 📝 **Tab-separated log** — registration details, task verification, and any errors. Same format as the accelerator log.

---

## 🚦 Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Always. This script never fails the task sequence step. Even if scheduling fails, it catches the error, logs it, and exits `0`. |

The scheduler's philosophy: **never block the task sequence.** If scheduling fails, the accelerator already ran once in the TS. The retries are a bonus, not a requirement.

---

## 🐛 Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| **Task not registered** (check Task Scheduler) | `New-ScheduledTask*` cmdlets unavailable | Verify PowerShell 5.1 is available. The `ScheduledTasks` module is built into PS 5.1. |
| **Enrollment script not found** (`-MainScriptPath`) | Path mismatch | Check the log for the actual path. Default is the same folder as the scheduler. |
| **PostOSD-Enrollment exists but never fires** | AutoLogon not configured in the TS | Ensure the task sequence enables AutoLogon (part of the standard OSD TS template). |
| **No reboot after 3010** | `RebootDone.flag` already exists from a previous run | Delete `C:\Windows\Temp\PostOSD\RebootDone.flag`. Then run the accelerator manually or wait for the next retry cycle. |
| **Logs are in the SCCM folder, not C:\IntuneLogs** | `_SMSTSLogPath` override is active | Expected when inside a TS. Check `C:\Windows\CCM\Logs\` or wherever `smsts.log` lives. |
| **Leftover files/tasks after 35 min** | Cleanup task didn't fire (machine was off/sleeping) | Tasks are one-time-only. If missed, manually delete `PostOSD-Enrollment` and `PostOSD-Cleanup` from Task Scheduler and `C:\Windows\Temp\PostOSD\`. |
| **Task triggers every logon, not just the first** | The trigger is `AtLogOn` | This is intentional — the repetition covers 30 minutes from the first logon, but it will fire on EVERY logon during that window. After 30 minutes, repetition expires and the task stops. |
| **Log show "Task already registered - skipping"** | The TS step ran before but the cleanup was missed | Expected — idempotent. The old task from the previous TS run still exists. Either delete manually or increase `-CleanupDelayMinutes` for the next run. |

---

## 🛡 Design Principles

- **Never block the task sequence** — exit code is always `0`. All errors are caught and logged.
- **Ephemeral cache independence** — the script is copied out of the SCCM package cache before scheduling.
- **Self-healing + self-cleaning** — no admin intervention needed to remove tasks or files.
- **Guard against infinite reboot** — a single flag file ensures exactly one reboot cycle.
- **Fully parameterized timing** — all intervals are parameters. Tune for your environment's AAD Connect sync speed, network latency, and reboot policies.
- **Fallback-safe cleanup** — cleanup uses a clock-based one-time trigger, not a logon trigger. Works even on machines that never get a user session.

---

## 📜 License

This project is licensed under the [MIT License](../LICENSE).

---

## 👤 Author

**Mohammad Abdulkader Omar**
Website: https://momar.tech
LinkedIn: https://www.linkedin.com/in/mabdulkadr/

---

## ⚠ Disclaimer

These scripts are provided as-is. Test them in a staging environment before applying them to production. The author is not responsible for any unintended outcomes resulting from their use.
