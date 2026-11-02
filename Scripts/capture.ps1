Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WinUtil {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
'@

# Minimize DayOne main window to tray so desktop widgets are completely visible
$hwnd = [WinUtil]::FindWindow("WinUIDesktopWin32WindowClass", "DayOne")
if ($hwnd -ne [IntPtr]::Zero) {
    [WinUtil]::ShowWindow($hwnd, 6) # SW_MINIMIZE
}

# Minimize any Windows Terminal window
Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.MainWindowHandle -ne [IntPtr]::Zero) {
        [WinUtil]::ShowWindow($_.MainWindowHandle, 6)
    }
}

Start-Sleep -Milliseconds 500

& "C:\Users\mihai\source\repos\Daily\Scripts\inspect_daily_windows.ps1" | Set-Content -Path "C:\Users\mihai\windows_dump.txt"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bmp.Save('C:\Users\mihai\desktop_screen.png', [System.Drawing.Imaging.ImageFormat]::Png)

$thumbWidth = 1024
$thumbHeight = [int]($bounds.Height * ($thumbWidth / $bounds.Width))
$thumb = New-Object System.Drawing.Bitmap $thumbWidth, $thumbHeight
$gThumb = [System.Drawing.Graphics]::FromImage($thumb)
$gThumb.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gThumb.DrawImage($bmp, 0, 0, $thumbWidth, $thumbHeight)
$thumb.Save('C:\Users\mihai\desktop_small.png', [System.Drawing.Imaging.ImageFormat]::Png)

$gThumb.Dispose()
$thumb.Dispose()
$graphics.Dispose()
$bmp.Dispose()
Write-Host "Screen captured ($($bounds.Width)x$($bounds.Height)) and saved to C:\Users\mihai\desktop_screen.png"
