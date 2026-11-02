Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class ZOrderDump {
    public const uint GW_HWNDNEXT = 2;
    [DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    public static List<string> Dump() {
        var list = new List<string>();
        IntPtr cur = GetTopWindow(IntPtr.Zero);
        int rank = 0;
        while (cur != IntPtr.Zero) {
            uint pid;
            GetWindowThreadProcessId(cur, out pid);
            var sbClass = new StringBuilder(256);
            GetClassName(cur, sbClass, 256);
            var sbText = new StringBuilder(256);
            GetWindowText(cur, sbText, 256);
            bool vis = IsWindowVisible(cur);

            // Filter out 0x0 invisible internal hooks, but keep Progman, WorkerW, and Daily windows
            string title = sbText.ToString();
            string cls = sbClass.ToString();
            if (cls.Contains("Progman") || cls.Contains("WorkerW") || cls.Contains("Shell") || cls.Contains("WinUIDesktop") || vis) {
                list.Add(string.Format("Z#{0} | HWND: {1} | PID: {2} | Vis: {3} | Class: '{4}' | Title: '{5}'",
                    rank, cur, pid, vis, cls, title));
            }
            rank++;
            cur = GetWindow(cur, GW_HWNDNEXT);
        }
        return list;
    }
}
'@

[ZOrderDump]::Dump() | Set-Content -Path "C:\Users\mihai\zorder.txt"
Write-Host "Z-order dumped to C:\Users\mihai\zorder.txt"
