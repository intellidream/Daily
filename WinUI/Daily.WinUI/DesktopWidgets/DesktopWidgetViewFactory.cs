using System;
using Microsoft.UI.Xaml;
using Daily_WinUI.DesktopWidgets.Views;

namespace Daily_WinUI.DesktopWidgets
{
    public static class DesktopWidgetViewFactory
    {
        public static FrameworkElement CreateView(DesktopWidgetModel model, DesktopWidgetWindow hostWindow)
        {
            return model.Type switch
            {
                DesktopWidgetType.Bubbles   => new DesktopBubblesWidgetView(model, hostWindow),
                DesktopWidgetType.Smokes    => new DesktopSmokesWidgetView(model, hostWindow),
                DesktopWidgetType.Money     => new DesktopMoneyWidgetView(model, hostWindow),
                DesktopWidgetType.Sleep     => new DesktopSleepWidgetView(model, hostWindow),
                DesktopWidgetType.Stress    => new DesktopStressWidgetView(model, hostWindow),
                DesktopWidgetType.Cosmos    => new DesktopCosmosWidgetView(model, hostWindow),
                DesktopWidgetType.TagDos    => new DesktopTagdosWidgetView(model, hostWindow),
                DesktopWidgetType.Weather   => new DesktopWeatherWidgetView(model, hostWindow),
                DesktopWidgetType.Combined  => new DesktopCombinedWidgetView(model, hostWindow),
                _                           => new DesktopCombinedWidgetView(model, hostWindow)
            };
        }
    }
}
