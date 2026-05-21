using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Input;

namespace Daily_WinUI.Helpers
{
    public static class NavigationHelper
    {
        public static bool HandleMouseNavigation(UIElement rootElement, PointerRoutedEventArgs e)
        {
            var properties = e.GetCurrentPoint(rootElement).Properties;
            if (properties.PointerUpdateKind == PointerUpdateKind.XButton1Pressed) // Back button
            {
                if (TryNavigateBack(rootElement))
                {
                    e.Handled = true;
                    return true;
                }
            }
            else if (properties.PointerUpdateKind == PointerUpdateKind.XButton2Pressed) // Forward button
            {
                if (TryNavigateForward(rootElement))
                {
                    e.Handled = true;
                    return true;
                }
            }
            return false;
        }

        private static bool TryNavigateBack(DependencyObject element)
        {
            // 1. Prioritize page-specific custom back handling (e.g. RSS Reader View)
            if (element is Views.RssFeedDetailPage rssPage)
            {
                if (rssPage.TryGoBack())
                {
                    return true;
                }
            }

            // 2. Traversal of children first (innermost elements get priority)
            int childCount = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(element);
            for (int i = 0; i < childCount; i++)
            {
                var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(element, i);
                if (TryNavigateBack(child))
                {
                    return true;
                }
            }

            // 3. Fallback to standard Frame navigation
            if (element is Frame frame && frame.CanGoBack)
            {
                frame.GoBack();
                return true;
            }

            return false;
        }

        private static bool TryNavigateForward(DependencyObject element)
        {
            // Traversal of children first
            int childCount = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(element);
            for (int i = 0; i < childCount; i++)
            {
                var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(element, i);
                if (TryNavigateForward(child))
                {
                    return true;
                }
            }

            // Fallback to standard Frame navigation
            if (element is Frame frame && frame.CanGoForward)
            {
                frame.GoForward();
                return true;
            }

            return false;
        }
    }
}
