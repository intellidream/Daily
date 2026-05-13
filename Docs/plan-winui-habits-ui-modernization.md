# 🎯 WinUI Habits UI Modernization

## Understanding
The WinUI habits widget and detail page need a visual rebuild so they feel much closer to the MAUI experience while staying WinUI3-native. The goals are to preserve behavior, improve spacing and responsiveness for desktop/mobile window sizes, use Syncfusion where it adds value, and refine the consistency heatmap and chart layout on the detail page.

## Assumptions
- The MAUI reference implementation is the source of truth for layout, hierarchy, and quick actions.
- We should keep current data loading and command handlers intact unless a UI change requires minor binding adjustments.
- WinUI-native Fluent/Segoe iconography is acceptable if it avoids adding unnecessary dependencies.
- Syncfusion Gauge controls can represent multiple segments via multiple ranges, which is appropriate for the water widget breakdown.
- The detail page should remain a single page with responsive sections rather than navigation changes.

## Approach
First, compare the MAUI habits widget and detail page with the WinUI counterparts to identify the biggest gaps in hierarchy, density, and responsiveness. Then redesign the WinUI widget to use a more MAUI-like circular progress presentation, add labeled quick actions with coherent icons, and use gauge ranges or a similar multi-segment visualization to represent water, coffee, and tea contributions. After that, rework the detail page into responsive cards that adapt to wider desktop layouts and tighter mobile layouts: make the consistency heatmap span more width, place the history graph beside it when there is room, and preserve existing log/history/configuration functionality. Finally, validate the build and correct any XAML or binding issues.

## Key Files
- `WinUI/Daily.WinUI/Controls/HabitsWidgetControl.xaml` - widget visual redesign.
- `WinUI/Daily.WinUI/Controls/HabitsWidgetControl.xaml.cs` - preserve and, if needed, extend quick-add behavior and progress aggregation.
- `WinUI/Daily.WinUI/Views/HabitsDetailPage.xaml` - responsive detail page layout update.
- `WinUI/Daily.WinUI/Views/HabitsDetailPage.xaml.cs` - keep behavior and data bindings aligned with the revised layout.
- `Components/Widgets/HabitsWidget.razor` - MAUI visual reference for parity.
- `Components/Pages/HabitsDetail.razor` - MAUI visual reference for parity.

## Risks & Open Questions
- The WinUI Syncfusion gauge API may require a slightly different composition than the MAUI-style circular progress, so the final implementation may need iteration.
- The current WinUI code appears to support only a limited set of quick-adds; expanding the UI should not introduce broken or misleading actions.
- The user mentioned smokes subtypes and outline icons broadly; exact icon choices may need refinement based on available WinUI glyphs.

**Last Updated**: 2026-05-12 22:33:34

## 📝 Plan Steps
-  **Inspect the MAUI habits widget and detail page more closely to capture layout patterns, quick actions, and visual hierarchy.**
-  **Redesign the WinUI habits widget XAML to use a richer circular progress presentation and a closer MAUI-like layout.**
-  **Update the widget code-behind if needed to support the new visual breakdown and preserve click behavior.**
-  **Rebuild the WinUI habits detail XAML into responsive cards with a wider heatmap and a better chart/heatmap arrangement.**
-  **Adjust the habits detail code-behind only where bindings or layout state require support for the new visual structure.**
-  **Validate the WinUI project build and fix any XAML/binding errors.**
-  **Review the result against the MAUI reference and make any final UI polish corrections.**
