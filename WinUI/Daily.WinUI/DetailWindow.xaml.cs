using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;
using System;

namespace Daily_WinUI;

public sealed partial class DetailWindow : Window
{
    public DetailWindow()
    {
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon("Assets/AppIcon.ico");
        
        // Unhook native title bar before closing to prevent WinUI 3 access violation
        this.Closed += DetailWindow_Closed;
    }

    private void DetailWindow_Closed(object sender, WindowEventArgs args)
    {
        this.Closed -= DetailWindow_Closed;
        ExtendsContentIntoTitleBar = false;
        SetTitleBar(null);
        Content = null;
    }

    public void NavigateTo(Type pageType, object parameter = null)
    {
        try
        {
            RootFrame.Navigate(pageType, parameter);
        }
        catch (Exception ex)
        {
            System.IO.File.WriteAllText("crash_log.txt", ex.ToString());
            throw;
        }
    }
}
