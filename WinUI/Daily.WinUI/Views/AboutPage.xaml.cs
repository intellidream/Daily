using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Daily_WinUI.Views;

public sealed partial class AboutPage : Page
{
    public AboutPage()
    {
        InitializeComponent();
        Loaded += AboutPage_Loaded;
        ActualThemeChanged += AboutPage_ThemeChanged;
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

        CopyrightText.Text = $"© {System.DateTime.Now.Year} Intellidream. All rights reserved.";

        // Set theme-aware SVG sources
        UpdateThemeSvgs();
    }

    private void AboutPage_ThemeChanged(FrameworkElement sender, object args)
    {
        UpdateThemeSvgs();
    }

    private void UpdateThemeSvgs()
    {
        var isDark = ActualTheme == ElementTheme.Dark;

        // App icon
        var appIconPath = isDark 
            ? "ms-appx:///Assets/appicon.theme-dark.svg"
            : "ms-appx:///Assets/appicon.theme-light.svg";
        ((SvgImageSource)AppIconImage.Source).UriSource = new System.Uri(appIconPath);

        // Intellidream company logo (theme-aware)
        var companyIconPath = isDark
            ? "ms-appx:///Assets/companyicon.theme-dark.svg"
            : "ms-appx:///Assets/companyicon.theme-light.svg";
        ((SvgImageSource)IntellIdreamImage.Source).UriSource = new System.Uri(companyIconPath);
    }
}
