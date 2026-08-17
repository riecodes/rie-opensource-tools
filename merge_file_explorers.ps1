# merge_file_explorers.ps1
# Merges every open File Explorer folder window into a single tabbed window.
#
# made with loving prompts by riecodes

[CmdletBinding()]
param(
    # Run without the spinning ASCII folder and progress bar.
    [Alias('NoSplash')]
    [switch]$NoAnimation,

    # Skip the "press any key to continue" prompt at the end.
    [switch]$NoPause,

    # Multiplies every wait. Raise it if Explorer is slow to settle on your machine.
    [ValidateRange(0.25, 10.0)]
    [double]$DelayScale = 1.0,

    # Log what every step actually observed. Implies -NoAnimation, since the
    # trace and the spinning folder cannot share the console.
    [switch]$Trace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class ExplorerWindowControl
{
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr GetTopWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    // Used only to hand focus back to this console once the merge is finished.
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    // Top-level windows, front to back. Used to break a tie between candidate
    // destination windows in favour of the one you used most recently.
    public static IntPtr[] WindowsFrontToBack()
    {
        var order = new List<IntPtr>();
        IntPtr current = GetTopWindow(IntPtr.Zero);
        while (current != IntPtr.Zero)
        {
            order.Add(current);
            current = GetWindow(current, 2); // GW_HWNDNEXT
        }
        return order.ToArray();
    }
}

// A donut.c style renderer, except the solid is a 2D folder icon extruded into a
// slab and spun sideways around its vertical axis.
public static class FolderSpinner
{
    private const string Shades = ".,-~:;=!*#$@";
    private const string Watermark = "made with loving prompts by riecodes";

    // Half thickness of the slab and the bulge of its two big faces.
    private const double Thickness = 0.18;
    private const double BulgeU = 0.30;
    private const double BulgeV = 0.20;

    // Folder outline: a body rectangle with a tab sitting on its top-left.
    private const double BodyLeft = -1.00;
    private const double BodyRight = 1.00;
    private const double BodyBottom = -0.75;
    private const double BodyTop = 0.45;
    private const double TabRight = -0.15;
    private const double TabTop = 0.75;

    // The bottom three rows of every frame are reserved for the progress bar,
    // the status line, and the watermark.
    public const int ReservedRows = 4;

    private static double[] _px, _py, _pz, _nx, _ny, _nz;

    private static bool Inside(double u, double v)
    {
        if (u >= BodyLeft && u <= BodyRight && v >= BodyBottom && v <= BodyTop) return true;
        if (u >= BodyLeft && u <= TabRight && v > BodyTop && v <= TabTop) return true;
        return false;
    }

    // Face displacement, so the flat sides catch a shading gradient instead of
    // rendering as one solid block of the same character.
    private static double Face(double u, double v)
    {
        return Thickness * (1.0 - BulgeU * u * u - BulgeV * v * v);
    }

    private static void Emit(List<double> pts, List<double> nrm,
                             double x, double y, double z,
                             double nx, double ny, double nz)
    {
        double len = Math.Sqrt(nx * nx + ny * ny + nz * nz);
        if (len < 1e-9) return;
        pts.Add(x); pts.Add(y); pts.Add(z);
        nrm.Add(nx / len); nrm.Add(ny / len); nrm.Add(nz / len);
    }

    public static void Build()
    {
        if (_px != null) return;

        var pts = new List<double>();
        var nrm = new List<double>();

        // Front and back faces.
        for (double v = BodyBottom; v <= TabTop + 1e-9; v += 0.034)
        {
            for (double u = BodyLeft; u <= BodyRight + 1e-9; u += 0.028)
            {
                if (!Inside(u, v)) continue;

                double f = Face(u, v);
                double fu = Thickness * (-2.0 * BulgeU * u);
                double fv = Thickness * (-2.0 * BulgeV * v);

                // Viewer sits on the -z side, so the front face is at -f.
                Emit(pts, nrm, u, v, -f, -fu, -fv, -1.0);
                Emit(pts, nrm, u, v, f, -fu, -fv, 1.0);
            }
        }

        // Side walls, walked as a counter-clockwise outline so the outward
        // normal of each segment is simply (dy, -dx).
        double[,] outline = new double[,]
        {
            { BodyLeft, BodyBottom }, { BodyRight, BodyBottom },
            { BodyRight, BodyTop }, { TabRight, BodyTop },
            { TabRight, TabTop }, { BodyLeft, TabTop }
        };

        int corners = outline.GetLength(0);
        for (int i = 0; i < corners; i++)
        {
            int j = (i + 1) % corners;
            double ax = outline[i, 0], ay = outline[i, 1];
            double bx = outline[j, 0], by = outline[j, 1];
            double dx = bx - ax, dy = by - ay;
            double segLen = Math.Sqrt(dx * dx + dy * dy);
            int steps = Math.Max(2, (int)(segLen / 0.028));

            for (int s = 0; s <= steps; s++)
            {
                double t = (double)s / steps;
                double u = ax + dx * t;
                double v = ay + dy * t;
                double f = Face(u, v);
                int zSteps = Math.Max(2, (int)(2.0 * f / 0.030));

                for (int k = 0; k <= zSteps; k++)
                {
                    double z = -f + 2.0 * f * k / zSteps;
                    Emit(pts, nrm, u, v, z, dy, -dx, 0.0);
                }
            }
        }

        int count = pts.Count / 3;
        _px = new double[count]; _py = new double[count]; _pz = new double[count];
        _nx = new double[count]; _ny = new double[count]; _nz = new double[count];
        for (int i = 0; i < count; i++)
        {
            _px[i] = pts[i * 3]; _py[i] = pts[i * 3 + 1]; _pz[i] = pts[i * 3 + 2];
            _nx[i] = nrm[i * 3]; _ny[i] = nrm[i * 3 + 1]; _nz[i] = nrm[i * 3 + 2];
        }
    }

    private static void Stamp(char[] buffer, int stride, int width, int row, string text)
    {
        if (row < 0 || string.IsNullOrEmpty(text) || text.Length > width) return;
        int start = row * stride + (width - text.Length) / 2;
        for (int i = 0; i < text.Length; i++) buffer[start + i] = text[i];
    }

    // Renders one frame into a newline separated buffer of `height` rows: the
    // spinning folder, then the progress bar, status line, and watermark.
    public static char[] Frame(double angle, int width, int height,
                               string progressLine, string statusLine)
    {
        Build();

        int stride = width + 1;
        int artRows = height - ReservedRows;
        var buffer = new char[stride * height];
        var depth = new double[width * artRows];

        double cx = width / 2.0;
        double cy = artRows / 2.0;
        double cameraDistance = 4.6;
        double scale = width * 1.55;

        // Light from the upper left, on the viewer's side of the slab.
        double lx = -0.35, ly = 0.55, lz = -0.76;
        double lLen = Math.Sqrt(lx * lx + ly * ly + lz * lz);
        lx /= lLen; ly /= lLen; lz /= lLen;

        // A fixed downward tilt so the spin reads as 3D rather than a flip.
        double tilt = 0.30;
        double tiltCos = Math.Cos(tilt), tiltSin = Math.Sin(tilt);

        double ca = Math.Cos(angle), sa = Math.Sin(angle);

        for (int i = 0; i < buffer.Length; i++) buffer[i] = ' ';
        for (int r = 0; r < height; r++) buffer[r * stride + width] = '\n';

        for (int i = 0; i < _px.Length; i++)
        {
            // Spin around the vertical axis, then apply the fixed tilt.
            double x = _px[i] * ca + _pz[i] * sa;
            double zy = -_px[i] * sa + _pz[i] * ca;
            double y = _py[i] * tiltCos - zy * tiltSin;
            double z = _py[i] * tiltSin + zy * tiltCos;

            double nxr = _nx[i] * ca + _nz[i] * sa;
            double nzy = -_nx[i] * sa + _nz[i] * ca;
            double nyr = _ny[i] * tiltCos - nzy * tiltSin;
            double nzr = _ny[i] * tiltSin + nzy * tiltCos;

            double lum = nxr * lx + nyr * ly + nzr * lz;
            if (lum <= 0.0) continue;

            double ooz = 1.0 / (cameraDistance + z);
            int sx = (int)Math.Round(cx + scale * ooz * x);
            int sy = (int)Math.Round(cy - scale * 0.5 * ooz * y);
            if (sx < 0 || sx >= width || sy < 0 || sy >= artRows) continue;

            int cell = sy * width + sx;
            if (ooz <= depth[cell]) continue;

            depth[cell] = ooz;
            int shade = (int)(lum * (Shades.Length - 1) + 0.5);
            if (shade < 0) shade = 0;
            if (shade > Shades.Length - 1) shade = Shades.Length - 1;
            buffer[sy * stride + sx] = Shades[shade];
        }

        Stamp(buffer, stride, width, height - 3, progressLine);
        Stamp(buffer, stride, width, height - 2, statusLine);
        Stamp(buffer, stride, width, height - 1, Watermark);
        return buffer;
    }
}

// Owns a fixed block of console rows and keeps the folder spinning while the
// merge runs. Every wait the merge would have spent in Start-Sleep is spent in
// Pump instead, so the animation is the progress indicator rather than an intro.
public static class MergeDisplay
{
    private const int FrameMilliseconds = 28;

    private static bool _active;
    private static bool _cursorHidden;
    private static int _width, _height, _top;
    private static int _total, _done;
    private static string _status = string.Empty;
    private static Stopwatch _clock;

    public static bool IsActive { get { return _active; } }

    // Reserves the console rows and starts the clock. Falls back to inactive
    // (Pump degrades to a plain sleep) on a redirected or undersized console.
    public static void Start(int totalSteps)
    {
        _total = Math.Max(1, totalSteps);
        _done = 0;
        _status = string.Empty;
        _active = false;

        if (Console.IsOutputRedirected) return;

        try
        {
            _width = Math.Min(80, Math.Max(40, Console.WindowWidth - 1));
            _height = Math.Min(26, Math.Max(16, Console.WindowHeight - 3));
        }
        catch { return; }

        if (_width < 40 || _height < 16) return;

        FolderSpinner.Build();

        try { Console.CursorVisible = false; _cursorHidden = true; } catch { }

        try
        {
            Console.Write(new string('\n', _height));
            _top = Math.Max(0, Console.CursorTop - _height);
        }
        catch
        {
            if (_cursorHidden) { try { Console.CursorVisible = true; } catch { } _cursorHidden = false; }
            return;
        }

        _clock = Stopwatch.StartNew();
        _active = true;
        Draw();
    }

    public static void SetStatus(string text)
    {
        _status = text == null ? string.Empty : text;
        Draw();
    }

    public static void SetProgress(int done)
    {
        _done = done < 0 ? 0 : (done > _total ? _total : done);
        Draw();
    }

    // Renders frames for the given duration. This replaces every Start-Sleep in
    // the merge path, which is what keeps the folder spinning during the work.
    public static void Pump(int milliseconds)
    {
        if (milliseconds <= 0) return;

        if (!_active)
        {
            Thread.Sleep(milliseconds);
            return;
        }

        var elapsed = Stopwatch.StartNew();
        while (true)
        {
            Draw();
            long remaining = milliseconds - elapsed.ElapsedMilliseconds;
            if (remaining <= 0) break;
            Thread.Sleep((int)Math.Min(FrameMilliseconds, remaining));
        }
    }

    // Releases the console rows, leaving the last frame on screen.
    public static void Stop()
    {
        if (_active)
        {
            Draw();
            try
            {
                Console.SetCursorPosition(0, Math.Min(_top + _height, Console.BufferHeight - 1));
                Console.WriteLine();
            }
            catch { }
            _active = false;
        }

        if (_cursorHidden)
        {
            try { Console.CursorVisible = true; } catch { }
            _cursorHidden = false;
        }
    }

    private static string BuildProgressLine()
    {
        double fraction = (double)_done / _total;
        int barWidth = Math.Max(10, Math.Min(46, _width - 24));
        int filled = (int)Math.Round(fraction * barWidth);
        if (filled < 0) filled = 0;
        if (filled > barWidth) filled = barWidth;

        return "[" + new string('#', filled) + new string('-', barWidth - filled) + "] "
             + _done + "/" + _total + "  " + (int)Math.Round(fraction * 100) + "%";
    }

    // Middle-elides long folder paths so the status line always fits the frame.
    private static string Fit(string text, int width)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        if (text.Length <= width) return text;
        if (width <= 3) return text.Substring(0, Math.Max(0, width));

        int keep = width - 3;
        int left = keep / 2;
        return text.Substring(0, left) + "..." + text.Substring(text.Length - (keep - left));
    }

    private static void Draw()
    {
        if (!_active) return;

        char[] buffer = FolderSpinner.Frame(
            _clock.Elapsed.TotalSeconds * 2.1, _width, _height,
            BuildProgressLine(), Fit(_status, _width));

        try
        {
            Console.SetCursorPosition(0, _top);
            Console.Out.Write(buffer, 0, buffer.Length - 1);
        }
        catch
        {
            // A resized console must never break the merge.
            _active = false;
        }
    }
}
'@

