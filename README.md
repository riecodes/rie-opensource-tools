# rie-opensource-tools

Small, single-file Windows utilities. No installer, no dependencies, no telemetry — every tool is a plain text script you can read end to end before running it.

## Tools

### [battery-mode](battery-mode/)

Extreme battery-saving mode for ASUS ROG Zephyrus M15 (GU502LV), with exact restore.

Applies reversible power-saving changes to maximize battery runtime: lowers CPU frequency, sets display brightness, adjusts power plan settings, stops energy-intensive background processes, and switches Windows power mode to "Best power efficiency". **Backs up your machine's current state before changing anything** — restoring reads that backup, not hardcoded defaults.

- **Quick start:** `bat extreme` (apply), `bat restore` (undo), `bat status` (check current state)
- **Install:** Copy to `C:\dev\battery-mode`, set `BATTERY_MODE_HOME` env var, add shim to PATH
- **Read more:** [battery-mode/README.md](battery-mode/README.md)

### [merge-file-explorer](merge-file-explorer/)

Merges every open File Explorer folder window into a single tabbed Explorer window.

Windows 11 gave File Explorer tabs but never gave it a "merge all windows" command. If you end up with eleven Explorer windows scattered across monitors, this script folds them all into one — one tab per folder — and closes the now-empty source windows.

- **Quick start:** Double-click `Merge File Explorers.cmd`
- **Parameters:** `-NoAnimation`, `-NoPause`, `-DelayScale`, `-Trace`, `-Verbose`
- **Read more:** [merge-file-explorer/README.md](merge-file-explorer/README.md)

## Adding a New Tool

Each tool lives in its own folder with:
- **`tool-name.ps1`** — main script (required)
- **`Tool Name.cmd`** — launcher shim for double-clicking (optional, but recommended for GUI users)
- **`README.md`** — tool-specific documentation (required)
- **`.gitignore`** — tool-specific ignore rules (optional)

Example structure:
```
rie-opensource-tools/
  ├── my-new-tool/
  │   ├── my-new-tool.ps1
  │   ├── My New Tool.cmd
  │   ├── README.md
  │   └── .gitignore (if needed)
  ├── battery-mode/
  ├── merge-file-explorer/
  ├── README.md (this file)
  ├── LICENSE
  └── .gitignore
```

**Guidelines:**
- Keep scripts single-file, dependency-free, and readable — anyone should audit a script in one sitting.
- Document behavior, safety considerations, and any quirky edge cases.
- Test with `-ExecutionPolicy Bypass` and `-NoProfile` to ensure no profile customizations affect it.
- If the tool creates backup or temporary files, add them to `.gitignore`.

## Requirements

Each tool specifies its own requirements. Most tools need:
- **Windows 10/11**
- **PowerShell 5.1** or **PowerShell 7+**
- **Administrator privileges** (if the tool touches system settings)

## Safety

- **Nothing is destroyed.** Tools change settings and stop processes, never uninstall or delete.
- **Backups and dry-runs.** Tools support `dry-run` mode (print actions, change nothing) and backup current state before applying changes.
- **All code is readable.** No obfuscation, no downloads, no telemetry — read any script before running it.
- **No elevation prompts.** If a tool needs admin, it tells you upfront (e.g., battery-mode says "Requires elevated PowerShell").

## Contributing

Issues and pull requests welcome. Keep tools single-file, dependency-free, and readable. New tools should follow the folder structure above and include thorough, honest documentation.

## License

MIT. See [LICENSE](LICENSE).

---

made with loving prompts by [riecodes](https://github.com/riecodes)
