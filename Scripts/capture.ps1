Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class WinCleaner {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void CleanDesktop(uint dailyPid) {
        EnumWindows((hWnd, lParam) => {
            if (IsWindowVisible(hWnd)) {
                StringBuilder sbClass = new StringBuilder(256);
                GetClassName(hWnd, sbClass, 256);
                string cls = sbClass.ToString();
                
                uint pid;
                GetWindowThreadProcessId(hWnd, out pid);

                if (cls.Contains("Shell") || cls.Contains("Progman") || cls.Contains("WorkerW")) return true;
                
                StringBuilder sbText = new StringBuilder(256);
                GetWindowText(hWnd, sbText, 256);
                string title = sbText.ToString();

                if (pid == dailyPid) {
                    if (title == "DayOne") {
                        ShowWindow(hWnd, 0); // SW_HIDE
                    }
                } else {
                    if (cls.Contains("CASCADIA") || cls.Contains("Console") || cls.Contains("ApplicationFrame") || title.Contains("powershell") || title.Contains("Terminal") || title.Contains("Settings")) {
                        ShowWindow(hWnd, 6); // SW_MINIMIZE
                    }
                }
            }
            return true;
        }, IntPtr.Zero);
    }
}
'@

$daily = Get-Process -Name "Daily.WinUI" -ErrorAction SilentlyContinue
$pidToPass = if ($daily) { $daily.Id } else { 0 }
[WinCleaner]::CleanDesktop($pidToPass)
Start-Sleep -Milliseconds 600

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save('C:\Users\mihai\desktop_screen.png', [System.Drawing.Imaging.ImageFormat]::Png)

$graphics.Dispose()
$bmp.Dispose()
Write-Host "Screen captured ($($bounds.Width)x$($bounds.Height)) and saved to C:\Users\mihai\desktop_screen.png"
