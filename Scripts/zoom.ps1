Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ZoomOps {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
    public static void Zoom(int x, int y, int delta) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(200);
        mouse_event(0x0800, 0, 0, delta, 0);
    }
}
"@

[ZoomOps]::Zoom(960, 500, 120 * 6)
Start-Sleep -Milliseconds 600
Write-Output "Zoom In Performed"
