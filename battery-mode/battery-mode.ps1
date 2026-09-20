<#
.SYNOPSIS
    Extreme battery-saving mode for ASUS ROG Zephyrus M15 (GU502LV), with exact restore.

.DESCRIPTION
    Applies a set of reversible power-saving changes and, critically, records the
    machine's prior state to a JSON backup file BEFORE touching anything. Restoring
    reads that backup rather than any hardcoded defaults, so "Default" means "exactly
    what this machine had", not "what the script author guessed".

    Everything it changes is one of:
      - powercfg DC (on-battery) setting indexes on the currently active power scheme
      - the Windows power mode overlay (Best power efficiency)
      - display backlight brightness, via WMI
      - running background processes (stopped, never uninstalled, never unregistered
        from startup - they all come back on next launch or next sign-in)

    It deliberately does NOT touch: ASUS services (fan control, hotkeys, touchpad),
    device enable/disable state, CPU voltage, firmware, drivers, or the registry.

.PARAMETER Mode
    Extreme - back up current state, then apply battery-saving settings.
    Default - restore every value from the backup file.
    Status  - print current vs backed-up state. Changes nothing.

.PARAMETER DryRun
    Print every action that would be taken without performing any of them.
    Valid with Extreme and Default.

.PARAMETER IncludeEdge
    Also stop Microsoft Edge. Off by default: the background autolaunch process and
    your live browsing session share the msedge.exe name and cannot be distinguished,
    so enabling this closes open tabs.

.PARAMETER Brightness
    Backlight percentage to use in Extreme mode. Default 30.

.EXAMPLE
    bat status check-gpu
    bat extreme dry-run
    bat extreme
    bat restore

.NOTES
    Requires an elevated PowerShell session (powercfg /setdcvalueindex needs admin).

    Recommended manual companions, which this script intentionally does not automate:
      - Set Armoury Crate Operating Mode to Silent before running Extreme.
      - Turn off Aura keyboard lighting in Armoury Crate (~0.5-1 W).
      - Enable Battery Health Charging at 60% or 80%. That reduces further wear;
        it does not increase runtime.
#>

