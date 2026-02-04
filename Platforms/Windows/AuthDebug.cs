namespace Daily.WinUI
{
    public static class AuthDebug
    {
        public static void Log(string message)
        {
            System.Diagnostics.Debug.WriteLine($"[WindowsAuthDebug] {message}");
            try { 
                var path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "daily_auth_debug.txt");
                System.IO.File.AppendAllText(path, $"{System.DateTime.Now}: {message}\n"); 
            } catch {}
        }
    }
}
