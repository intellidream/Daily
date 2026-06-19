using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Daily_WinUI.Services;
using System;

namespace Daily_WinUI.Views;

public sealed partial class DebugSettingsPage : Page
{
    public DebugSettingsPage()
    {
        this.InitializeComponent();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        UpdateDebugFields();
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        UpdateDebugFields();
    }

    private void UpdateDebugFields()
    {
        ActiveEngineText.Text = string.IsNullOrEmpty(LlmDebugLogger.ActiveEngine) ? "None" : LlmDebugLogger.ActiveEngine;
        LastExecutionText.Text = LlmDebugLogger.LastExecutionTime == default ? "Never" : LlmDebugLogger.LastExecutionTime.ToString("yyyy-MM-dd HH:mm:ss");

        SystemPromptTextBox.Text = LlmDebugLogger.SystemPrompt;
        UserPromptTextBox.Text = LlmDebugLogger.UserPrompt;
        FormattedPromptTextBox.Text = LlmDebugLogger.FormattedPrompt;
        ResponseTextBox.Text = LlmDebugLogger.Response;

        if (string.IsNullOrEmpty(LlmDebugLogger.LastError))
        {
            ErrorCard.Visibility = Visibility.Collapsed;
            ErrorTextBox.Text = string.Empty;
        }
        else
        {
            ErrorCard.Visibility = Visibility.Visible;
            ErrorTextBox.Text = LlmDebugLogger.LastError;
        }
    }
}
