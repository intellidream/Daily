Start-Transcript -Path "C:\Users\mihai\enum_daily_hwnds.log" -Force

Add-Type @'
using System;
using System.Collections.Generic;
using System.Text;
using System.Runtime.InteropServices;

public class HwndFinder3 {
    public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    public static List<string> GetProcessWindows(uint targetPid) {
        List<string> list = new List<string>();
        EnumWindows((hWnd, lParam) => {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == targetPid) {
                StringBuilder sbClass = new StringBuilder(256);
                GetClassName(hWnd, sbClass, 256);
                StringBuilder sbText = new StringBuilder(256);
                GetWindowText(hWnd, sbText, 256);
                bool vis = IsWindowVisible(hWnd);
                RECT r;
                GetWindowRect(hWnd, out r);
                list.Add(string.Format("HWND: {0}, Visible: {1}, Rect: [{4},{5} -> {6},{7} ({8}x{9})], Class: '{2}', Title: '{3}'", 
                    hWnd, vis, sbClass.ToString(), sbText.ToString(), r.Left, r.Top, r.Right, r.Bottom, r.Right - r.Left, r.Bottom - r.Top));
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
'@

$proc = Get-Process -Name Daily.WinUI -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Daily.WinUI PID: $($proc.Id)"
    $lines = [HwndFinder3]::GetProcessWindows($proc.Id)
    Write-Host "Found $($lines.Count) windows:"
    foreach ($line in $lines) {
        Write-Host $line
    }
}

Stop-Transcript
