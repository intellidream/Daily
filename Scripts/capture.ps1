Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WinCloser {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
'@

# Close Terminal window if open
$hTerm = [WinCloser]::FindWindow("CASCADIA_HOSTING_WINDOW_CLASS", $null)
if ($hTerm -ne [IntPtr]::Zero) {
    [WinCloser]::PostMessage($hTerm, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}

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
