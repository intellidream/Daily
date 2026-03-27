# Smart Floating Button — Implementation Guide

## Overview

The Smart Button is a floating action button (FAB) that lives in the bottom-right corner of the app. It observes user behavior over time, builds a local **Pattern Engine**, and proactively suggests which widget to visit next — all **without consuming any cloud AI tokens**.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   SmartFab.razor                 │
│         (UI: FAB + badge + glow + label)         │
│  IntersectionObserver tracks visible widget      │
└──────────────┬───────────────┬──────────────────┘
               │               │
       scrollToWidget    RecordTransition
               │               │
┌──────────────▼───────────────▼──────────────────┐
│              SmartAgentService.cs                 │
│    Frequency Map  +  Markov Transition Map        │
│    Time Priors    +  Fallback Heuristics          │
└──────────────┬───────────────┬──────────────────┘
               │               │
       RecordEvent       GetSuggestion
               │               │
┌──────────────▼───────────────▼──────────────────┐
│           SQLite (local, per-user)               │
│   behavior_events  |  navigation_transitions     │
└─────────────────────────────────────────────────┘
```

### Design Principles

- **Zero cloud cost** — All learning happens on-device via frequency counting and Markov chains. No LLM calls.
- **User-scoped** — Events are stored per `UserId` from Supabase auth. The button only appears for authenticated users.
- **Self-pruning** — Events older than 90 days are automatically deleted on each write.
- **Graceful degradation** — When no data exists, falls back to time-of-day heuristics (morning → Vitals, evening → Habits, etc.).

---

## Components

### 1. Data Models (`Models/LocalModels.cs`)

#### `LocalBehaviorEvent` — Table: `behavior_events`

| Column       | Type       | Purpose                                    |
|-------------|------------|--------------------------------------------|
| `Id`        | int (PK)   | Auto-increment primary key                 |
| `UserId`    | string     | Supabase user ID (indexed)                 |
| `WidgetType`| string     | e.g. `"HabitsWidget"`, `"RssFeedWidget"`  |
| `Action`    | string     | e.g. `"view"`, `"log"`, `"suggested_click"`|
| `DayOfWeek` | int        | 0 (Sun) – 6 (Sat)                         |
| `HourOfDay` | int        | 0–23                                       |
| `Timestamp` | DateTime   | UTC timestamp                              |

#### `LocalNavigationTransition` — Table: `navigation_transitions`

| Column       | Type       | Purpose                                    |
|-------------|------------|--------------------------------------------|
| `Id`        | int (PK)   | Auto-increment primary key                 |
| `UserId`    | string     | Supabase user ID (indexed)                 |
| `FromWidget`| string     | Widget user scrolled away from (indexed)   |
| `ToWidget`  | string     | Widget user scrolled to (indexed)          |
| `DayOfWeek` | int        | 0–6                                        |
| `HourOfDay` | int        | 0–23                                       |
| `Timestamp` | DateTime   | UTC timestamp                              |

---

### 2. Service Interface (`Services/ISmartAgentService.cs`)

```csharp
public interface ISmartAgentService
{
    Task RecordEventAsync(string widgetType, string action = "view");
    Task<WidgetSuggestion?> GetSuggestionAsync(string? currentVisibleWidget = null);
    Task InitializeAsync();
    Task RecordTransitionAsync(string fromWidget, string toWidget);
    bool IsReady { get; }
    event Action? OnSuggestionChanged;
}
```

**`WidgetSuggestion`** returned by `GetSuggestionAsync`:
- `WidgetType` — Which widget to suggest (or `""` for idle state)
- `Confidence` — 0.0–1.0 score driving glow intensity
- `Icon` — MudBlazor icon string for the FAB
- `Label` — Human-readable text (e.g. "Log habits", "Go to Read news")
- `IsTransitionBased` — `true` when the suggestion comes from the Markov chain rather than time-based patterns

---

### 3. Pattern Engine (`Services/SmartAgentService.cs`)

The core "brain" uses three layers of prediction, evaluated in priority order:

#### Layer 1: Time-Based Frequency Map

A dictionary keyed by `(DayOfWeek, HourBucket)` where `HourBucket = hour / 2` (12 buckets per day). Each bucket maps widget names to interaction counts.

**Scoring:**
1. Exact bucket match: `count / total` in that bucket
2. Adjacent buckets (±1): weighted at 30% of exact
3. **Time priors** (hardcoded boosts for known patterns):
   - `HealthWidget`: +0.3 boost between 6–10 AM
   - `HabitsWidget`: +0.2 boost mornings (7–11) and evenings (18–23)
   - `RssFeedWidget`: +0.15 boost mornings, lunch, evenings
   - `FinancesWidget`: +0.1 boost mornings and late afternoons

A widget with score ≥ 0.3 is considered a **strong** time-based suggestion.

#### Layer 2: Markov Transition Map (Context-First)

A dictionary keyed by `FromWidget` → `ToWidget` → count. Records where the user deliberately navigates after viewing a specific widget.

**Rules:**
- Needs ≥ 3 total transitions from a widget to activate
- Best destination must have been chosen ≥ 2 times
- Best destination must have ≥ 40% of total transitions (confidence threshold)
- Produces suggestions like "Go to Read news" with the `IsTransitionBased` flag

#### Layer 3: Fallback Heuristics

When neither layer produces a result, a static time-of-day map is used:

| Time         | Suggested Widget |
|-------------|-----------------|
| 6–9 AM      | HealthWidget     |
| 10–11 AM    | HabitsWidget     |
| 12–2 PM     | RssFeedWidget    |
| 3–5 PM      | FinancesWidget   |
| 6–9 PM      | HabitsWidget     |
| Other       | RssFeedWidget    |

#### Absolute Fallback

If all layers fail (or the suggestion matches the currently visible widget), the FAB shows a generic sparkle icon with "What's next?" — it never disappears.

**Priority cascade:**
```
Transition suggestion (Context) → Strong time signal (≥0.25) → Weak time signal (≥0.05) → Fallback heuristic → Idle state
```

---

### 4. UI Component (`Components/Shared/SmartFab.razor`)

#### Visual States

| State                  | Icon                  | Badge                 | Glow              |
|-----------------------|----------------------|----------------------|-------------------|
| Idle (no data)        | ✨ AutoAwesome        | Sparkle (orange)     | None              |
| Time suggestion       | Widget-specific       | Sparkle (orange)     | Pulse if ≥0.7     |
| Transition suggestion | Widget-specific       | Arrow (blue)         | Subtle pulse      |
| Expanded (first tap)  | Same                  | Same                 | Same + label pill  |

#### Interaction Flow

1. **First tap** → Expands to show a label pill (e.g. "Log habits"). Auto-collapses after 3 seconds.
2. **Second tap** (while expanded) → Scrolls to the suggested widget with smooth animation + highlight glow. Records a `suggested_click` event as positive feedback.

#### Viewport-Center & Click Tracking

The FAB uses a combination of mathematical scroll tracking and click intent to determine what you are looking at:

1. **Center-Distance Scroll Tracker**: A `scroll` listener (with an 800ms debounce) calculates the exact absolute center point of every widget. The widget whose center is closest to the middle of the viewport wins.
2. **Global Click Intent**: A `mousedown` listener running in the capture phase catches any click inside a widget. Clicking instantly proves intent, overriding the scroll timer and making that widget active.
3. **Smart Light**: The currently tracked widget is given the `.widget-active-light` CSS class, applying a subtle glowing border so the user visually knows what the algorithm is observing. 

When a widget becomes active via either method, the `OnWidgetVisible` callback fires:

1. Records the navigation transition (previous → current widget).
2. Re-evaluates the suggestion with the new `currentVisibleWidget` context.

#### Authentication Retry

If Supabase auth isn't ready on first load, a retry timer fires every 5 seconds (up to 12 attempts / 60 seconds). Once authenticated, the FAB initializes and shows suggestions.

---

### 5. CSS (`Components/Shared/SmartFab.razor.css`)

Key visual features:
- **Fixed position**: `bottom: 24px; right: 24px` (16px on mobile)
- **Animate-in**: Starts at `scale(0) / opacity: 0`, transitions to `scale(1)` after 1.5s delay
- **Glow pulse** (`.glow`): Expanding shadow ring on a 2.5s loop for confidence ≥ 0.7
- **Subtle glow** (`.glow-subtle`): Blue-tinted ring on a 3s loop for transition suggestions
- **Badge sparkle**: Scales 1→1.15 on a 3s loop. Orange gradient for time-based, blue for transitions
- **Label pill**: Slides in from the right with fade animation, surface-colored rounded pill
- **Widget highlight**: When scrolled to, the target widget gets a 2-pulse glow border (`.widget-highlighted`)

---

### 6. JavaScript Interop (`wwwroot/index.html` → `dailyInterop`)

Three functions under `window.dailyInterop`:

#### `scrollToWidget(elementId)`
Smooth-scrolls to the widget and adds a temporary `widget-highlighted` class (removed after 4.5s).

#### `initWidgetObserver(dotNetRef)`
Hooks up `scroll` and `mousedown` event listeners. Calculates `distance = Math.abs(viewportCenter - widgetCenter)` on scroll stop (800ms debounce). Calls `setSmartLight(widgetType)` to apply the CSS glow and triggers `dotNetRef.invokeMethodAsync('OnWidgetVisible', widgetType)`.

#### `disposeWidgetObserver()`
Disconnects the observer and clears references. Called on component disposal.

---

### 7. Integration Points

#### `Components/WidgetContainer.razor`
Each widget container renders with `id="widget-{WidgetType}"` so the IntersectionObserver and scroll functions can target them.

#### `Components/Layout/MainLayout.razor`
The `<SmartFab />` component is placed after the main content area, rendering as a fixed overlay.

#### `MauiProgram.cs`
Registered as a singleton:
```csharp
builder.Services.AddSingleton<ISmartAgentService, SmartAgentService>();
```

#### `Services/DatabaseService.cs`
Tables created during initialization:
```csharp
await Connection.CreateTableAsync<LocalBehaviorEvent>();
await Connection.CreateTableAsync<LocalNavigationTransition>();
```

#### Widget-level tracking
Individual widgets (e.g. HabitsWidget, RssFeedWidget) inject `ISmartAgentService` and call `RecordEventAsync()` when the user performs meaningful actions (logging a habit, clicking an article).

---

## Data Flow Example

```
User opens app at 8:15 AM Monday
    → SmartFab.OnInitializedAsync()
    → SmartAgentService.InitializeAsync() loads last 30 days from SQLite
    → GetSuggestionAsync(null):
        Time bucket = (Monday, 4) → HabitsWidget has 45 hits, HealthWidget has 30
        Time prior boost: HealthWidget +0.3 (6-10 AM)
        → HealthWidget wins with score 0.62
    → FAB shows ❤️ heart icon with glow

