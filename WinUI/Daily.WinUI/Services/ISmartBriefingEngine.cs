using System.Threading.Tasks;

namespace Daily_WinUI.Services
{
    public interface ISmartBriefingEngine
    {
        Task<bool> IsSupportedAsync();
        Task InitializeAsync();
        Task<string> GenerateBriefingAsync(string prompt);
        IAsyncEnumerable<string> GenerateBriefingStreamAsync(string prompt);
    }
}
