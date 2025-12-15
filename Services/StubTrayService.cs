using Daily.Services;
using System;

namespace Daily.Services
{
    public class StubTrayService : ITrayService
    {
        public Action? ClickHandler { get; set; }
        public void Initialize() { }
    }
}