function Set-MergeStatus {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([MergeDisplay]::IsActive) {
        [MergeDisplay]::SetStatus($Text)
    }
    elseif ($Text) {
        Write-Host $Text
    }
}

# Every wait in the merge path goes through here, so -DelayScale tunes all of
# them together and the animation keeps drawing for the whole duration.
function Wait-Merge {
    param(
        [Parameter(Mandatory)]
        [int]$Milliseconds
    )

    [MergeDisplay]::Pump([int][Math]::Round($Milliseconds * $script:DelayScale))
}

# Returns the focused element only when it is a text field, which is how the
# address bar reports itself (ControlType.Edit, name "Address Bar"). Anything
# else means Ctrl+L missed and the folder view still has focus.
function Get-FocusedAddressBar {
    try {
        $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -eq $focused) { return $null }

        $controlType = $focused.Current.ControlType
        if ($controlType -ne [System.Windows.Automation.ControlType]::Edit -and
            $controlType -ne [System.Windows.Automation.ControlType]::ComboBox) {
            return $null
        }

        return $focused
    }
    catch {
        return $null
    }
}

function Get-AddressBarText {
    param(
        [Parameter(Mandatory)]
        $Element
    )

    try {
        return $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    }
    catch {
        return $null
    }
}

# Counts every tab in one Explorer window, including tabs on Home or This PC.
# Those report an empty LocationURL, so Get-ExplorerFolderWindows filters them
# out - but they are exactly what proves a fresh Ctrl+T tab appeared.
function Get-ExplorerWindowTabCount {
    param(
        [Parameter(Mandatory)]
        [IntPtr]$Hwnd
    )

    $shell = New-Object -ComObject Shell.Application
    $count = 0
    foreach ($window in @($shell.Windows())) {
        try {
            if ([IO.Path]::GetFileName($window.FullName) -ine 'explorer.exe') { continue }
            if (([IntPtr][int64]$window.HWND) -eq $Hwnd) { $count++ }
        }
        catch {
            # Explorer can close or navigate while its windows are enumerated.
        }
    }

    return $count
}

