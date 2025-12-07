using System;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface IRefreshService
    {
        event Func<Task> RefreshRequested;
        event Func<Task> DetailRefreshRequested;
        Task TriggerRefreshAsync();
        Task TriggerDetailRefreshAsync();
    }
}
