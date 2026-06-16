# Feature: Unified Calendar & Tasks (Syncfusion Scheduler & Account Sync)

The Unified Calendar & Tasks feature aggregates schedule data and checklist tasks from multiple cloud calendars (Google Calendar, Microsoft Outlook, Microsoft 365, Yahoo Calendar) and Microsoft ToDo into a single dashboard interface. It features a SQLite caching layer, encrypted credentials synchronization via Supabase, and a Syncfusion WinUI Scheduler view with interactive widgets.

---

## 1. Functional Specification

### 1.1 Multi-Provider Calendar Aggregation
- **Google Calendar**: Integrates with personal Google accounts (read-only) via Google OAuth 2.0.
- **Microsoft Outlook & Microsoft 365**: Connects both personal Outlook (Live, Hotmail) and enterprise Microsoft 365 Company accounts via a unified Azure AD OAuth flow. Retrieves events from the user's primary calendar.
- **Yahoo Calendar**: Connects over CalDAV using Yahoo App Passwords (Basic Auth over HTTPS), enabling users to sync Yahoo calendar events without developer portal setups.
- **Color Coding**: Each connected calendar account is assigned a custom visual color. All associated events and tasks are color-coded in the scheduler grid and widgets for easy differentiation.

### 1.2 Integrated Tasks & Microsoft ToDo Sync
- **Unified List**: Displays Microsoft ToDo tasks directly inside the calendar scheduler grid as all-day appointments pinned to their due dates.
- **Interactive Checkboxes**: Users can check off todo tasks directly on the scheduler page or widget. Checking a task triggers bi-directional sync, sending a PATCH request to Microsoft Graph to mark the task completed.

### 1.3 Adaptive Dashboard Widget
A native XAML dashboard widget (`CalendarWidgetControl.xaml`) supports four distinct sizes (VisualStates):
1. **Small (1x1)**: Displays only the next upcoming agenda item in a compact card.
2. **Normal (2x1)**: Lists up to two upcoming items side by side with a header.
3. **Tall (1x2)**: Displays a scrollable list of upcoming events and todos with checkable list items.
4. **Large (2x2)**: Features a styled date card (month, day number, day name) on the left and a scrollable, checkable upcoming items agenda list on the right.

---

## 2. Technical Architecture & Data Model

### 2.1 Credential Encryption & Supabase Sync
To secure OAuth access tokens and passwords synced to the cloud:
- **AES-GCM Encryption**: Tokens are encrypted using AES-GCM prior to database storage. 
- **User-Specific Key Derivation**: Encryption keys are derived uniquely for each user by combining the Supabase User ID with a static server-side salt via `Rfc2898DeriveBytes` (PBKDF2-SHA256).
- **SQLite Cache**: Connected accounts are cached locally in the SQLite database and pushed to Supabase (`calendar_accounts` table) to sync connected credentials across user devices.

