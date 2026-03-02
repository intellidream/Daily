using System;
using System.Threading.Tasks;
using Microsoft.Maui.Devices;
using Plugin.Maui.Audio;

namespace Daily.Services
{
    public interface IFeedbackService
    {
        Task PlayWaterFeedbackAsync();
        Task PlaySmokeFeedbackAsync();
    }

    public class FeedbackService : IFeedbackService
    {
        private readonly IAudioManager _audioManager;
        private readonly DebugLogger _logger;
        private IAudioPlayer? _waterPlayer;
        private IAudioPlayer? _smokePlayer;
        private bool _isInitialized;

        public FeedbackService(IAudioManager audioManager, DebugLogger logger)
        {
            _audioManager = audioManager;
            _logger = logger;
        }

        private async Task EnsureInitializedAsync()
        {
            if (_isInitialized) return;

            try
            {
                var waterStream = await FileSystem.OpenAppPackageFileAsync("water_drop.wav");
                _waterPlayer = _audioManager.CreatePlayer(waterStream);

                var smokeStream = await FileSystem.OpenAppPackageFileAsync("lighter_click.wav");
                _smokePlayer = _audioManager.CreatePlayer(smokeStream);
                
                _logger.Log("[FeedbackService] Audio Init Success");
            }
            catch (Exception ex)
            {
                _logger.Log($"[FeedbackService] Warning: Could not initialize audio players - {ex.Message}");
            }
            finally
            {
                _isInitialized = true;
            }
        }

        public async Task PlayWaterFeedbackAsync()
        {
            await EnsureInitializedAsync();
            await PlayFeedbackAsync(_waterPlayer);
        }

        public async Task PlaySmokeFeedbackAsync()
        {
            await EnsureInitializedAsync();
            await PlayFeedbackAsync(_smokePlayer);
        }

        private Task PlayFeedbackAsync(IAudioPlayer? player)
        {
            // Triggers a click Haptic on iOS/Android, safely ignores on MacOS/Win
            MainThread.BeginInvokeOnMainThread(() =>
            {
                try
                {
                    if (HapticFeedback.Default.IsSupported)
                    {
                        HapticFeedback.Default.Perform(HapticFeedbackType.Click);
                        _logger.Log("[FeedbackService] Haptic Click Performed");
                    }
                    else
                    {
                        _logger.Log("[FeedbackService] Haptics Not Supported on this Device");
                    }
                }
                catch (Exception ex)
                {
                    _logger.Log($"[FeedbackService] Warning: Haptic failed - {ex.Message}");
                }
            });

            if (player != null)
            {
                try
                {
                    // Reset position if it was already played
                    player.Seek(0);
                    player.Play();
                }
                catch (Exception ex)
                {
                    _logger.Log($"[FeedbackService] Warning: Audio failed - {ex.Message}");
                }
            }
            else
            {
                 _logger.Log("[FeedbackService] Warning: Audio Player is Null");
            }
            
            return Task.CompletedTask;
        }
    }
}
