using System;
using System.Threading.Tasks;
using Microsoft.Windows.AI.Text;
using Microsoft.Windows.AI;

namespace Daily_WinUI.Services
{
    public class PhiSilicaNpuEngine : ISmartBriefingEngine
    {
        private LanguageModel? _model;
        private bool _initialized;

        public Task<bool> IsSupportedAsync()
        {
            try
            {
                string? npu = SettingsService.GetDetectedNpuName();
                if (string.IsNullOrEmpty(npu) || !npu.Contains("Qualcomm", StringComparison.OrdinalIgnoreCase))
                {
                    return Task.FromResult(false);
                }

                // Unlock the Limited Access Feature for Phi Silica LanguageModel API
                var access = Windows.ApplicationModel.LimitedAccessFeatures.TryUnlockFeature(
                    "com.microsoft.windows.ai.languagemodel",
                    "bm83TtgNO2HbnbBAf79aIQ==",
                    "1z32rh13vfry6 has registered their use of com.microsoft.windows.ai.languagemodel with Microsoft and agrees to the terms of use.");

                if (access.Status != Windows.ApplicationModel.LimitedAccessFeatureStatus.Available &&
                    access.Status != Windows.ApplicationModel.LimitedAccessFeatureStatus.AvailableWithoutToken)
                {
                    System.Diagnostics.Debug.WriteLine($"[PhiSilicaNpuEngine] Phi Silica LAF unlock failed. Status: {access.Status}");
                    return Task.FromResult(false);
                }

                var state = LanguageModel.GetReadyState();
                return Task.FromResult(state == AIFeatureReadyState.Ready || state == AIFeatureReadyState.NotReady);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[PhiSilicaNpuEngine] NPU availability check failed: {ex.Message}");
                return Task.FromResult(false);
            }
        }

        public async Task InitializeAsync()
        {
            if (_initialized) return;

            if (!await IsSupportedAsync())
            {
                throw new NotSupportedException("Phi Silica NPU is not supported or available on this system.");
            }

            try
            {
                var state = LanguageModel.GetReadyState();
                if (state == AIFeatureReadyState.NotReady)
                {
                    var result = await LanguageModel.EnsureReadyAsync();
                    if (result.Status != AIFeatureReadyResultState.Success)
                    {
                        throw new InvalidOperationException($"Phi Silica model provisioning failed. Status: {result.Status}, Error: {result.ErrorDisplayText}");
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[PhiSilicaNpuEngine] Error checking/ensuring readiness: {ex.Message}");
                throw;
            }

            _model = await LanguageModel.CreateAsync();
            _initialized = true;
        }

        public async Task<string> GenerateBriefingAsync(string prompt)
        {
            if (!_initialized || _model == null)
            {
                throw new InvalidOperationException("PhiSilicaNpuEngine is not initialized.");
            }

            var result = await _model.GenerateResponseAsync(prompt);
            if (result.Status == LanguageModelResponseStatus.Complete)
            {
                return result.Text;
            }
            else
            {
                throw new Exception($"Phi Silica generation failed. Status: {result.Status}");
            }
        }
    }
}
