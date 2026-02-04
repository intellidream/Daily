// Log helper
public static void Log(string message)
{
    System.Diagnostics.Debug.WriteLine($"[WindowsAuthDebug] {message}");
    // Also try file log if debug output isn't visible
    try { File.AppendAllText(Path.Combine(FileSystem.CacheDirectory, "auth_debug.log"), $"{DateTime.Now}: {message}\n"); } catch {}
}