### 2.2 Redirect URI Scheme
- **Microsoft OAuth**: Uses the custom protocol handler `com.intellidream.daily.desktop://login-callback` as its redirect URI. A named-pipe forwarder in [App.xaml.cs](file:///c:/Users/mihai/Source/repos/Daily/WinUI/Daily.WinUI/App.xaml.cs) captures this callback and routes the auth code to the active login task.
- **Google OAuth**: Uses a loopback address redirect URI (`http://localhost:<port>/`) via a dynamically started local `HttpListener` on the client, complying with Google's OAuth 2.0 policy for native desktop applications.

### 2.3 Data Models (`Models/CalendarModels.cs` & `Models/RemoteCalendarModels.cs`)

#### Local SQLite Cache Tables
- **`LocalCalendarAccount`**: Caches account metadata, encryption tokens, validation expiry dates, user-selected display colors, and active status.
- **`LocalCalendarEvent`**: Caches events with unique `ProviderEventId` identifiers, location, dates, titles, and descriptions.
- **`LocalCalendarTodo`**: Caches task items containing `ProviderTodoId`, notes, due dates, completion dates, and priority status.

#### Database Service Integration (`DatabaseService.cs`)
The local SQLite initialization creates:
- `local_calendar_accounts`
- `local_calendar_events`
- `local_calendar_todos`

---

## 3. UI/UX & Layout

### 3.1 Syncfusion WinUI Scheduler (`CalendarDetailPage.xaml`)
- **Control**: Hosts `SfScheduler` bound to the cached events collection.
- **Views**: Supports toggling between **Day**, **Week**, **Work Week**, and **Month** views.
- **Appointments Mapping**: Custom mapping binds properties of `CalendarAppointment` (subject, start time, end time, location, notes, background) to the Syncfusion scheduler's internal appointment engine.
- **Interaction**: Tapping an appointment displays a dialog with location and description details. Tapping a ToDo appointment opens a checklist dialog where users can toggle task completion.

### 3.2 Side Panel Accounts Management
- Displays currently linked accounts.
- Toggles account active status (filters out events on the scheduler without deleting credentials).
- Changes account display colors using a quick preset palette.
- Initiates manual credential link flows for Google, Microsoft, and Yahoo accounts.

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **UI Technology** | Native XAML Controls (`CalendarWidgetControl.xaml` & `CalendarDetailPage.xaml`) | Not currently implemented (WinUI-exclusive) |
| **Scheduler Engine** | Syncfusion WinUI Scheduler (`SfScheduler`) | Native HTML Table / MudBlazor list layout |
| **Visual States** | VisualStateManager with native XAML states (`SmallState`, `NormalState`, etc.) | CSS Media queries & MudBlazor Breakpoint listeners |
| **OAuth Catching** | Native WinUI protocol activation and named-pipe forwarder | System web views or MAUI WebAuthenticator callback handlers |
| **Credential Storage** | Encrypted locally in SQLite and synchronized to Supabase | SQLite encrypted local variables |

---

## 5. Recent Improvements (June 2026)

### 5.1 Authentication & Multi-Account Support
- **Multi-Account Account Switching**: Added `prompt=select_account` to Google and Microsoft OAuth authorization URLs. This prevents the browser from automatically logging in using the default browser session and enables users to connect multiple distinct accounts.
- **Enterprise Microsoft 365 Support**: Refactored Microsoft Graph user endpoints and database mapping to support corporate and school accounts (`MicrosoftWork`) alongside personal Outlook profiles (`MicrosoftPersonal`).
- **Google Sync Loop Prevention**: Resolved infinite loading and synchronization loop triggers by adding local SQLite verification guards, stopping redundant sync cascades.

### 5.2 Yahoo CalDAV & Timezone Synchronization
- **Yahoo CalDAV Auto-Discovery**: Added a Basic Auth CalDAV interface over HTTPS for Yahoo Calendar. The service automatically performs XML `PROPFIND` queries to discover calendar folders.
- **Timezone Offset Correction**: Resolved timezone offset conversion bugs (e.g. Romanian timezone) that shifted single-day events into late night or early morning hours.

### 5.3 Unified Header UI & Glassmorphic Styling (June 2026)
- **Interactive Calendar Header Button**: Merged the left sidebar collapse button and the calendar icon into a single circular `40x40px` glass button (`CornerRadius="20"`). It displays the calendar icon (`&#xE787;`) and functions as the sidebar toggle, removing header clutter.
- **Custom Header Layout & Date Selection**: Migrated from the native Syncfusion header control to a fully custom XAML header layout by setting `HeaderHeight="0"`. This custom header houses an interactive date range button, a navigation stack (previous, next, and Today buttons), and the view switcher panel side-by-side in a single grid row.
- **Header Layout Ordering**: Positioned the navigation controls stack (previous, Today, and next buttons) on the far left of the header area, and the Date Range Selector button immediately to its right.
- **Narrow Width Window Adaptation (Responsive Header UI)**: Added a `SizeChanged` event handler that calculates the available scheduler header width dynamically (subtracting the 340px sidebar when open) to adapt layout density when the scheduler area is narrow (`availableWidth < 700`):
  - **Connected Accounts Sidebar Auto-Collapse**: Collapses the connected accounts sidebar panel (by setting `ToggleSidebarBtn.IsChecked = false`) when window width drops below `950px` to immediately reclaim horizontal space.
  - **Date Format Minimization**: Swaps verbose dates (e.g., "June 2026", "June 11, 2026") for shorter, abbreviated formats (e.g., "Jun 2026", "Jun 11, 26", or "05/31 - 06/04").
  - **Today Button Compact View**: Hides the "Today" text string, displays a calendar-home icon (`&#xE895;`), and shrinks the button into a square `32x32px` profile matching the adjacent navigation arrow buttons.
  - **View Switcher Label Abbreviation**: Shortens the view switcher segment labels to single-letter/compact codes ("D", "W", "Wk", "M") and reduces their internal padding to prevent layout overlapping.
- **Interactive Date Selector Button with High-Contrast Arrow**: Wrapped the date range `TextBlock` inside a transparent `Button` that triggers a `Flyout` containing a `CalendarView`. Choosing a date in the calendar view updates the scheduler's display date programmatically and closes the flyout. Added a prominent, high-contrast dropdown chevron icon (`&#xE70D;` from Segoe Fluent Icons, `FontSize="12"`, solid foreground, full opacity) next to the date text, providing a clear visual indicator that the header is clickable to open a calendar view. The calendar view selection is synchronized bi-directionally whenever the scheduler range navigates (e.g. Prev/Next/Today).
- **Today & Navigation Button Alignment**: Designed the custom Today, previous, and next navigation buttons to be squarer (`CornerRadius="6"`) and taller (`Height="32"`), matching the height and corner radius of the view switcher pane exactly, utilizing matching glassy backdrops (`AppGlassSubColorBrush` and `AppGlassBorderColorBrush` border).
- **Add New Account Expander & Redesigned Connection Buttons**:
  - Renamed the connection panel header from **"Link New Calendar"** to **"Add New Account"**.
  - Redesigned the Google, Microsoft, and Yahoo connection buttons inside the expander to just display **"Google"**, **"Microsoft"**, and **"Yahoo"** respectively.
  - Styled the buttons to be larger and more prominent (`Height="48"`, `CornerRadius="10"`), utilizing larger brand icons (`FontSize="18"`), bold text, and vibrant color-tinted glassy backdrops.

### 5.4 Dashboard Widget Layout & State Fixes (June 2026)
- **Overlapping Stacks Resolved**: Replaced the `<Grid>` layout panel in the widget's `SmallState` (1x1 view) with a standard vertical layout, stopping multiple upcoming items from drawing directly on top of each other.
- **Adaptive Size Constraints**: Introduced distinct `SmallItems` (up to 2 items) and `NormalItems` (2 items) collections populated during data loading. The 2x1 view binds to the top two horizontal cards, and the 1x1 view binds to the vertical list.
- **1x1 Multi-Item Support**: Redesigned the small state widget layout in `CalendarWidgetControl.xaml` to render up to 2 items vertically. Items are styled in an extremely compact template (`Height="52"`, `Padding="8,6"`, `Margin="0,0,0,6"`, smaller text size and character truncation) that prevents layout overflow.
- **Full Width Grid Alignment**: Removed the ColumnDefinitions grid constraint inside the `NormalContainer` (2x1 view), letting the wide horizontal stack stretch across the full width of the cell rather than squishing in the left 50% section.
- **Boolean State Indicators**: Exposed indicator flags (`HasSmallItems`, `HasNormalItems`, `HasUpcomingItems`) to safely control empty state fallback visibility via the native `InverseBooleanToVisibilityConverter`.
- **In-Widget Item Cap**: Limited the total scrollable upcoming items collection to a maximum of 15 items to keep the widget lightweight.

### 5.5 Account Personalization, Reordering & Sidebar Memory (June 2026)
- **Premium Color Presets**: Expanded color preset choices from 6 to 11 items (adding Teal, Pink, Lavender, Coral, and Mint) and adjusted horizontal layout spacing to `6px`. To prevent clipping, the color picker and drag handle are placed inside a nested Grid spanning all three columns (`Grid.ColumnSpan="3"`), allowing all 11 colors to stretch dynamically up to the drag handle.
  - **Visual Selection Ring**: Added an outer selection ring `Border` around the color preset buttons. It dynamically displays a high-contrast border outline (`1.5` thickness and standard foreground color) only when a preset matches the account's active color. This is achieved cleanly using a `ColorPresetItem` data wrapper model, bypassing complex value converter resources.
- **Account Renaming & Display Hierarchy**:
  - Enabled inline editing of account names (saved on Enter, cancelled on Escape).
  - Without Custom Name: Shows Email as main title, and Provider/Org as subtitle.
  - With Custom Name: Shows Custom Name as main title, Email as subtitle, and Provider/Org as a more transparent, smaller footer.
- **Drag-and-Drop Reordering**: Migrated the accounts management list to a `ListView` supporting native drag reordering (`CanReorderItems="True"`, `AllowDrop="True"`). Order indices are persisted in the SQLite database (`DisplayOrder` field).
  - **Hover and Drag Highlight**: Added a visual reorder indicator icon (`&#xE700;` hamburger glyph from Segoe Fluent Icons) to the far right of the card. To suggest drag interactivity, the hamburger handle "lights up" to full `1.0` opacity and the OS `SystemAccentColorBrush` (guaranteeing high-contrast visibility on both Light and Dark themes) whenever the mouse hovers over the card or while dragging is active (muted to `0.4` opacity and gray when idle).
- **Sidebar Layout Float & Transitions**:
  - **Symmetrical Layout Margin**: Styled the sidebar border with `Margin="20,0,0,20"`, full borders (`BorderThickness="1"`), and `CornerRadius="12"`, creating a floating glassy panel that matches the scheduler container spacing and rounding exactly.
  - **Slide-and-Fade Transition Animation**: Wrapped the sidebar panel inside a `SidebarContainer` Grid and programmed a `Storyboard` that animates the container's `Width` (0 to 360px), `Opacity` (0.0 to 1.0), and the panel's `TranslateTransform.X` (0 to -360px) using cubic easing (`CubicEase` over 250ms). By setting the inner `SidebarPanel` to `HorizontalAlignment="Left"` and setting the margin to `20,0,0,20`, the panel's right edge aligns perfectly with the container's right edge at every frame of the translation, causing the sidebar to smoothly roll/slide into and out of the left screen boundary flush with the scheduler resizing.
  - **Synchronized Scheduler Parallax Animation**: Coupled the scheduler container Grid (`SchedulerContainer`) to the toggle animation by adding a `TranslateTransform` (`SchedulerTranslate`) and animating its `X` coordinate from `-80` to `0` (on sidebar open) and from `80` to `0` (on sidebar close). This creates a synchronized, hardware-accelerated parallax slide transition, giving the scheduler container a natural physical sliding motion as it stretches/reclaims column space in sync with the collapsing accounts pane.
  - **State Capture & Layout Robustness**: To ensure transitions play fluidly in both directions and do not trigger jumps during rapid toggle clicks, the logic captures the current `ActualWidth`, `Opacity`, `SidebarTranslate.X`, and `SchedulerTranslate.X` values as starting points immediately before stopping any active storyboards.
  - **Constraint-Based Scroll Containment**: Removed the redundant outer ScrollViewer, placing the accounts `ListView` directly inside the Grid row (row height set to `*`). The `ListView` constraints restrict its height automatically, enabling high-performance vertical scrolling inside its own container without pushing down or overlapping the bottom "Add New Account" Expander.
- **Accounts Sidebar Layout Memory**: Saved the sidebar pane open/closed toggle state inside LocalSettings so that it is restored on page navigation.
- **Outlook/Microsoft Personal Account Email Fetch & Fallbacks**:
  - Requested `User.Read` scope during Microsoft OAuth links.
  - Implemented a fallback query to primary calendar metadata (`GET /me/calendar` for `owner.address`) under `Calendars.Read` scope if the profile lookup fails.
  - Programmed a self-healing background sync routine to update the local SQLite database email cache for legacy calendar connections.
  - **Local Time & Timezone Conversion Fix**: Configured the Microsoft Graph API request to return dates converted to UTC by sending the `Prefer: outlook.timezone="UTC"` header. Added robust timezone parsing using `SafeFindTimeZone` to parse Microsoft's timezone strings (converting naive local datetimes to UTC) to guarantee that Outlook events show up in the correct local time on the calendar, matching Google and Yahoo calendars.
- **Robust Virtualization & Toggling Feedback Loop Fix**: Resolved timing race conditions, container recycling bugs, and programmatic toggle loops in the side panel connected accounts list:
  - Changed the `ToggleSwitch.IsOn` binding from `TwoWay` to `OneWay` to stop direct property write-backs during virtualization.
  - Implemented in-place synchronization of the `Accounts` collection in `LoadAccountsAsync()` instead of clearing the list, maintaining list focus and preventing visual jumps.
  - Defer resetting the `_isUpdatingAccountsList` update gate using `DispatcherQueue.TryEnqueue` to shield the control against programmatic toggles during collection changes.
  - Restricted the background `OnCalendarDataChanged` event handler to only call `LoadEventsAsync()`, leaving the static accounts list completely stable and untouched during active state toggles. This entirely eliminates background rebindings, container recycling, and focus leaks, making toggles 100% stable and responsive.


### 5.6 Scheduler View Persistence & Switcher Highlights (June 2026)
- **View Selection Memory**: Saved the last selected view type (Day, Week, Work, Month) inside LocalSettings and restored it on page navigation.
- **Visual Highlight**: Added active button selection highlighting in the view switcher. The selected button is given a solid glassy background (`AppGlassColorBrush`) and solid white text, while unselected ones remain transparent and muted.

### 5.7 Today's Date Highlight & Theme Adaptations (June 2026)
- **WinUI XamlParseException Crash Resolution**: Completely resolved runtime XAML resource parsing crashes on calendar open by removing unsafe direct `{ThemeResource}` color dictionary references (`SystemAccentColorLight2` and `SystemAccentColorDark1` color keys) from [App.xaml](file:///c:/Users/mihai/source/repos/Daily/WinUI/Daily.WinUI/App.xaml).
- **Dynamic Today Cell Highlight Glow**: Implemented `TodayBackgroundGlowConverter` which programmatically extracts the active theme's accent color from `AccentFillColorDefaultBrush` (using the Dark/Default theme's `SystemAccentColorLight2` variant) at `0.04` opacity, ensuring a safe, consistent background glow in both Light and Dark modes.
- **Unified Light-Blue Accent for Today Circle Badge**: Integrated `TodayCircleBadgeBrushConverter` which dynamically retrieves the light-blue system accent color variant (`SystemAccentColorLight2` from the `"Dark"` theme dictionary) in both themes, rendering today's date badge background circle (e.g. "16") consistently in both Light and Dark modes.
- **Theme-Consistent Time of Day Line**: Programmed `UpdateCurrentTimeIndicatorStroke()` to query the light-blue system accent variant from the `"Dark"` theme dictionary, ensuring the Day/Week/Work views' hour indicator line stays identical in color across all themes.
- **Connected Accounts Selected Preset Color Circle Theme Adaptation**: Updated the selection ring around the selected color preset dot in the accounts panel template to use `{ThemeResource AppFgColorBrush}` in [CalendarDetailPage.xaml](file:///c:/Users/mihai/source/repos/Daily/WinUI/Daily.WinUI/Views/CalendarDetailPage.xaml). Removed the code-behind property `SelectionBrush` from `ColorPresetItem` in [CalendarDetailPage.xaml.cs](file:///c:/Users/mihai/source/repos/Daily/WinUI/Daily.WinUI/Views/CalendarDetailPage.xaml.cs). The selection border now automatically and instantly adapts to dark mode (white ring) and light mode (dark-gray ring) when switching themes.

### 5.8 Custom Refresh Button & Synchronization Integration (June 2026)
- **Local Refresh Button**: Added a glassy Refresh button next to the view switcher in the custom scheduler header of [CalendarDetailPage.xaml](file:///c:/Users/mihai/source/repos/Daily/WinUI/Daily.WinUI/Views/CalendarDetailPage.xaml). Triggering this button invokes a cloud synchronization (`_calendarService.SyncAllCalendarsAsync()`) while showing a progress ring overlay.
- **Global Refresh Button Integration**: Configured [CalendarWidgetControl.xaml.cs](file:///c:/Users/mihai/source/repos/Daily/WinUI/Daily.WinUI/Controls/CalendarWidgetControl.xaml.cs) so that triggering the widget refresh (e.g., via the main window's global refresh button) initiates a full background cloud synchronization prior to loading local cached calendar items.
- **Title Bar Refresh Management**: Updated `RefreshFromTitleBarAsync` to activate the `IsLoading` progress indicator during the entire lifecycle of the data fetch and cloud sync.