[CmdletBinding()]
param(
    # Everything is parsed by hand at the bottom of this file so the tool can be
    # driven as a normal CLI - "bat status check-gpu" - as well as in PowerShell
    # parameter style - "-Mode Status -CheckGpu". Both forms reach the same code.
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandLine = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$BackupPath = Join-Path $PSScriptRoot 'battery-state-backup.json'

# The name the shim is installed under. Referenced only in help text, so changing
# the shim's filename and this string together is all a rename takes.
$CliName = if ($env:BATTERY_MODE_NAME) { $env:BATTERY_MODE_NAME } else { 'bat' }

# Defaults. StrictMode requires these to exist before any function reads them; the
# argument parser at the bottom overwrites them before anything is dispatched.
$Mode        = $null
$DryRun      = $false
$IncludeEdge = $false
$CheckGpu    = $false
$Brightness  = 30
$MaxCpu      = 50

# ---------------------------------------------------------------------------
# Power settings table
#
# Each entry maps a friendly name to its powercfg subgroup/setting GUID pair and
# the value to apply in Extreme mode. Only the DC (on-battery) index is touched;
# AC behaviour is left completely alone so plugged-in performance is unchanged.
#
# Some of these settings are hidden by default on consumer systems. A missing
# setting is skipped with a warning rather than treated as a failure.
# ---------------------------------------------------------------------------
$PowerSettings = [ordered]@{
    # Overridden at runtime from -MaxCpu. Note that boost is already disabled on this
    # machine's Silent plan, so 100% here means the 2.3 GHz base clock, not the 5 GHz
    # turbo ceiling. That makes the percentage bite harder than it looks: 50% is about
    # 1.15 GHz, and 35% is about 0.8 GHz, which is noticeably sluggish on a 4K desktop.
    'ProcessorMaxState' = @{
        Subgroup = '54533251-82be-4824-96c1-47b60b740d00'
        Setting  = 'bc5038f7-23e0-4960-96da-33abaf5935ec'
        Extreme  = 50
        Units    = '%'
        Note     = 'Caps sustained clock. Currently 100% on battery.'
    }
    'ProcessorMinState' = @{
        Subgroup = '54533251-82be-4824-96c1-47b60b740d00'
        Setting  = '893dee8e-2bef-41e0-89c6-b55d0929964c'
        Extreme  = 5
        Units    = '%'
        Note     = 'Idle floor.'
    }
    'ProcessorBoostMode' = @{
        Subgroup = '54533251-82be-4824-96c1-47b60b740d00'
        Setting  = 'be337238-0d82-4146-a960-4f3749d470c7'
        Extreme  = 0
        Units    = 'mode'
        Note     = '0 = boost disabled.'
    }
    'DisplayOffTimeout' = @{
        Subgroup = '7516b95f-f776-4464-8c53-06167f40cc99'
        Setting  = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
        Extreme  = 60
        Units    = 'seconds'
        Note     = '4K backlight is the single largest idle draw.'
    }
    'SleepTimeout' = @{
        Subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
        Setting  = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
        Extreme  = 300
        Units    = 'seconds'
        Note     = 'Sleep after 5 minutes idle.'
    }
    'HibernateTimeout' = @{
        Subgroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
        Setting  = '9d7815a6-7ee4-497e-8888-515a05f02364'
        Extreme  = 600
        Units    = 'seconds'
        Note     = 'The Modern Standby drain fix: hibernate 10 minutes after sleeping.'
    }
    'DiskOffTimeout' = @{
        Subgroup = '0012ee47-9041-4b5d-9b77-535fba8b1442'
        Setting  = '6738e2c4-e8a5-4a42-b16a-e040e769756e'
        Extreme  = 60
        Units    = 'seconds'
        Note     = 'Minimal effect on NVMe, harmless.'
    }
    'UsbSelectiveSuspend' = @{
        Subgroup = '2a737441-1930-4402-8d77-b2bebba308a3'
        Setting  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
        Extreme  = 1
        Units    = 'enabled'
        Note     = '1 = suspend idle USB devices.'
    }
    'WirelessPowerSaving' = @{
        Subgroup = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
        Setting  = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
        Extreme  = 3
        Units    = 'level'
        Note     = '3 = maximum power saving. May slightly raise Wi-Fi latency.'
    }
    'PciExpressAspm' = @{
        Subgroup = '501a4d13-42af-4429-9fd1-a8218c268e20'
        Setting  = 'ee12f906-d277-404b-b6da-e5fa1a576df5'
        Extreme  = 2
        Units    = 'level'
        Note     = '2 = maximum power savings on the PCIe link.'
    }
}

# Windows power mode overlay GUIDs.
$OverlayBestEfficiency = '961cc777-2547-4f9d-8174-7d86181b8a7a'
$OverlayDefault        = '00000000-0000-0000-0000-000000000000'
$OverlayRegPath        = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'

# ---------------------------------------------------------------------------
# Background processes to stop in Extreme mode.
#
# These are stopped, not uninstalled and not removed from startup. Relaunch any of
# them normally, or sign out and back in, to get them all back.
# ---------------------------------------------------------------------------
$KillGroups = [ordered]@{
    'Gaming' = @{
        Processes = @('Steam', 'steamwebhelper', 'RiotClientServices', 'RiotClientUx',
                      'RiotClientUxRender', 'RiotClientCrashHandler', 'Discord')
        Warning   = $null
    }
    'Work' = @{
        Processes = @('Notion', 'Figma Agent', 'figma_agent', 'Viber', 'ViberPC')
        Warning   = 'Notion syncs to the cloud, but close it yourself first if you have unsaved edits.'
    }
    'CloudRemote' = @{
        Processes = @('OneDrive', 'ProtonVPN', 'ProtonVPN.Client', 'ProtonVPNService', 'AnyDesk')
        Warning   = 'Stopping Proton VPN drops your VPN protection. Stopping AnyDesk ends any remote session in progress.'
    }
    'Peripherals' = @{
        Processes = @('lghub', 'lghub_agent', 'lghub_updater', 'picpick', 'flux')
        Warning   = 'Logitech custom bindings and DPI profiles stop applying until LGHUB is relaunched. f.lux night colour shift stops.'
    }
}

$EdgeProcesses = @('msedge')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Test-Elevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ActiveSchemeGuid {
    $out = powercfg /getactivescheme 2>&1 | Out-String
    if ($out -match '([0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})') {
        return $Matches[1]
    }
    throw "Could not determine the active power scheme. powercfg said: $out"
}

function Get-SchemeName {
    param([string]$Guid)
    $out = powercfg /list 2>&1 | Out-String
    if ($out -match ([regex]::Escape($Guid) + '\s+\(([^)]+)\)')) { return $Matches[1] }
    return '(unnamed)'
}

# Reads the DC index for one setting. Returns $null when the setting does not exist
# on this system, which happens for settings hidden by the OEM power plan.
function Get-DcIndex {
    param([string]$Scheme, [string]$Subgroup, [string]$Setting)

    $out = powercfg /query $Scheme $Subgroup $Setting 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { return $null }
    if ($out -match 'Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)') {
        return [Convert]::ToInt64($Matches[1], 16)
    }
    return $null
}

function Set-DcIndex {
    param([string]$Scheme, [string]$Subgroup, [string]$Setting, [int64]$Value)

    $out = powercfg /setdcvalueindex $Scheme $Subgroup $Setting $Value 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg /setdcvalueindex failed for $Subgroup/$Setting : $out"
    }
}

