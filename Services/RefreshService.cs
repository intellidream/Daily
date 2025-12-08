using System;
using System.Threading.Tasks;

namespace Daily.Services
{
    public class RefreshService : IRefreshService
    {
        public event Func<Task> RefreshRequested;
        public event Func<Task> DetailRefreshRequested;

        public async Task TriggerRefreshAsync()
        {
            if (RefreshRequested != null)
            {
                var delegates = RefreshRequested.GetInvocationList();
                var tasks = new System.Collections.Generic.List<Task>(delegates.Length);
                foreach (Func<Task> d in delegates)
                {
                    try
                    {
                        tasks.Add(d());
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Refresh delegate error: {ex}");
                        // Continue ensuring other delegates run
                    }
                }
                await Task.WhenAll(tasks);
            }
        }

        public async Task TriggerDetailRefreshAsync()
        {
            if (DetailRefreshRequested != null)
            {
                var delegates = DetailRefreshRequested.GetInvocationList();
                var tasks = new System.Collections.Generic.List<Task>(delegates.Length);
                foreach (Func<Task> d in delegates)
                {
                    try
                    {
                        tasks.Add(d());
                    }
                    catch (Exception ex)
                    {
                        Console.WriteLine($"Detail refresh delegate error: {ex}");
                    }
                }
                await Task.WhenAll(tasks);
            }
        }
    }
}
