# merge_file_explorers.ps1
# Merges every open File Explorer folder window into a single tabbed window.
#
# made with loving prompts by riecodes

[CmdletBinding()]
param(
    # Skip the rotating ASCII folder intro.
    [switch]$NoSplash,

    # How long the intro spins, in seconds.
    [ValidateRange(0, 30)]
    [double]$SplashSeconds = 3.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

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

    private static void Build()
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
        if (row < 0 || text.Length > width) return;
        int start = row * stride + (width - text.Length) / 2;
        for (int i = 0; i < text.Length; i++) buffer[start + i] = text[i];
    }

    // Renders one frame into a newline separated buffer of `height` rows.
    public static char[] Frame(double angle, int width, int height)
    {
        Build();

        int stride = width + 1;
        var buffer = new char[stride * height];
        var depth = new double[width * height];

        double cx = width / 2.0;
        double cy = (height - 2) / 2.0;
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
            if (sx < 0 || sx >= width || sy < 0 || sy >= height - 2) continue;

            int cell = sy * width + sx;
            if (ooz <= depth[cell]) continue;

            depth[cell] = ooz;
            int shade = (int)(lum * (Shades.Length - 1) + 0.5);
            if (shade < 0) shade = 0;
            if (shade > Shades.Length - 1) shade = Shades.Length - 1;
            buffer[sy * stride + sx] = Shades[shade];
        }

        Stamp(buffer, stride, width, height - 1, Watermark);
        return buffer;
    }

    public static void Run(double seconds)
    {
        if (Console.IsOutputRedirected) return;

        int width = Math.Min(80, Math.Max(40, Console.WindowWidth - 1));
        int height = Math.Min(26, Math.Max(14, Console.WindowHeight - 3));
        if (width < 40 || height < 14) return;

        Build();

        bool cursorHidden = false;
        int top = 0;
        try { Console.CursorVisible = false; cursorHidden = true; } catch { }

        try
        {
            Console.Write(new string('\n', height));
            top = Math.Max(0, Console.CursorTop - height);

            var clock = Stopwatch.StartNew();
            while (clock.Elapsed.TotalSeconds < seconds)
            {
                char[] buffer = Frame(clock.Elapsed.TotalSeconds * 2.1, width, height);

                Console.SetCursorPosition(0, top);
                Console.Out.Write(buffer, 0, buffer.Length - 1);

                try { if (Console.KeyAvailable) { Console.ReadKey(true); break; } } catch { }

                System.Threading.Thread.Sleep(28);
            }

            Console.SetCursorPosition(0, Math.Min(top + height, Console.BufferHeight - 1));
            Console.WriteLine();
        }
        catch (Exception)
        {
            // A resized or non-interactive console must never break the merge.
        }
        finally
        {
            if (cursorHidden) { try { Console.CursorVisible = true; } catch { } }
        }
    }
}
'@

function Show-FolderSplash {
    param(
        [double]$Seconds
    )

    if ($Seconds -le 0) { return }

    try { [FolderSpinner]::Run($Seconds) } catch { }
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
    Start-Sleep -Milliseconds 200
    [void][ExplorerWindowControl]::SetForegroundWindow($Hwnd)
    Start-Sleep -Milliseconds 300

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

    Set-ExplorerWindowForeground -Hwnd $Hwnd
    [Windows.Forms.Clipboard]::SetText($Path)
    [Windows.Forms.SendKeys]::SendWait('^t')
    Start-Sleep -Milliseconds 350
    [Windows.Forms.SendKeys]::SendWait('^l')
    Start-Sleep -Milliseconds 100
    [Windows.Forms.SendKeys]::SendWait('^a')
    [Windows.Forms.SendKeys]::SendWait('^v')
    [Windows.Forms.SendKeys]::SendWait('{ENTER}')

    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 250
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
    } while (-not $tabWasAdded -and [DateTime]::UtcNow -lt $deadline)

    if (-not $tabWasAdded) {
        throw "Explorer did not open '$Path' in the destination window. No source windows were closed."
    }
}

if (-not $NoSplash) {
    Show-FolderSplash -Seconds $SplashSeconds
}

$windows = @(Get-ExplorerFolderWindows)
if ($windows.Count -eq 0) {
    Write-Warning 'No open Explorer windows showing normal filesystem folders were found.'
    exit 1
}

$windowGroups = @($windows | Group-Object { $_.Hwnd.ToInt64() })
$targetGroup = $windowGroups |
    Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name |
    Select-Object -First 1
$targetHwnd = [IntPtr][int64]$targetGroup.Name
$sourceTabs = @($windows | Where-Object { $_.Hwnd -ne $targetHwnd })
$sourceHwnds = @($sourceTabs | ForEach-Object { $_.Hwnd.ToInt64() } | Sort-Object -Unique)

if ($sourceHwnds.Count -eq 0) {
    Write-Host ("Explorer is already consolidated in one window with {0} filesystem tab(s)." -f $targetGroup.Count)
    Write-Host 'made with loving prompts by riecodes' -ForegroundColor DarkGray
    exit 0
}

$originalClipboard = [Windows.Forms.Clipboard]::GetDataObject()

try {
    foreach ($sourceTab in $sourceTabs) {
        Add-ExplorerFolderTab -Hwnd $targetHwnd -Path $sourceTab.Path
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

foreach ($sourceHwndValue in $sourceHwnds) {
    $sourceHwnd = [IntPtr][int64]$sourceHwndValue
    if ([ExplorerWindowControl]::IsWindow($sourceHwnd)) {
        [void][ExplorerWindowControl]::PostMessage($sourceHwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    }
}

$finalTabCount = $targetGroup.Count + $sourceTabs.Count
Write-Host ("Merged {0} tab(s) into the existing Explorer window; it now has {1} filesystem tab(s). Closed {2} source window(s)." -f $sourceTabs.Count, $finalTabCount, $sourceHwnds.Count)
Write-Host 'made with loving prompts by riecodes' -ForegroundColor DarkGray
