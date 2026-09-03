using System;
using System.IO;

class Program
{
    static void Main()
    {
        var file = "/Users/mihai/Source/Daily/Services/SyncService.cs";
        var content = File.ReadAllText(file);
        content = content.Replace("else if (lastPull < threshold)", "else if (lastPull > threshold)");
        File.WriteAllText(file, content);
    }
}