function Write-Trace {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $script:Trace) { return }
    Write-Host ("  [{0:HH:mm:ss.fff}] {1}" -f [DateTime]::Now, $Message) -ForegroundColor DarkCyan
}

function Get-ExplorerFolderWindows {
    $shell = New-Object -ComObject Shell.Application
    $items = foreach ($window in @($shell.Windows())) {
        try {
            if ([IO.Path]::GetFileName($window.FullName) -ine 'explorer.exe') { continue }

            $uri = [string]$window.LocationURL
            if (-not $uri.StartsWith('file:', [StringComparison]::OrdinalIgnoreCase)) { continue }

            $path = ([Uri]$uri).LocalPath
            if (-not [IO.Directory]::Exists($path)) { continue }

            [pscustomobject]@{
                Hwnd = [IntPtr][int64]$window.HWND
                Path = $path
            }
        }
        catch {
            # Explorer can close or navigate while its windows are enumerated.
        }
    }

    return @($items)
}

function Set-ExplorerWindowForeground {
    param(
        [Parameter(Mandatory)]
        [IntPtr]$Hwnd
    )

    if (-not [ExplorerWindowControl]::IsWindow($Hwnd)) {
        throw 'The destination Explorer window was closed before the merge finished.'
    }

    [void][ExplorerWindowControl]::ShowWindowAsync($Hwnd, 9) # SW_RESTORE
    Wait-Merge 300
    [void][ExplorerWindowControl]::SetForegroundWindow($Hwnd)
    Wait-Merge 600

    if ([ExplorerWindowControl]::GetForegroundWindow() -ne $Hwnd) {
        throw 'Could not focus the destination Explorer window. No source windows were closed.'
    }
}

