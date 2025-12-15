using System;

namespace Daily.Services
{
    public interface ITrayService
    {
        void Initialize();
        Action? ClickHandler { get; set; }
    }
}
