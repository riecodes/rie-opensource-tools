# rie-opensource-tools

Small, single-file Windows utilities. No installer, no dependencies, no telemetry — every tool is a plain text script you can read end to end before running it.

## merge_file_explorers.ps1 (`mfe.ps1`)

Merges every open File Explorer folder window into a single tabbed Explorer window.

Windows 11 gave File Explorer tabs but never gave it a "merge all windows" command the way browsers have one. If you end up with eleven Explorer windows scattered across two monitors, this script folds them all into one window — one tab per folder — and closes the now-empty source windows.

```powershell
powershell -ExecutionPolicy Bypass -File .\merge_file_explorers.ps1
```

### Running it without a terminal

Double-clicking a `.ps1` opens it in an editor rather than running it, so the repo ships **`Merge File Explorers.cmd`**. Double-click that instead — it supplies the flags the script needs (`-STA` for the clipboard, `-ExecutionPolicy Bypass` because the script is unsigned and local, `-NoProfile` so your `$PROFILE` cannot change its behaviour).

For a desktop or taskbar entry: right-click `Merge File Explorers.cmd` → **Send to** → **Desktop (create shortcut)**. The launcher passes arguments through, so you can append `-DelayScale 2` to the shortcut's Target if your machine needs longer waits.

**Do not touch the mouse or keyboard while it runs.** The script has to hold the destination Explorer window in the foreground, because `SendKeys` types into whatever window is focused. If you alt-tab or click away mid-merge it stops immediately with a message — by design, so your folder path never gets typed into whatever you switched to. A merge costs roughly two seconds per window.

### Requirements

- Windows 11 (build with File Explorer tab support — `Ctrl+T` must open a new tab in Explorer)
- Windows PowerShell 5.1 or PowerShell 7+
- An interactive desktop session (the script drives the real Explorer UI, so it cannot run headless or over a disconnected RDP session)
- An STA thread, because the clipboard is used to carry the path. Windows PowerShell 5.1 is STA by default; if you hit a "single thread apartment" error, launch with `powershell -STA`.
- `UIAutomationClient` / `UIAutomationTypes`, which ship with the .NET Framework on every supported Windows install

### Parameters

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

### What it actually does

1. Enumerates open shell windows through the `Shell.Application` COM object and keeps only the ones that are `explorer.exe` showing a real filesystem directory. Control Panel windows, `This PC`, virtual namespaces and Internet Explorer style windows are ignored.
2. Groups those tabs by window handle and picks the window that already has the most tabs as the destination, so it does the least work possible. When windows tie — and they all tie at one tab each in the common case — it prefers the one nearest the front of the Z-order, meaning the Explorer window you used most recently.
3. For each remaining tab, it focuses the destination window, puts that tab's path on the clipboard, and sends `Ctrl+T` → `Ctrl+L` → `Ctrl+A` → `Ctrl+V` → `Enter` — exactly the keystrokes you would type yourself to open a new tab and navigate it. Between `Ctrl+L` and `Ctrl+A` it checks via UI Automation that the address bar really holds keyboard focus, and after the paste it checks that the address bar really contains the target path, before it commits with `Enter`.
4. Waits (up to 8 seconds per tab) until the destination window really reports a new tab at that path before moving on. If Explorer does not cooperate, the script throws and **no source window is closed**.
5. Restores whatever was on your clipboard before it started.
6. Only after every tab has been recreated does it post `WM_CLOSE` to the source windows.
7. Takes focus back from Explorer, prints how many folders were merged and lists each one, then waits for a keypress.

### The display

The animation is not a splash screen — it runs *while* the merge does. The renderer is a `donut.c` style ASCII engine: a folder icon extruded into a slab, spun around its vertical axis, shaded by a fixed light source. Every wait the merge would have spent sleeping (focusing a window, letting a tab settle, polling for confirmation) is spent drawing frames instead, so the folder keeps spinning for exactly as long as there is work left.

Under the folder sit a progress bar, a live status line naming the folder currently being merged, and the watermark:

```
                    !!!****************!!!!!!
                    !!!!***************!!!!!!
                    !!!!!***************!!!!!

              [#########-----------] 9/20  45%
      Merging tab 9 of 20: C:\dev\rie-opensource-tools
            made with loving prompts by riecodes
```

When it finishes, the script takes focus back from Explorer and prints what it did — the count, the resulting tab total, and every folder it merged, numbered:

```
Merged 7 folder(s) into the existing Explorer window; it now has 9 filesystem tab(s). Closed 7 source window(s).

Merged folders:
  1. C:\dev\rie-opensource-tools
  2. C:\Users\you\Downloads
  ...

Press any key to continue...
```

If the merge stops partway, the same list is printed for the tabs that *did* land, along with a reminder that no source window was closed. Use `-NoAnimation` for plain text status lines and `-NoPause` to drop the final prompt.

