# battery-mode

Extreme battery-saving mode for ASUS ROG Zephyrus M15 (GU502LV), with exact restore.

## What it does

Applies reversible power-saving changes to maximize battery runtime:
- Lowers CPU frequency ceiling (default 50%, tunable with `--max-cpu`)
- Sets display brightness (default 30%, tunable with `--brightness`)
- Adjusts power plan settings (sleep timers, USB suspend, wireless power saving, etc.)
- Stops energy-intensive background processes (gaming, work apps, cloud/remote tools, peripherals)
- Switches Windows power mode overlay to "Best power efficiency"

**Critically:** Backs up your machine's current state to JSON *before* changing anything. Restoring reads that backup, so "restore" means "exactly what this machine had", not "what some script author guessed."

## Safety

- All changes are to battery (DC) settings only. AC performance is untouched.
- No ASUS firmware, services, drivers, registry, or CPU voltage changes.
- No uninstall, no service disabling — stopped processes come back on next launch.
- Dry-run mode (`bat extreme dry-run`) shows every action without changing anything.
- Tested on GU502LV only; adapt settings for other hardware.

## Installation

**1. Clone or copy to `C:\dev\battery-mode`:**
```bash
git clone https://github.com/eirmonpaculan/battery-mode C:\dev\battery-mode
```

**2. Install the CLI shim (one-time):**

Open PowerShell as Administrator:
```powershell
$src = 'C:\dev\battery-mode\bat.cmd'
$dst = 'C:\Users\eirmo\.local\bin\bat.cmd'
if (-not (Test-Path $dst)) { mkdir (Split-Path $dst) -Force | Out-Null }
Copy-Item $src $dst -Force
```

**3. Set the environment variable (one-time):**
```powershell
[Environment]::SetEnvironmentVariable('BATTERY_MODE_HOME', 'C:\dev\battery-mode', 'User')
```

**4. Verify:**
```
bat --help
```

## Usage

All commands require an **elevated (admin) PowerShell**. If you forget, the script will tell you.

### Check current state
```bash
bat status                    # Show current + backed-up settings
bat status check-gpu          # Also show GPU power draw
```

### Test (dry-run)
```bash
bat extreme dry-run           # Print actions, change nothing
bat extreme dry-run --brightness 20
```

### Apply extreme mode
```bash
bat extreme                   # Apply and back up current state
bat extreme --brightness 20   # Use 20% brightness instead of default 30%
bat extreme --max-cpu 35      # Use 35% CPU ceiling instead of 50%
```

### Restore to backed-up state
```bash
bat restore                   # Restore. Also spelled 'default'.
bat restore dry-run           # Test first
```

### Get help
```bash
bat --help
bat -h
```

## Tuning

- `--brightness N` (10–100): Backlight in Extreme mode. Default 30.
- `--max-cpu N` (20–100): CPU frequency ceiling in Extreme mode. Default 50.
  - Note: Boost is already off on this machine, so 100% = base clock (~2.3 GHz), not turbo.
  - 50% ≈ 1.15 GHz. 35% ≈ 0.8 GHz (noticeably sluggish on 4K).

## Manual companions

These are *not* automated (and shouldn't be):
- **Armoury Crate:** Set Operating Mode to **Silent** and turn off **Aura lighting** (~0.5–1 W).
- **BIOS/Battery Health:** Enable Battery Health Charging at 60% or 80% (reduces wear; doesn't extend runtime).

## What gets stopped

**Gaming:** Steam, Riot Client, Discord  
**Work:** Notion, Figma, Viber, Microsoft Edge (can be disabled per session with `--include-edge`)  
**Cloud/Remote:** OneDrive, Proton VPN, AnyDesk  
**Peripherals:** LGHUB, PicPick, f.lux  

To customize, edit the `$KillGroups` hash in `battery-mode.ps1`.

## Troubleshooting

**"Cannot find battery-mode.ps1"**
- Ensure `BATTERY_MODE_HOME` is set: `echo $env:BATTERY_MODE_HOME` in a fresh PowerShell.
- Close and reopen the terminal if you just set it.
- Fallback: Edit `bat.cmd` line 19 to your actual install path.

**"Brightness not changing"**
- This machine's 4K panel misreports brightness via WMI. Brightness read shows 0 or stale values.
- Use `Fn+F7` / `Fn+F8` to adjust manually. The script skips it and warns you.

**GPU power draw looks implausible**
- `nvidia-smi` can report incorrect draws when idle or misaligned with battery controller.
- Check `Current draw` (battery controller total) instead. It's the ground truth.

## Requirements

- Windows 10/11
- PowerShell 5.1+ (Windows built-in; PowerShell 7 preferred)
- Administrator privileges (for `powercfg` changes)
- Intel CPU (if CPU frequency tuning is wanted; GPU settings work on NVIDIA too)

## License

MIT. See LICENSE file.

## Contributing

Found a bug or want to adapt this for other hardware? Issues and PRs welcome. Please test thoroughly on your machine first — power settings are security-sensitive in the sense that mistakes can degrade reliability or render a system unbootable in edge cases.

---

**Disclaimer:** This script changes OS-level power settings. Test with `dry-run` first. The author is not responsible for data loss, hardware damage, or unexpected system behavior. Use at your own risk.
