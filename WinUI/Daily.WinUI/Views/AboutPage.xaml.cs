using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;

namespace Daily_WinUI.Views;

public sealed partial class AboutPage : Page
{
    public AboutPage()
    {
        InitializeComponent();
        Loaded += AboutPage_Loaded;
    }

    private void AboutPage_Loaded(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        try
        {
            var v = Windows.ApplicationModel.Package.Current.Id.Version;
            VersionText.Text = $"Version {v.Major}.{v.Minor}.{v.Build}";
        }
        catch
        {
            // Unpackaged / debug — fall back to assembly version
            var asm = System.Reflection.Assembly.GetExecutingAssembly().GetName().Version;
            VersionText.Text = asm is not null
                ? $"Version {asm.Major}.{asm.Minor}.{asm.Build}"
                : "Version 1.0.0";
        }

        CopyrightText.Text = $"© {System.DateTime.Now.Year} intellidream. All rights reserved.";
    }
}