### Design choices worth knowing

- **Nothing is destroyed.** Source windows are closed with `WM_CLOSE` (the same message the X button sends) only after their folder is confirmed open as a tab in the destination window. No file, folder, registry key, or setting is ever touched.
- **Your clipboard is restored.** The original clipboard contents are captured before the merge and put back in a `finally` block, so an error mid-merge still restores it.
- **It fails loudly, not quietly.** `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` are set at the top. If the destination window cannot be focused, or a tab does not appear, the script stops with a message rather than closing windows it should not.
- **Nothing is typed until `Ctrl+T` is confirmed.** A dropped `Ctrl+T` used to go unnoticed, and the `Ctrl+L` after it would land on the tab that was *already* open — so `Enter` navigated that tab away from where it was, and the merge then failed its own confirmation. A brand new tab sits on Home and reports an empty `LocationURL`, so it is invisible to the filesystem-tab filter but shows up in the unfiltered per-window count. That count is what the script waits on, retrying `Ctrl+T` up to three times before giving up without typing anything.
- **`Ctrl+A` and `Enter` are gated behind a focus check.** A freshly opened tab lands on Home with focus in the *content view*, and it takes Explorer a moment to settle. A `Ctrl+L` sent too early gets swallowed by that view — and then `Ctrl+A` selects every file in the folder and `Enter` opens all of them. So the script asks UI Automation what actually holds focus and will not send that pair until the answer is the address bar. It retries `Ctrl+L` up to three times, then gives up with a message suggesting `-DelayScale 2`.
- **It only reads directory paths.** It never reads file contents, never enumerates what is inside the folders, and never sends anything anywhere.

### Known limitations

- Because it drives the real UI with `SendKeys`, do not type or click during the merge. The script re-checks that the destination window is still foreground before every keystroke burst and stops the moment it is not, so alt-tabbing aborts the run rather than misrouting keys — but you will have to rerun it.
- The destination Explorer window has to be foreground for `SendKeys` to reach it, so the console — and the animation in it — sits behind Explorer for the duration. The script pulls focus back to the console once the merge is done, before it prints the summary and waits for a key.
- Explorer windows showing virtual locations (`This PC`, `Quick access`, network namespaces without a drive path, Recycle Bin) are skipped by design.
- If Explorer is configured to open folders in separate processes, or tabs are disabled, the script will report that no tab appeared and stop.

## "Is this a virus?"

No. But it is worth explaining *why* an antivirus engine might raise an eyebrow at it, because the same techniques do show up in malware:

| What the script does | Why it looks suspicious | Why it is benign here |
| --- | --- | --- |
| `Add-Type` compiles inline C# at runtime | Malware uses this to build payloads in memory | The C# is fully visible in the file: eight P/Invoke declarations, an ASCII renderer, and the console display that drives it. Nothing is downloaded, decoded, or decrypted. |
| P/Invoke into `user32.dll` and `kernel32.dll` | Window manipulation is used by injectors and clickers | Eight imports total: `SetForegroundWindow`, `ShowWindowAsync`, `IsWindow`, `GetForegroundWindow`, `PostMessage`, `GetTopWindow`, `GetWindow`, and `GetConsoleWindow` — focus a window, restore it, send it a close message, walk the Z-order, and find this console to focus it again at the end. No process memory is read or written. |
| `SendKeys` synthetic keystrokes | Keystroke automation resembles keylogging | Keystrokes are only *sent*, never captured. The five shortcuts sent are `Ctrl+T`, `Ctrl+L`, `Ctrl+A`, `Ctrl+V`, `Enter`. |
| Clipboard read and write | Clipboard stealers exfiltrate wallet addresses and passwords | The clipboard is used as the transport for a folder path you already have open, and the original contents are restored afterwards. Nothing is logged or transmitted. |
| UI Automation reads the focused element | Accessibility APIs can be used to scrape other apps | Two read-only questions, both about Explorer's own address bar: what control has focus, and what text is in it. It is a safety check — it is what stops the script from sending `Ctrl+A`+`Enter` into a folder view. |
| Recommended with `-ExecutionPolicy Bypass` | A common malware launch pattern | Needed only because unsigned local scripts are blocked by default. You can instead sign it, or run `Unblock-File .\merge_file_explorers.ps1` once. |

Things the script contains **zero** of: network calls, downloads, `Invoke-Expression`, base64 or otherwise obfuscated payloads, scheduled tasks, registry writes, persistence of any kind, file deletion, elevation prompts, and telemetry. Read it — it is 712 lines of commented PowerShell and C#.

### VirusTotal

`merge_file_explorers.ps1`

```
SHA256: 6E23EC61AE688F24A95EFC0C3D9F6EC08EF525E745453556D761C67618BB25D8
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
