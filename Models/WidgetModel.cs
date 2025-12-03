using System;
using System.Collections.Generic;

namespace Daily.Models
{
    public class WidgetModel
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Title { get; set; } = string.Empty;
        public string ComponentType { get; set; } = string.Empty;
        public Dictionary<string, object> Parameters { get; set; } = new();
        public int ColumnSpan { get; set; } = 1;
        public int RowSpan { get; set; } = 1;
    }
}
