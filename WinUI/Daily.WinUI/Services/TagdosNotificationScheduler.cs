using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Daily.Models;
using Daily.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace Daily_WinUI.Services
{
    /// <summary>
    /// 100% local daily reminder scheduler for TagDoS streams and per-stream groups/clusters on Windows 11.
    /// Zero background network egress; routes toast taps directly to the target stream or cluster.
    /// </summary>
    public sealed class TagdosNotificationScheduler
    {
        public static TagdosNotificationScheduler Instance { get; } = new();

        private IServiceProvider? _services;
        private Timer? _timer;
        private bool _isStarted;
        private readonly HashSet<string> _firedKeys = new(StringComparer.Ordinal);
        private string _activeDayKey = string.Empty;
        private readonly object _gate = new();

        private TagdosNotificationScheduler() { }

        public void Start(IServiceProvider? services)
        {
            lock (_gate)
            {
                _services = services;
                if (_isStarted) return;
                _isStarted = true;
            }

            try
            {
                AppNotificationManager.Default.NotificationInvoked += OnNotificationInvoked;
                AppNotificationManager.Default.Register();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TagdosNotificationScheduler] Register notice: {ex.Message}");
            }

            // Check every 15s for local HH:mm matches (in-memory cache, 0ms DB/network overhead)
            _timer = new Timer(_ => _ = CheckDueRemindersAsync(), null, TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(15));
        }

        private async Task CheckDueRemindersAsync()
        {
            var tagdos = _services?.GetService<ITagdosService>();
            if (tagdos == null) return;

            List<TagDoStream> streams;
            try
            {
                streams = await tagdos.GetStreamsAsync().ConfigureAwait(false);
            }
            catch
            {
                return;
            }

            var nowLocal = DateTime.Now;
            var dayKey = nowLocal.ToString("yyyy-MM-dd");
            int nowHour = nowLocal.Hour;
            int nowMin = nowLocal.Minute;

            lock (_gate)
            {
                if (_activeDayKey != dayKey)
                {
                    _activeDayKey = dayKey;
                    _firedKeys.Clear();
                }
            }

            foreach (var stream in streams)
            {
                if (stream.StreamReminder.HasValue)
                {
                    var rem = stream.StreamReminder.Value;
                    if (rem.Hour == nowHour && rem.Minute == nowMin)
                    {
                        var key = $"{dayKey}|stream|{stream.Id}|{nowHour:D2}:{nowMin:D2}";
                        bool shouldFire;
                        lock (_gate) { shouldFire = _firedKeys.Add(key); }
                        if (shouldFire)
                        {
                            var activeCount = stream.AllPills.Count(p => !p.IsCompleted);
                            var driving = stream.AllPills.FirstOrDefault(p => !p.IsCompleted)?.Text;
                            var title = $"TagDoS · {stream.DisplayTitle}";
                            var body = !string.IsNullOrWhiteSpace(driving)
                                ? $"Focus now: {driving} ({activeCount} active tags)"
                                : $"Check {stream.DisplayTitle}";
                            ShowToast(title, body, stream.Id, null);
                        }
                    }
                }

                for (int cIdx = 0; cIdx < stream.Clusters.Count; cIdx++)
                {
                    var cluster = stream.Clusters[cIdx];
                    if (!cluster.ClusterReminder.HasValue) continue;
                    var crem = cluster.ClusterReminder.Value;
                    if (crem.Hour == nowHour && crem.Minute == nowMin)
                    {
                        var key = $"{dayKey}|cluster|{stream.Id}|{cIdx}|{nowHour:D2}:{nowMin:D2}";
                        bool shouldFire;
                        lock (_gate) { shouldFire = _firedKeys.Add(key); }
                        if (shouldFire)
                        {
                            var activePills = cluster.Pills.Where(p => !p.IsCompleted).ToList();
                            var sourcePills = activePills.Count > 0 ? activePills : cluster.Pills;
                            var preview = string.Join(" / ", sourcePills.Take(4).Select(p => p.Text));
                            var title = $"TagDoS · {stream.DisplayTitle}";
                            var body = string.IsNullOrWhiteSpace(preview) ? "Group reminder" : $"Group: {preview}";
                            ShowToast(title, body, stream.Id, cIdx);
                        }
                    }
                }
            }
        }

        private static void ShowToast(string title, string body, string streamId, int? clusterIndex)
        {
            try
            {
                var builder = new AppNotificationBuilder()
                    .AddArgument("action", "tagdos")
                    .AddArgument("streamId", streamId);

                if (clusterIndex.HasValue)
                {
                    builder.AddArgument("clusterIndex", clusterIndex.Value.ToString());
                }

                var notification = builder
                    .AddText(title)
                    .AddText(body)
                    .BuildNotification();

                AppNotificationManager.Default.Show(notification);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TagdosNotificationScheduler] ShowToast warning: {ex.Message}");
            }
        }

        private void OnNotificationInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
        {
            try
            {
                if (!args.Arguments.TryGetValue("action", out var action) ||
                    !string.Equals(action, "tagdos", StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }

                args.Arguments.TryGetValue("streamId", out var streamId);
                int? clusterIndex = null;
                if (args.Arguments.TryGetValue("clusterIndex", out var cStr) && int.TryParse(cStr, out int parsedIdx))
                {
                    clusterIndex = parsedIdx;
                }

                var mw = App.Current?.MainWindow;
                mw?.DispatcherQueue.TryEnqueue(() =>
                {
                    var tagdos = App.Current?.Services?.GetService<ITagdosService>();
                    tagdos?.RequestNavigation(streamId: streamId, clusterIndex: clusterIndex, openPillEditor: false);
                    mw.ShowAndActivate();
                    mw.NavigateToTab(3);
                });
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[TagdosNotificationScheduler] NotificationInvoked error: {ex.Message}");
            }
        }
    }
}
