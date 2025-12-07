using System;
using System.Collections.Generic;
using System.Linq;

namespace Daily.Services
{
    public interface IBackButtonService
    {
        void Register(Func<bool> handler);
        void Unregister(Func<bool> handler);
        bool HandleBack();
    }

    public class BackButtonService : IBackButtonService
    {
        private readonly List<Func<bool>> _handlers = new();
        private static BackButtonService? _instance;

        public BackButtonService()
        {
            _instance = this;
        }

        public void Register(Func<bool> handler)
        {
            if (!_handlers.Contains(handler))
            {
                _handlers.Add(handler);
            }
        }

        public void Unregister(Func<bool> handler)
        {
            _handlers.Remove(handler);
        }

        public bool HandleBack()
        {
            // Iterate in reverse to give priority to the most recently registered handler (LIFO-like)
            for (int i = _handlers.Count - 1; i >= 0; i--)
            {
                if (_handlers[i]())
                {
                    return true;
                }
            }
            return false;
        }

        [Microsoft.JSInterop.JSInvokable]
        public static bool HandleNativeBack()
        {
            return _instance?.HandleBack() ?? false;
        }
    }
}
