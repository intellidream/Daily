using System;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface IRefreshService
    {
        event Func<Task> RefreshRequested;
        event Func<Task> DetailRefreshRequested;
        event Func<Task> HealthRefreshRequested;
        Task TriggerRefreshAsync();
        Task TriggerDetailRefreshAsync();
        Task TriggerHealthRefreshAsync();
    }
}
