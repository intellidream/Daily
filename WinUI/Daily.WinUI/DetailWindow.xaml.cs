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
    }

    public void NavigateTo(Type pageType, object parameter = null)
    {
        RootFrame.Navigate(pageType, parameter);
    }
}
