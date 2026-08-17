# rie-opensource-tools

Small, single-file Windows utilities. No installer, no dependencies, no telemetry — every tool is a plain text script you can read end to end before running it.

## merge_file_explorers.ps1 (`mfe.ps1`)

Merges every open File Explorer folder window into a single tabbed Explorer window.

Windows 11 gave File Explorer tabs but never gave it a "merge all windows" command the way browsers have one. If you end up with eleven Explorer windows scattered across two monitors, this script folds them all into one window — one tab per folder — and closes the now-empty source windows.

```powershell
powershell -ExecutionPolicy Bypass -File .\merge_file_explorers.ps1
```

### Requirements

- Windows 11 (build with File Explorer tab support — `Ctrl+T` must open a new tab in Explorer)
- Windows PowerShell 5.1 or PowerShell 7+
- An interactive desktop session (the script drives the real Explorer UI, so it cannot run headless or over a disconnected RDP session)

### Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-NoSplash` | switch | off | Skip the ASCII intro animation and merge immediately. |
| `-SplashSeconds` | double (0–30) | `3.0` | How long the intro spins before the merge starts. |
| `-Verbose` | switch | off | Standard `CmdletBinding` verbose stream. |

```powershell
# no animation, straight to the merge
.\merge_file_explorers.ps1 -NoSplash

# shorter intro
.\merge_file_explorers.ps1 -SplashSeconds 1
```

### What it actually does

1. Enumerates open shell windows through the `Shell.Application` COM object and keeps only the ones that are `explorer.exe` showing a real filesystem directory. Control Panel windows, `This PC`, virtual namespaces and Internet Explorer style windows are ignored.
2. Groups those tabs by window handle and picks the window that already has the most tabs as the destination, so it does the least work possible.
3. For each remaining tab, it focuses the destination window, puts that tab's path on the clipboard, and sends `Ctrl+T` → `Ctrl+L` → `Ctrl+A` → `Ctrl+V` → `Enter` — exactly the keystrokes you would type yourself to open a new tab and navigate it.
4. Waits (up to 8 seconds per tab) until the destination window really reports a new tab at that path before moving on. If Explorer does not cooperate, the script throws and **no source window is closed**.
5. Restores whatever was on your clipboard before it started.
6. Only after every tab has been recreated does it post `WM_CLOSE` to the source windows.

The intro animation is a `donut.c` style ASCII renderer: a folder icon extruded into a slab and spun around its vertical axis, shaded by a fixed light source. It is decoration only and is fully skippable with `-NoSplash`.

### Design choices worth knowing

- **Nothing is destroyed.** Source windows are closed with `WM_CLOSE` (the same message the X button sends) only after their folder is confirmed open as a tab in the destination window. No file, folder, registry key, or setting is ever touched.
- **Your clipboard is restored.** The original clipboard contents are captured before the merge and put back in a `finally` block, so an error mid-merge still restores it.
- **It fails loudly, not quietly.** `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` are set at the top. If the destination window cannot be focused, or a tab does not appear, the script stops with a message rather than closing windows it should not.
- **It only reads directory paths.** It never reads file contents, never enumerates what is inside the folders, and never sends anything anywhere.

### Known limitations

- Because it drives the real UI with `SendKeys`, do not type or click during the merge — stolen focus will misroute the keystrokes. The tab-confirmation check will catch it and abort before closing anything, but you will have to rerun.
- Explorer windows showing virtual locations (`This PC`, `Quick access`, network namespaces without a drive path, Recycle Bin) are skipped by design.
- If Explorer is configured to open folders in separate processes, or tabs are disabled, the script will report that no tab appeared and stop.

## "Is this a virus?"

No. But it is worth explaining *why* an antivirus engine might raise an eyebrow at it, because the same techniques do show up in malware:

| What the script does | Why it looks suspicious | Why it is benign here |
| --- | --- | --- |
| `Add-Type` compiles inline C# at runtime | Malware uses this to build payloads in memory | The C# is fully visible in the file: six `user32.dll` P/Invoke declarations and an ASCII renderer. Nothing is downloaded, decoded, or decrypted. |
| P/Invoke into `user32.dll` | Window manipulation is used by injectors and clickers | Only `SetForegroundWindow`, `ShowWindowAsync`, `IsWindow`, `GetForegroundWindow`, and `PostMessage` — focus a window, restore it, and send it a close message. No process memory is read or written. |
| `SendKeys` synthetic keystrokes | Keystroke automation resembles keylogging | Keystrokes are only *sent*, never captured. The five shortcuts sent are `Ctrl+T`, `Ctrl+L`, `Ctrl+A`, `Ctrl+V`, `Enter`. |
| Clipboard read and write | Clipboard stealers exfiltrate wallet addresses and passwords | The clipboard is used as the transport for a folder path you already have open, and the original contents are restored afterwards. Nothing is logged or transmitted. |
| Recommended with `-ExecutionPolicy Bypass` | A common malware launch pattern | Needed only because unsigned local scripts are blocked by default. You can instead sign it, or run `Unblock-File .\merge_file_explorers.ps1` once. |

Things the script contains **zero** of: network calls, downloads, `Invoke-Expression`, base64 or otherwise obfuscated payloads, scheduled tasks, registry writes, persistence of any kind, file deletion, elevation prompts, and telemetry. Read it — it is 428 lines of commented PowerShell and C#.

### VirusTotal

`merge_file_explorers.ps1`

```
SHA256: 3735E320F2EA2630634769874747545BFDA926298EE940E3BCC938EDA657CECC
```

Verify the copy you downloaded matches before you trust any report below:

```powershell
Get-FileHash .\merge_file_explorers.ps1 -Algorithm SHA256
```

Then paste that hash into [virustotal.com](https://www.virustotal.com/gui/home/search) to pull up the scan yourself, or upload the file for a fresh one.

<!-- VIRUSTOTAL SCREENSHOTS: drop images in assets/ and reference them here, e.g.
![VirusTotal detection tab](assets/virustotal-detection.png)
![VirusTotal details tab](assets/virustotal-details.png)
-->

## Contributing

Issues and pull requests welcome. Keep tools single-file, dependency-free, and readable — anyone should be able to audit a script here in one sitting.

## License

MIT. See [LICENSE](LICENSE).

---

made with loving prompts by [riecodes](https://github.com/riecodes)
