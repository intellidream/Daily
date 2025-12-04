using System;
using System.Threading.Tasks;

namespace Daily.Services
{
    public interface IRefreshService
    {
        event Func<Task> RefreshRequested;
        Task TriggerRefreshAsync();
    }
}