function Add-ExplorerFolderTab {
    param(
        [Parameter(Mandatory)]
        [IntPtr]$Hwnd,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $destinationTabsBefore = @(Get-ExplorerFolderWindows | Where-Object {
        $_.Hwnd -eq $Hwnd
    })
    $tabCountBefore = $destinationTabsBefore.Count
    $matchingTabCountBefore = @($destinationTabsBefore | Where-Object {
        $_.Path -ieq $Path
    }).Count

    $allTabsBefore = Get-ExplorerWindowTabCount -Hwnd $Hwnd
    Write-Trace ("destination has {0} tab(s) total, {1} filesystem, {2} already at target" -f $allTabsBefore, $tabCountBefore, $matchingTabCountBefore)

    Set-ExplorerWindowForeground -Hwnd $Hwnd
    [Windows.Forms.Clipboard]::SetText($Path)
    Write-Trace 'focused destination, clipboard set'

    # Confirm Ctrl+T actually produced a tab before typing anything. A dropped
    # Ctrl+T used to go unnoticed: the following Ctrl+L would land on the tab
    # that was already open and Enter would navigate it away from where it was.
    # A brand new tab sits on Home and reports an empty LocationURL, so it only
    # shows up in the unfiltered count.
    $tabOpened = $false
    for ($attempt = 1; $attempt -le 3 -and -not $tabOpened; $attempt++) {
        [Windows.Forms.SendKeys]::SendWait('^t')
        $tabDeadline = [DateTime]::UtcNow.AddSeconds(3)
        do {
            Wait-Merge 300
            $allTabsNow = Get-ExplorerWindowTabCount -Hwnd $Hwnd
            $tabOpened = $allTabsNow -gt $allTabsBefore
        } while (-not $tabOpened -and [DateTime]::UtcNow -lt $tabDeadline)
        Write-Trace ("Ctrl+T attempt {0}: tabs {1} -> {2}, opened={3}" -f $attempt, $allTabsBefore, $allTabsNow, $tabOpened)
    }

    if (-not $tabOpened) {
        throw "Explorer never opened a new tab in the destination window for '$Path'. Nothing was typed or submitted, so no existing tab was navigated away. No source windows were closed. Try -DelayScale 2."
    }

    # Never send Ctrl+A and Enter until the address bar is confirmed focused and
    # readable: in the folder view that pair selects every file and opens all of
    # them. An editable control with no readable value is treated as a miss,
    # because the paste could not then be verified either.
    $addressBar = $null
    for ($attempt = 1; $attempt -le 3 -and $null -eq $addressBar; $attempt++) {
        [Windows.Forms.SendKeys]::SendWait('^l')
        Wait-Merge 600
        $candidate = Get-FocusedAddressBar
        if ($null -ne $candidate -and $null -ne (Get-AddressBarText -Element $candidate)) {
            $addressBar = $candidate
        }
        Write-Trace ("Ctrl+L attempt {0}: focused={1}" -f $attempt, $(if ($null -eq $candidate) { 'not a text field' } else { "'" + $candidate.Current.Name + "' (" + $candidate.Current.ControlType.ProgrammaticName + ")" }))
    }

    if ($null -eq $addressBar) {
        throw "The address bar never took focus for '$Path', so the path was not typed. Nothing was selected or opened, and no source windows were closed. Try -DelayScale 2."
    }

    [Windows.Forms.SendKeys]::SendWait('^a')
    Wait-Merge 150
    [Windows.Forms.SendKeys]::SendWait('^v')
    Wait-Merge 400

    # Confirm the paste actually landed before committing with Enter.
    $typedPath = Get-AddressBarText -Element $addressBar
    Write-Trace ("address bar reads '{0}'" -f $typedPath)
    if ($null -eq $typedPath -or $typedPath.TrimEnd('\') -ine $Path.TrimEnd('\')) {
        throw "The address bar held '$typedPath' instead of '$Path', so nothing was submitted. No source windows were closed."
    }

    [Windows.Forms.SendKeys]::SendWait('{ENTER}')

    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        Wait-Merge 250
        $destinationTabs = @(Get-ExplorerFolderWindows | Where-Object {
            $_.Hwnd -eq $Hwnd
        })
        $matchingTabCount = @($destinationTabs | Where-Object {
            $_.Path -ieq $Path
        }).Count
        $tabWasAdded = (
            $destinationTabs.Count -gt $tabCountBefore -and
            $matchingTabCount -gt $matchingTabCountBefore
        )
        Write-Trace ("confirm: filesystem tabs {0} (was {1}), matching {2} (was {3})" -f $destinationTabs.Count, $tabCountBefore, $matchingTabCount, $matchingTabCountBefore)
    } while (-not $tabWasAdded -and [DateTime]::UtcNow -lt $deadline)

    if (-not $tabWasAdded) {
        throw "Explorer did not open '$Path' in the destination window. No source windows were closed."
    }
}

function Write-MergedFolderList {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Paths,

        [Parameter(Mandatory)]
        [string]$Heading
    )

    if ($Paths.Count -eq 0) { return }

    Write-Host ''
    Write-Host $Heading
    $numberWidth = ([string]$Paths.Count).Length
    for ($i = 0; $i -lt $Paths.Count; $i++) {
        $number = ([string]($i + 1)).PadLeft($numberWidth)
        Write-Host ("  {0}. {1}" -f $number, $Paths[$i])
    }
}