# Returns $null when the backlight level cannot be trusted, in which case the script
# leaves brightness alone entirely.
#
# On this GU502LV the panel is driven through the Intel iGPU under Optimus and the
# ACPI brightness level reports as 0 while the screen is plainly lit and Active=True.
# A reported 0 therefore means "the driver is not telling us the truth", not "the
# backlight is off". Backing up a bogus 0 and later restoring it could black out the
# panel, so a 0 read disables brightness management in both directions.
function Get-CurrentBrightness {
    try {
        $b = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop |
             Select-Object -First 1
        $level = [int]$b.CurrentBrightness
        if ($level -le 0) { return $null }
        return $level
    } catch {
        return $null
    }
}

$Script:BrightnessSkipNotice = @'
  Brightness            SKIPPED - this panel does not report a usable backlight level
                        via WMI, so the script will not touch it in either direction.
                        Set it by hand with Fn+F7 / Fn+F8. Roughly 30% is the target;
                        on a 4K panel that is worth about 3-5 W, the single biggest win.
'@

function Set-Brightness {
    param([int]$Percent)
    try {
        $methods = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop |
                   Select-Object -First 1
        Invoke-CimMethod -InputObject $methods -MethodName WmiSetBrightness `
            -Arguments @{ Timeout = [uint32]0; Brightness = [byte]$Percent } | Out-Null
        return $true
    } catch {
        Write-Warning "Could not set brightness via WMI: $($_.Exception.Message)"
        Write-Warning "Adjust it with the Fn brightness keys instead."
        return $false
    }
}

# Design capacity is not readable from BatteryStaticData on this machine (the class
# raises a generic WMI error), so it is parsed out of a freshly generated battery
# report instead. Live draw comes from root/wmi BatteryStatus, which does work.
function Get-BatteryInfo {
    $info = @{ Design = $null; Full = $null; Remaining = $null; DrawMilliwatts = $null; Cycles = $null }

    try {
        $reportPath = Join-Path $env:TEMP 'battery-mode-report.html'
        powercfg /batteryreport /output $reportPath 2>&1 | Out-Null
        if (Test-Path $reportPath) {
            $html = Get-Content $reportPath -Raw
            if ($html -match 'DESIGN CAPACITY.*?([\d,]+)\s*mWh') {
                $info.Design = [int64]($Matches[1] -replace ',', '')
            }
            if ($html -match 'FULL CHARGE CAPACITY.*?([\d,]+)\s*mWh') {
                $info.Full = [int64]($Matches[1] -replace ',', '')
            }
            if ($html -match 'CYCLE COUNT.*?<td[^>]*>(\d+)') {
                $info.Cycles = [int]$Matches[1]
            }
            Remove-Item $reportPath -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # Report generation is best-effort; the live figures below are the useful part.
    }

    try {
        $status = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction Stop |
                  Select-Object -First 1
        $info.Remaining = [int64]$status.RemainingCapacity
        if (-not $status.Charging) { $info.DrawMilliwatts = [int64]$status.DischargeRate }
    } catch {
        # No battery present, or the class is unavailable.
    }

    return $info
}

function Get-OverlayGuid {
    try {
        $v = Get-ItemProperty -Path $OverlayRegPath -Name 'ActiveOverlayDcPowerScheme' -ErrorAction Stop
        return [string]$v.ActiveOverlayDcPowerScheme
    } catch {
        return $OverlayDefault
    }
}

function Set-Overlay {
    param([string]$Guid)
    $out = powercfg /setactiveoverlayscheme $Guid 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not set the power mode overlay to $Guid. This is non-fatal; ASUS plans sometimes suppress the overlay. powercfg said: $($out.Trim())"
        return $false
    }
    return $true
}

function Get-KillList {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($group in $KillGroups.Values) {
        foreach ($p in $group.Processes) { $list.Add($p) }
    }
    if ($IncludeEdge) {
        foreach ($p in $EdgeProcesses) { $list.Add($p) }
    }
    return $list
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------

function Show-Status {
    $scheme = Get-ActiveSchemeGuid
    Write-Host ""
    Write-Host "Active power scheme : $(Get-SchemeName $scheme)" -ForegroundColor Cyan
    Write-Host "                      $scheme"

    $backup = $null
    if (Test-Path $BackupPath) {
        $backup = Get-Content $BackupPath -Raw | ConvertFrom-Json
        Write-Host "Recorded state      : $($backup.State) (saved $($backup.SavedAt))" -ForegroundColor Cyan
    } else {
        Write-Host "Recorded state      : Default (no backup file yet)" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host ("{0,-22} {1,12} {2,12}" -f 'Setting', 'Current DC', 'Backed up') -ForegroundColor DarkGray
    Write-Host ("-" * 50) -ForegroundColor DarkGray

    foreach ($name in $PowerSettings.Keys) {
        $s = $PowerSettings[$name]
        $current = Get-DcIndex -Scheme $scheme -Subgroup $s.Subgroup -Setting $s.Setting
        $saved = '-'
        if ($backup -and ($backup.PowerSettings.PSObject.Properties.Name -contains $name)) {
            $saved = $backup.PowerSettings.$name
        }
        $cur = if ($null -eq $current) { 'n/a' } else { $current }
        Write-Host ("{0,-22} {1,12} {2,12}" -f $name, $cur, $saved)
    }

    $bright = Get-CurrentBrightness
    $savedBright = if ($backup -and $null -ne $backup.Brightness) { "$($backup.Brightness)%" } else { '-' }
    Write-Host ("{0,-22} {1,12} {2,12}" -f 'Brightness',
        $(if ($null -eq $bright) { 'unmanaged' } else { "$bright%" }), $savedBright)

    $overlay = Get-OverlayGuid
    Write-Host ""
    Write-Host "Power mode overlay  : $overlay"
    if ($overlay -eq $OverlayBestEfficiency) { Write-Host "                      (Best power efficiency)" -ForegroundColor DarkGray }
    if ($backup) { Write-Host "Backed-up overlay   : $($backup.Overlay)" }

    # Live draw is the number worth watching: run Status before and after Extreme mode
    # and compare the watts. Health is shown because it caps everything else.
    $bat = Get-BatteryInfo
    Write-Host ""
    if ($null -ne $bat.DrawMilliwatts -and $bat.DrawMilliwatts -gt 0) {
        $watts = [math]::Round($bat.DrawMilliwatts / 1000.0, 1)
        Write-Host "Current draw        : $watts W" -ForegroundColor Yellow
        if ($null -ne $bat.Remaining) {
            $hours = [math]::Round($bat.Remaining / [double]$bat.DrawMilliwatts, 1)
            Write-Host "Est. remaining      : $hours h at this draw ($($bat.Remaining) mWh left)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Current draw        : n/a (on AC power - unplug to measure)" -ForegroundColor DarkGray
    }

    if ($null -ne $bat.Design -and $bat.Design -gt 0 -and $null -ne $bat.Full) {
        $health = [math]::Round(100 * $bat.Full / $bat.Design, 1)
        $cyc = if ($null -ne $bat.Cycles) { ", $($bat.Cycles) cycles" } else { "" }
        Write-Host "Battery health      : $health%  ($($bat.Full) of $($bat.Design) mWh design$cyc)" -ForegroundColor Yellow
    }

    if ($CheckGpu) { Show-GpuState -SystemDrawMilliwatts $bat.DrawMilliwatts }
    Write-Host ""
}

# Off by default and deliberately opt-in, because querying the discrete GPU wakes it
# out of its low-power state. The measurement itself costs battery.
#
# On this GU502LV the reported figure is worse than merely noisy: nvidia-smi has been
# observed claiming ~9.9 W for the GPU while the whole laptop was drawing 11.4 W from
# the battery, which would leave 1.5 W for the CPU, 4K panel and everything else. That
# is impossible, so the number is not a real power measurement here. The cross-check
# below catches exactly that case rather than letting the reading drive decisions.
function Show-GpuState {
    param([Nullable[int64]]$SystemDrawMilliwatts)

    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if (-not $smi) {
        $candidate = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if (Test-Path $candidate) { $smi = $candidate } else { return }
    } else {
        $smi = $smi.Source
    }

    Write-Host ""
    Write-Host "Discrete GPU (this query itself wakes the GPU):" -ForegroundColor DarkYellow
    try {
        $csv = & $smi --query-gpu=name,pstate,power.draw,utilization.gpu --format=csv,noheader
        foreach ($line in $csv) { Write-Host "  $line" }

        # Sanity-check the reported GPU draw against the whole machine's draw. If the
        # GPU alone claims most of the system total, the sensor is not telling the truth
        # and no conclusion should be drawn from it.
        $gpuWatts = $null
        if ($csv -is [array]) { $first = $csv[0] } else { $first = $csv }
        if ($first -match ',\s*([\d.]+)\s*W\s*,') { $gpuWatts = [double]$Matches[1] }

        if ($null -ne $gpuWatts -and $null -ne $SystemDrawMilliwatts -and $SystemDrawMilliwatts -gt 0) {
            $sysWatts = $SystemDrawMilliwatts / 1000.0
            if ($gpuWatts -ge ($sysWatts * 0.7)) {
                Write-Host ""
                Write-Host "  IMPLAUSIBLE: GPU claims $gpuWatts W of a $([math]::Round($sysWatts,1)) W system total." -ForegroundColor Red
                Write-Host "  That leaves too little for the CPU and 4K panel, so this sensor is" -ForegroundColor Red
                Write-Host "  unreliable on this machine. Ignore the wattage. Judge the dGPU by" -ForegroundColor Red
                Write-Host "  whether the system total in 'Current draw' actually falls when you" -ForegroundColor Red
                Write-Host "  close Electron and Chromium apps - that number comes from the battery" -ForegroundColor Red
                Write-Host "  controller and is trustworthy." -ForegroundColor Red
                return
            }
        }

        Write-Host "  A sustained idle draw above ~5 W with 0% utilisation means something is" -ForegroundColor DarkGray
        Write-Host "  pinning the RTX 2060 awake. Usual culprits are Electron and Chromium apps." -ForegroundColor DarkGray
        Write-Host "  Fix in Settings > Display > Graphics: set them to 'Power saving'." -ForegroundColor DarkGray
    } catch {
        Write-Warning "  nvidia-smi failed: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Extreme
# ---------------------------------------------------------------------------

function Invoke-ExtremeMode {
    $scheme = Get-ActiveSchemeGuid
    $schemeName = Get-SchemeName $scheme

    # Guard against the one way this script could destroy your defaults: running
    # Extreme twice would otherwise capture the already-extreme values as the
    # "default" to restore later.
    if (Test-Path $BackupPath) {
        $existing = Get-Content $BackupPath -Raw | ConvertFrom-Json
        if ($existing.State -eq 'Extreme') {
            Write-Host ""
            Write-Host "Already in Extreme mode (backup from $($existing.SavedAt) holds your defaults)." -ForegroundColor Yellow
            Write-Host "Refusing to re-apply, because that would overwrite the backup with extreme values."
            Write-Host "Run -Mode Default first if you want to reapply from a clean state."
            Write-Host ""
            return
        }
    }

    Write-Host ""
    Write-Host "Applying Extreme battery mode to scheme '$schemeName'" -ForegroundColor Green
    if ($DryRun) { Write-Host "DRY RUN - nothing will actually change." -ForegroundColor Magenta }
    Write-Host ""

    $backup = [ordered]@{
        State         = 'Extreme'
        SavedAt       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        SchemeGuid    = $scheme
        SchemeName    = $schemeName
        Overlay       = Get-OverlayGuid
        Brightness    = Get-CurrentBrightness
        PowerSettings = [ordered]@{}
        KilledApps    = @()
    }

    # Pass 1: read and record everything before writing anything.
    foreach ($name in $PowerSettings.Keys) {
        $s = $PowerSettings[$name]
        $current = Get-DcIndex -Scheme $scheme -Subgroup $s.Subgroup -Setting $s.Setting
        if ($null -eq $current) {
            Write-Warning "$name is not exposed on this system - skipping."
            continue
        }
        $backup.PowerSettings[$name] = $current
    }

    if (-not $DryRun) {
        $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupPath -Encoding UTF8
        Write-Host "Backup written to $BackupPath" -ForegroundColor DarkGray
        Write-Host ""
    }

    # Pass 2: apply.
    foreach ($name in @($backup.PowerSettings.Keys)) {
        $s = $PowerSettings[$name]
        $from = $backup.PowerSettings[$name]
        $to = $s.Extreme
        Write-Host ("  {0,-22} {1} -> {2} {3}" -f $name, $from, $to, $s.Units)
        if (-not $DryRun) {
            try {
                Set-DcIndex -Scheme $scheme -Subgroup $s.Subgroup -Setting $s.Setting -Value $to
            } catch {
                Write-Warning "  Failed to set $name : $($_.Exception.Message)"
            }
        }
    }

    Write-Host ("  {0,-22} {1} -> {2}" -f 'PowerModeOverlay', $backup.Overlay, $OverlayBestEfficiency)
    if (-not $DryRun) { Set-Overlay $OverlayBestEfficiency | Out-Null }

    if ($null -ne $backup.Brightness) {
        Write-Host ("  {0,-22} {1}% -> {2}%" -f 'Brightness', $backup.Brightness, $Brightness)
        if (-not $DryRun) { Set-Brightness -Percent $Brightness | Out-Null }
    } else {
        Write-Host $Script:BrightnessSkipNotice -ForegroundColor Yellow
    }

    if (-not $DryRun) {
        powercfg /setactive $scheme 2>&1 | Out-Null
    }

    # Pass 3: stop background apps.
    Write-Host ""
    Write-Host "Stopping background apps:" -ForegroundColor Green
    foreach ($groupName in $KillGroups.Keys) {
        $group = $KillGroups[$groupName]
        if ($group.Warning) { Write-Host "  [$groupName] $($group.Warning)" -ForegroundColor Yellow }
    }
    if ($IncludeEdge) {
        Write-Host "  [Edge] -IncludeEdge is set: open Edge tabs will be closed." -ForegroundColor Yellow
    }
    Write-Host ""

    $killed = New-Object System.Collections.Generic.List[string]
    foreach ($procName in (Get-KillList)) {
        $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) { continue }
        Write-Host ("  stop {0} ({1} process(es))" -f $procName, $procs.Count)
        if (-not $DryRun) {
            foreach ($p in $procs) {
                try {
                    $p.CloseMainWindow() | Out-Null
                    Start-Sleep -Milliseconds 200
                    $p.Refresh()
                    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction Stop }
                } catch {
                    Write-Warning "  Could not stop $procName (PID $($p.Id)): $($_.Exception.Message)"
                }
            }
        }
        $killed.Add($procName)
    }
    if ($killed.Count -eq 0) { Write-Host "  (nothing from the kill list was running)" }

    if (-not $DryRun) {
        $backup.KilledApps = @($killed)
        $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupPath -Encoding UTF8
    }

    Write-Host ""
    if ($DryRun) {
        Write-Host "Dry run complete. NOTHING was changed and no backup was written." -ForegroundColor Magenta
        Write-Host "Run '$CliName extreme' without 'dry-run' to apply the above for real." -ForegroundColor Magenta
    } else {
        Write-Host "Extreme mode active. Restore with: $CliName restore" -ForegroundColor Green
        Write-Host "Still worth doing by hand in Armoury Crate: Operating Mode = Silent, Aura lighting off." -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Default (restore)
# ---------------------------------------------------------------------------

function Invoke-DefaultMode {
    if (-not (Test-Path $BackupPath)) {
        Write-Host ""
        Write-Host "No backup file found at $BackupPath" -ForegroundColor Red
        Write-Host "Nothing to restore from. If the machine is in a state you dislike, open"
        Write-Host "Control Panel > Power Options, pick Balanced, and use 'Restore plan defaults'."
        Write-Host ""
        return
    }

    $backup = Get-Content $BackupPath -Raw | ConvertFrom-Json

    if ($backup.State -eq 'Default') {
        Write-Host ""
        Write-Host "Backup already marked as restored ($($backup.SavedAt)). Re-applying anyway is harmless." -ForegroundColor Yellow
    }

    $scheme = $backup.SchemeGuid
    Write-Host ""
    Write-Host "Restoring scheme '$($backup.SchemeName)' from backup saved $($backup.SavedAt)" -ForegroundColor Green
    if ($DryRun) { Write-Host "DRY RUN - nothing will actually change." -ForegroundColor Magenta }
    Write-Host ""

    foreach ($prop in $backup.PowerSettings.PSObject.Properties) {
        $name = $prop.Name
        $value = [int64]$prop.Value
        if (-not $PowerSettings.Contains($name)) {
            Write-Warning "Backup contains unknown setting '$name' - skipping."
            continue
        }
        $s = $PowerSettings[$name]
        $current = Get-DcIndex -Scheme $scheme -Subgroup $s.Subgroup -Setting $s.Setting
        Write-Host ("  {0,-22} {1} -> {2} {3}" -f $name, $current, $value, $s.Units)
        if (-not $DryRun) {
            try {
                Set-DcIndex -Scheme $scheme -Subgroup $s.Subgroup -Setting $s.Setting -Value $value
            } catch {
                Write-Warning "  Failed to restore $name : $($_.Exception.Message)"
            }
        }
    }

    Write-Host ("  {0,-22} -> {1}" -f 'PowerModeOverlay', $backup.Overlay)
    if (-not $DryRun) { Set-Overlay $backup.Overlay | Out-Null }

    if ($null -ne $backup.Brightness) {
        Write-Host ("  {0,-22} -> {1}%" -f 'Brightness', $backup.Brightness)
        if (-not $DryRun) { Set-Brightness -Percent ([int]$backup.Brightness) | Out-Null }
    } else {
        Write-Host $Script:BrightnessSkipNotice -ForegroundColor Yellow
    }

    if (-not $DryRun) {
        powercfg /setactive $scheme 2>&1 | Out-Null
        $backup.State = 'Default'
        $backup.SavedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        $backup | ConvertTo-Json -Depth 5 | Set-Content -Path $BackupPath -Encoding UTF8
    }

    # Apps are deliberately not relaunched: their install paths and expected launch
    # arguments vary, and starting the wrong binary is worse than starting none.
    $killed = @($backup.KilledApps)
    if ($killed.Count -gt 0) {
        Write-Host ""
        Write-Host "These apps were stopped and are NOT restarted automatically:" -ForegroundColor Yellow
        Write-Host "  $($killed -join ', ')"
        Write-Host "  Relaunch the ones you want, or sign out and back in to get them all."
    }

    Write-Host ""
    if ($DryRun) {
        Write-Host "Dry run complete. NOTHING was changed and the backup was left untouched." -ForegroundColor Magenta
        Write-Host "Run '$CliName restore' without 'dry-run' to apply the above for real." -ForegroundColor Magenta
    } else {
        Write-Host "Restored. Check the result with: $CliName status" -ForegroundColor Green
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

function Show-Help {
    Write-Host ""
    Write-Host "$CliName - battery mode switcher for the ROG Zephyrus M15 (GU502LV)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE" -ForegroundColor Yellow
    Write-Host "  $CliName <command> [options]"
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor Yellow
    Write-Host "  status      Show current power settings, live draw and battery health."
    Write-Host "              Read-only. The only command that does not need admin."
    Write-Host "  extreme     Back up the current state, then apply battery-saving settings."
    Write-Host "  restore     Restore every value from the backup file."
    Write-Host "              Also spelled 'default'."
    Write-Host "  help        Show this text."
    Write-Host ""
    Write-Host "OPTIONS" -ForegroundColor Yellow
    Write-Host "  check-gpu           status only. Report discrete GPU power state."
    Write-Host "                      Opt-in because the query itself wakes the GPU."
    Write-Host "  dry-run             extreme/restore only. Print actions, change nothing."
    Write-Host "  include-edge        extreme only. Also close Microsoft Edge."
    Write-Host "                      Off by default: this closes your open tabs."
    Write-Host "  max-cpu <20-100>    extreme only. CPU ceiling percent. Default 50."
    Write-Host "                      Boost is already off, so 100% is the 2.3 GHz base,"
    Write-Host "                      not the 5 GHz turbo. 35% is roughly 0.8 GHz."
    Write-Host "  brightness <10-100> extreme only. Target backlight percent. Default 30."
    Write-Host "                      Ignored on panels that misreport their level."
    Write-Host ""
    Write-Host "  Options also accept --dashed and -PowerShellStyle spellings."
    Write-Host ""
    Write-Host "EXAMPLES" -ForegroundColor Yellow
    Write-Host "  $CliName status check-gpu"
    Write-Host "  $CliName extreme dry-run"
    Write-Host "  $CliName extreme max-cpu 35"
    Write-Host "  $CliName restore"
    Write-Host ""
    Write-Host "NOTES" -ForegroundColor Yellow
    Write-Host "  Backup file : $BackupPath"
    Write-Host "  Script      : $PSCommandPath"
    Write-Host "  Running 'extreme' twice is refused, so the backup can never be"
    Write-Host "  overwritten with already-extreme values."
    Write-Host ""
}

# Normalises a token to a canonical lower-case flag name: "--dry-run", "dry-run"
# and "-DryRun" all collapse to "dryrun".
function ConvertTo-FlagKey {
    param([string]$Token)
    $t = $Token -replace '^--?', ''
    $t = $t -replace '[-_]', ''
    return $t.ToLowerInvariant()
}

# Reads the value token following a flag, validating range. Exits on bad input.
function Read-IntArg {
    param([string[]]$Tokens, [ref]$Index, [string]$FlagName, [int]$Min, [int]$Max)
    $Index.Value++
    if ($Index.Value -ge $Tokens.Count) {
        Write-Host "Missing value after '$FlagName'." -ForegroundColor Red
        exit 2
    }
    $raw = $Tokens[$Index.Value]
    $parsed = 0
    if (-not [int]::TryParse($raw, [ref]$parsed) -or $parsed -lt $Min -or $parsed -gt $Max) {
        Write-Host "$FlagName must be a whole number from $Min to $Max, got '$raw'." -ForegroundColor Red
        exit 2
    }
    $Index.Value++
    return $parsed
}

$verbs = @{ 'status' = 'Status'; 'extreme' = 'Extreme'; 'default' = 'Default'
            'restore' = 'Default'; 'help' = 'Help' }

$i = 0
$tokens = @($CommandLine)
while ($i -lt $tokens.Count) {
    $raw = $tokens[$i]
    $key = ConvertTo-FlagKey $raw

    # A value for -Mode / mode, so "bat -Mode Status" keeps working.
    if ($key -eq 'mode') {
        $i++
        if ($i -ge $tokens.Count) { Write-Host "Missing value after '$raw'." -ForegroundColor Red; exit 2 }
        $key = ConvertTo-FlagKey $tokens[$i]
        if (-not $verbs.ContainsKey($key)) { Write-Host "Unknown mode '$($tokens[$i])'." -ForegroundColor Red; exit 2 }
        $Mode = $verbs[$key]
        $i++
        continue
    }

    if ($verbs.ContainsKey($key) -and $null -eq $Mode) { $Mode = $verbs[$key]; $i++; continue }

    # if/elseif rather than switch: PowerShell's switch is itself a loop, so a
    # 'continue' inside it would target the switch and not this while loop.
    if     ($key -eq 'dryrun')      { $DryRun = $true;      $i++ }
    elseif ($key -eq 'checkgpu')    { $CheckGpu = $true;    $i++ }
    elseif ($key -eq 'includeedge') { $IncludeEdge = $true; $i++ }
    elseif ($key -eq 'h')           { $Mode = 'Help';       $i++ }
    elseif ($key -eq 'maxcpu')      { $MaxCpu     = Read-IntArg $tokens ([ref]$i) 'max-cpu' 20 100 }
    elseif ($key -eq 'brightness')  { $Brightness = Read-IntArg $tokens ([ref]$i) 'brightness' 10 100 }
    else {
        Write-Host ""
        Write-Host "Unknown argument '$raw'." -ForegroundColor Red
        Write-Host "Run '$CliName help' for usage."
        Write-Host ""
        exit 2
    }
}

if ($null -eq $Mode) { $Mode = 'Help' }

if ($Mode -eq 'Help') { Show-Help; exit 0 }

# Reject options that do not apply to the chosen command, rather than silently
# ignoring them and leaving the user thinking they took effect.
if ($Mode -eq 'Status' -and ($DryRun -or $IncludeEdge)) {
    Write-Host "'dry-run' and 'include-edge' do not apply to 'status' - it never changes anything." -ForegroundColor Red
    exit 2
}
if ($Mode -ne 'Status' -and $CheckGpu) {
    Write-Host "'check-gpu' applies to 'status' only. Run: $CliName status check-gpu" -ForegroundColor Red
    exit 2
}
if ($Mode -eq 'Default' -and $IncludeEdge) {
    Write-Host "'include-edge' does not apply to 'default' - it restores, it never closes apps." -ForegroundColor Red
    exit 2
}

# Let max-cpu drive the CPU ceiling without editing the settings table.
$PowerSettings['ProcessorMaxState'].Extreme = $MaxCpu

if ($Mode -ne 'Status' -and -not (Test-Elevated)) {
    Write-Host ""
    Write-Host "This needs an elevated session." -ForegroundColor Red
    Write-Host "powercfg /setdcvalueindex requires administrator rights."
    Write-Host ""
    Write-Host "Open an admin terminal (Win+X, then 'Terminal (Admin)') and run:"
    Write-Host "  $CliName $($Mode.ToLowerInvariant())"
    Write-Host ""
    exit 1
}

switch ($Mode) {
    'Status'  { Show-Status }
    'Extreme' { Invoke-ExtremeMode }
    'Default' { Invoke-DefaultMode }
}
