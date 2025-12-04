using System;
using System.Threading.Tasks;

namespace Daily.Services
{
    public class RefreshService : IRefreshService
    {
        public event Func<Task> RefreshRequested;

        public async Task TriggerRefreshAsync()
        {
            if (RefreshRequested != null)
            {
                await RefreshRequested.Invoke();
            }
        }
    }
}