User scrolls past Weather to Habits
    → IntersectionObserver: OnWidgetVisible("HabitsWidget")
    → RecordTransitionAsync("WeatherWidget", "HabitsWidget")
    → GetSuggestionAsync("HabitsWidget"):
        Time signal says HealthWidget (but user is past it)
        Transition map: from HabitsWidget → RssFeedWidget (65% of the time)
        → FAB switches to 📰 article icon with blue badge: "Go to Read news"

User taps FAB once
    → Label expands: "Go to Read news"

User taps again
    → Smooth scroll to RssFeedWidget
    → RecordEventAsync("RssFeedWidget", "suggested_click") → reinforces pattern
```

---

## Cost

- **Cloud AI tokens**: $0.00 — Everything runs locally.
- **Supabase**: No additional usage. Events are stored in on-device SQLite only.
- **Storage**: ~50 bytes per event. At 50 events/day × 90 days = ~450 KB max.

---

## Future Enhancements

- **Weekly Gemini digest**: Send aggregated stats (not raw logs) to Gemini once/week for a personalized "Weekly Wisdom" report (~$0.01/month).
- **Cross-device sync**: Use Supabase Realtime to broadcast behavior events so the Mac FAB reacts to actions on iPhone.
- **Richer Markov chains**: Factor in time-of-day for transitions (morning transitions differ from evening ones).
- **Explicit feedback**: Long-press to dismiss a suggestion, reducing that pattern's confidence.
- **Agent evolution**: Replace the FAB with a conversational agent overlay that uses the same Pattern Engine as context for LLM-powered suggestions.
