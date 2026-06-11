using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Daily.Models;

namespace Daily_WinUI.Services
{
    public interface ICalendarService
    {
        Task<List<LocalCalendarAccount>> GetAccountsAsync();
        Task AddAccountAsync(LocalCalendarAccount account);
        Task DeleteAccountAsync(string id);
        Task SyncAllCalendarsAsync();
        Task<List<LocalCalendarEvent>> GetCachedEventsAsync(DateTime start, DateTime end);
        Task<List<LocalCalendarTodo>> GetCachedTodosAsync();
        Task ToggleAccountActiveAsync(string accountId, bool isActive);
        Task UpdateAccountColorAsync(string accountId, string hexColor);
        Task UpdateAccountCustomNameAsync(string accountId, string customName);
        Task UpdateAccountsOrderAsync(List<string> accountIds);
        Task CompleteTodoAsync(string todoId);
        event Action OnCalendarDataChanged;
    }
}