function Restore-ConsoleFocus {
    # The merge hands focus to Explorer, so take it back before prompting.
    try {
        $console = [ExplorerWindowControl]::GetConsoleWindow()
        if ($console -ne [IntPtr]::Zero) {
            [void][ExplorerWindowControl]::SetForegroundWindow($console)
        }
    }
    catch { }
}

function Wait-ForAnyKey {
    if ($NoPause) { return }

    try { if ([Console]::IsInputRedirected) { return } } catch { return }

    Restore-ConsoleFocus

    try {
        # Drop anything already buffered so a stray keystroke does not skip the prompt.
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
    }
    catch { return }

    Write-Host ''
    Write-Host 'Press any key to continue...' -ForegroundColor DarkGray
    try { [void][Console]::ReadKey($true) } catch { }
}

$windows = @(Get-ExplorerFolderWindows)
if ($windows.Count -eq 0) {
    Write-Warning 'No open Explorer windows showing normal filesystem folders were found.'
    Wait-ForAnyKey
    exit 1
}

$windowGroups = @($windows | Group-Object { $_.Hwnd.ToInt64() })

# Most tabs wins, because that is the least work. When windows tie - and they all
# tie at one tab each in the common case - prefer the one nearest the front of
# the Z-order, which is the Explorer window you used most recently.
$zOrder = @{}
$rank = 0
foreach ($handle in [ExplorerWindowControl]::WindowsFrontToBack()) {
    $zOrder[$handle.ToInt64()] = $rank
    $rank++
}

