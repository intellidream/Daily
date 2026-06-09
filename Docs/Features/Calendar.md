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
