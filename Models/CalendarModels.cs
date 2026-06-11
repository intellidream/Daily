using System;
using SQLite;

namespace Daily.Models
{
    [Table("calendar_accounts")]
    public class LocalCalendarAccount
    {
        [PrimaryKey]
        public string Id { get; set; } = string.Empty; // UUID string

        [Indexed]
        public string UserId { get; set; } = string.Empty; // Supabase user ID

        public string AccountType { get; set; } = string.Empty; // "Google", "MicrosoftPersonal", "MicrosoftWork", "Yahoo"
        
        public string Email { get; set; } = string.Empty;

        public string AccessToken { get; set; } = string.Empty;

        public string RefreshToken { get; set; } = string.Empty;

        public DateTime TokenExpiresAt { get; set; }

        public string Color { get; set; } = "#FF594AE2"; // Hex color code

        public string CustomName { get; set; } = string.Empty;

        public string IdentifiedName { get; set; } = string.Empty;

        public int DisplayOrder { get; set; }

        public bool IsActive { get; set; } = true;

        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        [Indexed]
        public DateTime? SyncedAt { get; set; } // Null = Dirty
    }

    [Table("calendar_events")]
    public class LocalCalendarEvent
    {
        [PrimaryKey]
        public string Id { get; set; } = string.Empty; // UUID or unique composite key

        [Indexed]
        public string AccountId { get; set; } = string.Empty; // FK to LocalCalendarAccount.Id

        [Indexed]
        public string UserId { get; set; } = string.Empty; // Supabase user ID

        public string ProviderEventId { get; set; } = string.Empty; // Event ID from Google/Microsoft/Yahoo

        public string Title { get; set; } = string.Empty;

        public string Description { get; set; } = string.Empty;

        public DateTime Start { get; set; }

        public DateTime End { get; set; }

        public bool IsAllDay { get; set; }

        public string Location { get; set; } = string.Empty;

        public string Color { get; set; } = string.Empty;

        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }

    [Table("calendar_todos")]
    public class LocalCalendarTodo
    {
        [PrimaryKey]
        public string Id { get; set; } = string.Empty; // UUID or unique composite key

        [Indexed]
        public string AccountId { get; set; } = string.Empty; // FK to LocalCalendarAccount.Id

        [Indexed]
        public string UserId { get; set; } = string.Empty; // Supabase user ID

        public string ProviderTodoId { get; set; } = string.Empty; // Task ID from Microsoft ToDo

        public string Title { get; set; } = string.Empty;

        public string Notes { get; set; } = string.Empty;

        public DateTime? DueDate { get; set; }

        public DateTime? CompletedDate { get; set; }

        public bool IsCompleted { get; set; }

        public string Importance { get; set; } = "normal"; // "normal", "high"

        public string Color { get; set; } = string.Empty;

        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    }
}
