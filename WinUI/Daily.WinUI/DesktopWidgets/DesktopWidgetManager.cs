using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Windowing;
using Windows.Graphics;
using Daily_WinUI.Services;

namespace Daily_WinUI.DesktopWidgets
{
    public sealed class DesktopWidgetManager
    {
        public static DesktopWidgetManager Instance { get; } = new();

        private readonly List<DesktopWidgetWindow> _activeWidgets = new();
        public IReadOnlyList<DesktopWidgetWindow> ActiveWidgets => _activeWidgets;

        private ISettingsService? _settingsService;
        private bool _isInitialized = false;

        private DesktopWidgetManager() { }

        public void Initialize()
        {
            if (_isInitialized) return;
            _isInitialized = true;

            try
            {
                _settingsService = App.Current.Services?.GetService<ISettingsService>();
                if (_settingsService != null && !_settingsService.Settings.DesktopWidgetsEnabled)
                {
                    return;
                }

                LoadWidgets();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopWidgetManager] Initialize error: {ex}");
            }
        }

        private void LoadWidgets()
        {
            List<DesktopWidgetModel>? models = null;
            string? json = _settingsService?.Settings.DesktopWidgetsConfigJson;

            if (!string.IsNullOrWhiteSpace(json))
            {
                try
                {
                    models = JsonSerializer.Deserialize<List<DesktopWidgetModel>>(json);
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"[DesktopWidgetManager] Error deserializing config: {ex.Message}");
                }
            }

            if (models == null || models.Count == 0)
            {
                models = CreateDefaultWidgets();
            }

            foreach (var model in models)
            {
                SpawnWidgetWindow(model);
            }
        }

        private List<DesktopWidgetModel> CreateDefaultWidgets()
        {
            var list = new List<DesktopWidgetModel>();

            var displayArea = DisplayArea.Primary ?? DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
            var workArea = displayArea.WorkArea;

            // Place on the right side of the desktop wallpaper with 24px padding
            int rightX = workArea.X + workArea.Width - 380 - 24;
            int startY = workArea.Y + 48;

            // 1. Combined Widget (Medium)
            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Combined,
                Size = DesktopWidgetSize.Medium,
                X = rightX,
                Y = startY,
                IsLocked = false
            });

            // 2. Bubbles Widget (Small) & Smokes Widget (Small) side-by-side
            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Bubbles,
                Size = DesktopWidgetSize.Small,
                X = rightX,
                Y = startY + 186,
                IsLocked = false
            });

            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Smokes,
                Size = DesktopWidgetSize.Small,
                X = rightX + 190,
                Y = startY + 186,
                IsLocked = false
            });

            // 3. Money Widget (Medium)
            list.Add(new DesktopWidgetModel
            {
                Type = DesktopWidgetType.Money,
                Size = DesktopWidgetSize.Medium,
                X = rightX,
                Y = startY + 372,
                IsLocked = false
            });

            return list;
        }

        private DesktopWidgetWindow SpawnWidgetWindow(DesktopWidgetModel model)
        {
            var window = new DesktopWidgetWindow(model);
            _activeWidgets.Add(window);

            App.Current.RegisterSecondaryWindow(window);

            window.Closed += (s, e) =>
            {
                _activeWidgets.Remove(window);
            };

            window.Activate();
            return window;
        }

        public void AddWidget(DesktopWidgetType type, DesktopWidgetSize size, int x, int y)
        {
            var model = new DesktopWidgetModel
            {
                Type = type,
                Size = size,
                X = x,
                Y = y,
                IsLocked = false
            };

            SpawnWidgetWindow(model);
            SaveConfiguration();
        }

        public void RemoveWidget(DesktopWidgetWindow window)
        {
            _activeWidgets.Remove(window);
            try
            {
                window.Close();
            }
            catch { }

            SaveConfiguration();
        }

        public void SaveConfiguration()
        {
            try
            {
                if (_settingsService == null)
                {
                    _settingsService = App.Current.Services?.GetService<ISettingsService>();
                }
                if (_settingsService == null) return;

                var models = _activeWidgets.Select(w => w.Model).ToList();
                string json = JsonSerializer.Serialize(models, new JsonSerializerOptions { WriteIndented = true });
                _settingsService.Settings.DesktopWidgetsConfigJson = json;
                _ = _settingsService.SaveSettingsAsync();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DesktopWidgetManager] SaveConfiguration error: {ex.Message}");
            }
        }

        public void ShowAll()
        {
            foreach (var w in _activeWidgets)
            {
                w.AppWindow.Show();
                w.SendToBottom();
            }
        }

        public void HideAll()
        {
            foreach (var w in _activeWidgets)
            {
                w.AppWindow.Hide();
            }
        }

        public void ToggleVisibility()
        {
            bool anyVisible = _activeWidgets.Any(w => w.AppWindow.IsVisible);
            if (anyVisible)
            {
                HideAll();
            }
            else
            {
                ShowAll();
            }
        }

        public void SetAllLocked(bool locked)
        {
            foreach (var w in _activeWidgets)
            {
                w.Model.IsLocked = locked;
            }
            SaveConfiguration();
        }

        public void RefreshAllWidgets()
        {
            foreach (var w in _activeWidgets)
            {
                w.RefreshViewData();
            }
        }

        public void ResetToDefaults()
        {
            // Close all
            var copy = _activeWidgets.ToList();
            foreach (var w in copy)
            {
                try { w.Close(); } catch { }
            }
            _activeWidgets.Clear();

            // Clear json
            if (_settingsService != null)
            {
                _settingsService.Settings.DesktopWidgetsConfigJson = string.Empty;
            }

            // Respawn
            LoadWidgets();
            SaveConfiguration();
        }
    }
}
