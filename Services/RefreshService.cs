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
                await RefreshRequested.Invoke();
            }
        }

        public async Task TriggerDetailRefreshAsync()
        {
            if (DetailRefreshRequested != null)
            {
                await DetailRefreshRequested.Invoke();
            }
        }
    }
}
