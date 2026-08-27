# Merge File Explorers

Merges every open File Explorer folder window into a single tabbed Explorer window.

Windows 11 gave File Explorer tabs but never gave it a "merge all windows" command the way browsers have one. If you end up with eleven Explorer windows scattered across two monitors, this script folds them all into one window — one tab per folder — and closes the now-empty source windows.

## Quick Start

Double-click **`Merge File Explorers.cmd`** — no terminal needed.

Or from PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\merge_file_explorers.ps1
```

## Installation

Copy `merge_file_explorers.ps1` and `Merge File Explorers.cmd` to your desired location. Both files must be in the same folder.

For a desktop or taskbar shortcut: right-click `Merge File Explorers.cmd` → **Send to** → **Desktop (create shortcut)**.

## Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-NoAnimation` | switch | off | Run without the spinning folder and progress bar; status lines are printed as plain text instead. Aliased as `-NoSplash`. |
| `-NoPause` | switch | off | Skip the "press any key to continue" prompt at the end. |
| `-DelayScale` | double (0.25–10) | `1.0` | Multiplies every wait. Raise it if Explorer is slow to settle on your machine. |
| `-Trace` | switch | off | Log what every step actually observed — tab counts, which control took focus, what the address bar held. Implies `-NoAnimation`. |
| `-Verbose` | switch | off | Standard `CmdletBinding` verbose stream. |

```powershell
# plain text output, no animation
.\merge_file_explorers.ps1 -NoAnimation

# unattended: no animation, no prompt at the end
.\merge_file_explorers.ps1 -NoAnimation -NoPause
```

## How it works

1. Finds all open `explorer.exe` windows showing filesystem directories (ignores Control Panel, `This PC`, virtual namespaces, Internet Explorer style windows).
2. Picks the window with the most tabs as the destination — or the most recently used if tied.
3. For each remaining tab: focuses the destination window, copies the tab's path to clipboard, sends `Ctrl+T` → `Ctrl+L` → `Ctrl+A` → `Ctrl+V` → `Enter`.
4. Waits (up to 8 seconds per tab) until the destination window confirms a new tab at that path.
5. Restores your original clipboard contents.
6. Closes the now-empty source windows.
7. Prints a summary of merged folders.

**Do not touch the mouse or keyboard while it runs.** The script holds the destination Explorer window in the foreground; alt-tabbing mid-merge aborts immediately — by design, so your folder path never gets typed into the wrong window. A merge costs roughly two seconds per window.

## Design & Safety

- **Nothing is destroyed.** Source windows are closed with `WM_CLOSE` (the same message the X button sends) only after their folder is confirmed in the destination.
- **Your clipboard is restored.** Original contents are captured before the merge and restored in a `finally` block — an error mid-merge still gets it back.
- **It fails loudly.** `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` ensure errors stop the script immediately, never silently.
- **Safety checks on every keystroke.** Uses UI Automation to confirm the address bar has focus before typing, and that the new tab actually exists before moving on.
- **Only reads directory paths.** Never reads file contents, never enumerates folders, never sends anything anywhere.

## Requirements

- **Windows 11** (with File Explorer tabs — `Ctrl+T` must open a new tab in Explorer)
- **PowerShell 5.1** or **PowerShell 7+**
- **Interactive desktop session** (drives the real Explorer UI; cannot run headless or over disconnected RDP)
- **STA thread** (for clipboard access; Windows PowerShell 5.1 is STA by default; if you hit a "single thread apartment" error, launch with `powershell -STA`)
- **UIAutomationClient / UIAutomationTypes** (ships with the .NET Framework on every supported Windows install)

## Known Limitations

- Do not type or click during the merge — keystrokes go to whatever window is focused.
- Explorer windows showing virtual locations (`This PC`, `Quick Access`, network namespaces, Recycle Bin) are skipped.
- If Explorer is configured to open folders in separate processes, or tabs are disabled, the merge will report that no tab appeared and stop.

## "Is this a virus?"

No. But the techniques are worth explaining, because they also show up in malware:

| What the script does | Why it looks suspicious | Why it is benign here |
| --- | --- | --- |
| `Add-Type` compiles inline C# at runtime | Malware uses this to build payloads in memory | The C# is fully visible in the file: eight P/Invoke declarations, an ASCII renderer, and the console display. Nothing is downloaded, decoded, or decrypted. |
| P/Invoke into `user32.dll` and `kernel32.dll` | Window manipulation is used by injectors and clickers | Eight imports total: focus windows, restore them, send close messages, walk the Z-order, find this console. No process memory is read or written. |
| `SendKeys` synthetic keystrokes | Keystroke automation resembles keylogging | Keystrokes are *sent*, never captured. The five shortcuts are `Ctrl+T`, `Ctrl+L`, `Ctrl+A`, `Ctrl+V`, `Enter`. |
| Clipboard read and write | Clipboard stealers exfiltrate wallet addresses and passwords | The clipboard carries only a folder path you already have open. Original contents are restored afterwards. Nothing is logged or transmitted. |
| UI Automation reads focused elements | Accessibility APIs can scrape other apps | Two read-only questions about Explorer's own address bar: what has focus, and what text is in it. It is a safety check. |
| Recommended with `-ExecutionPolicy Bypass` | A common malware launch pattern | Needed only because unsigned local scripts are blocked by default. You can instead sign it or run `Unblock-File` once. |

**Contains zero:** network calls, downloads, `Invoke-Expression`, obfuscated payloads, scheduled tasks, registry writes, persistence, file deletion, elevation prompts, and telemetry.

---

made with loving prompts by [riecodes](https://github.com/riecodes)
