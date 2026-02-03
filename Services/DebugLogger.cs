namespace Daily.Services
{
    public class DebugLogger
    {
        private readonly List<string> _logs = new List<string>();
        public event Action? OnLogAdded;

        public IReadOnlyList<string> Logs => _logs;

        public void Log(string message)
        {
            var entry = $"[{DateTime.Now:HH:mm:ss}] {message}";
            Console.WriteLine(entry); // Keep console logging too
            lock (_logs)
            {
                _logs.Add(entry);
            }
            OnLogAdded?.Invoke();
        }

        public void Clear()
        {
            lock (_logs)
            {
                _logs.Clear();
            }
            OnLogAdded?.Invoke();
        }
    }
}
