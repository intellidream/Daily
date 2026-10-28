param([int]$x = 500, [int]$y = 780)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MouseOps {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(150);
        mouse_event(2, 0, 0, 0, 0);
        System.Threading.Thread.Sleep(50);
        mouse_event(4, 0, 0, 0, 0);
    }
}
"@

[MouseOps]::Click($x, $y)