$targetGroup = $windowGroups |
    Sort-Object -Property `
        @{ Expression = 'Count'; Descending = $true },
        @{ Expression = {
            $key = [int64]$_.Name
            if ($zOrder.ContainsKey($key)) { $zOrder[$key] } else { [int]::MaxValue }
        } } |
    Select-Object -First 1
$targetHwnd = [IntPtr][int64]$targetGroup.Name
$sourceTabs = @($windows | Where-Object { $_.Hwnd -ne $targetHwnd })
$sourceHwnds = @($sourceTabs | ForEach-Object { $_.Hwnd.ToInt64() } | Sort-Object -Unique)

if ($sourceHwnds.Count -eq 0) {
    Write-Host ("Explorer is already consolidated in one window with {0} filesystem tab(s)." -f $targetGroup.Count)
    Write-MergedFolderList -Paths @($targetGroup.Group | ForEach-Object { $_.Path }) -Heading 'Open folders:'
    Write-Host ''
    Write-Host 'made with loving prompts by riecodes' -ForegroundColor DarkGray
    Wait-ForAnyKey
    exit 0
}

$mergedPaths = New-Object 'System.Collections.Generic.List[string]'
$mergeError = $null
$closedWindowCount = 0

if (-not $NoAnimation -and -not $Trace) {
    [MergeDisplay]::Start($sourceTabs.Count)
}

try {
    $originalClipboard = [Windows.Forms.Clipboard]::GetDataObject()

    try {
        $tabNumber = 0
        foreach ($sourceTab in $sourceTabs) {
            $tabNumber++
            Set-MergeStatus ("Merging tab {0} of {1}: {2}" -f $tabNumber, $sourceTabs.Count, $sourceTab.Path)
            Add-ExplorerFolderTab -Hwnd $targetHwnd -Path $sourceTab.Path
            $mergedPaths.Add($sourceTab.Path)
            [MergeDisplay]::SetProgress($mergedPaths.Count)
        }
    }
    finally {
        if ($null -ne $originalClipboard) {
            try { [Windows.Forms.Clipboard]::SetDataObject($originalClipboard, $true) } catch {}
        }
        else {
            try { [Windows.Forms.Clipboard]::Clear() } catch {}
        }
    }

    Set-MergeStatus ("Closing {0} source window(s)..." -f $sourceHwnds.Count)
    foreach ($sourceHwndValue in $sourceHwnds) {
        $sourceHwnd = [IntPtr][int64]$sourceHwndValue
        if ([ExplorerWindowControl]::IsWindow($sourceHwnd)) {
            [void][ExplorerWindowControl]::PostMessage($sourceHwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
            $closedWindowCount++
        }
    }

    Set-MergeStatus 'Merge complete.'
    # Hold the finished frame briefly so the full bar is actually seen.
    if ([MergeDisplay]::IsActive) { [MergeDisplay]::Pump(600) }
}
catch {
    $mergeError = $_
}
finally {
    [MergeDisplay]::Stop()
}

if ($null -ne $mergeError) {
    Write-Host ''
    Write-Host ("Merge stopped: {0}" -f $mergeError.Exception.Message) -ForegroundColor Red
    Write-Host ("{0} of {1} tab(s) were merged. No source windows were closed, so nothing was lost." -f $mergedPaths.Count, $sourceTabs.Count)
    Write-MergedFolderList -Paths $mergedPaths.ToArray() -Heading 'Folders that did make it into the destination window:'
    Write-Host ''
    Write-Host 'made with loving prompts by riecodes' -ForegroundColor DarkGray
    Wait-ForAnyKey
    exit 1
}

$finalTabCount = $targetGroup.Count + $mergedPaths.Count
Write-Host ("Merged {0} folder(s) into the existing Explorer window; it now has {1} filesystem tab(s). Closed {2} source window(s)." -f $mergedPaths.Count, $finalTabCount, $closedWindowCount)
Write-MergedFolderList -Paths $mergedPaths.ToArray() -Heading 'Merged folders:'
Write-Host ''
Write-Host 'made with loving prompts by riecodes' -ForegroundColor DarkGray
Wait-ForAnyKey
