# Smart Periodic Briefing & AI Summary System (Next-Gen)

## 1. Executive Summary & Overview
The **Smart Periodic Briefing & Summary System** introduces an intelligent cross-platform briefing experience into the Daily ecosystem. It analyzes all 6 primary data hubs (**Weather**, **Health & Vitals**, **Habits & Cravings**, **Finances & Money**, **TagDoS & Notes**, and **World News**) and presents an executive contextual snapshot tailored to the user's current diurnal phase.

Key visual highlights include:
- **Samsung Galaxy AI-Style Fading Typography**: A progressive word-by-word reveal with progressive opacity ramps, subtle Gaussian blur fades, and an ambient glowing lead cursor (`✨`), without jarring character clacks. Includes tap-to-skip functionality.
- **Diurnal Phase Adaptation**: Distinct intelligence narratives across 4 slots: Morning Awakening (05:00–11:59), Intra-Day Momentum (12:00–17:59), Evening Wind-Down (18:00–21:59), and Nightly Restoration (22:00–04:59).
- **Dual-Tier Hybrid Synthesis Engine**:
  - **Tier 1 (Instant Local Deterministic)**: Runs on-device in $<10$ms with zero network overhead, zero latency, and strict data consistency.
  - **Tier 2 (Cloud Generative via Google Gemini Flash)**: Optional upgrade using Gemini 2.5/1.5 Flash structured JSON generation with a hard 3.5-second timeout and graceful fallback to Tier 1.
- **Micro-Visuals**: Mini-charts embedded in the briefing sheet (Sleep/Recovery gauge, Hydration vs Goal, Smokes vs Baseline gauge, Financial monthly flow snapshot, and TagDoS active stream chips).
- **Zero Regression Isolation**: Cloud records persist to `public.daily_smart_summaries`, guaranteeing 100% isolation from WinUI's legacy `smart_briefings` table.

---

## 2. Architecture & Data Flow

```mermaid
flowchart TD
    subgraph Data Sources [6 Daily Data Hubs]
        W[Weather Service]
        H[Health & Vitals]
        Hab[Habits & Cravings]
        F[Finance Service]
        T[TagDoS Hub]
        N[News Service]
    end

    DataSources --> Aggregator[SmartBriefingService.generateBriefing]
    Aggregator --> HashCheck{SHA-256 Hash Changed & Cached?}

    HashCheck -- "Unchanged (<6h)" --> ReturnCached[Return Cached Briefing - 0ms]
    HashCheck -- "Changed or Missing" --> TierCheck{Gemini API Key Available?}

    TierCheck -- "No / Disabled" --> Tier1[Tier 1: Deterministic Local Synthesizer - <10ms]
    TierCheck -- "Yes" --> Tier2[Tier 2: Gemini Flash AI REST - Timeout: 3.5s]

    Tier2 -- "Success" --> Finalize[Store Cache & Sync to Supabase]
    Tier2 -- "Error / Timeout" --> Tier1
    Tier1 --> Finalize

    Finalize --> UI[SmartBriefingOverlayView]
    UI --> FadingText[Samsung-Style Fading Typography]
    UI --> Gauges[Swift Charts Micro-Gauges]
```

---

## 3. Diurnal Time Slots

| Slot | Time Window | Context & Tone | Focus |
| :--- | :--- | :--- | :--- |
| **Morning Awakening** | 05:00 – 11:59 | Optimistic, motivating, crisp | Sleep score, daily weather forecast, hydration kickoff, primary TagDoS focus |
| **Intra-Day Momentum** | 12:00 – 17:59 | Action-oriented, pace-checking | Hydration pacing, smoke reduction vs baseline, active work streams, midday financial checks |
| **Evening Wind-Down** | 18:00 – 21:59 | Reflective, relaxing | Total daily steps, daily net cashflow, smoke count vs target, TagDoS achievements |
| **Nightly Restoration** | 22:00 – 04:59 | Calming, serene, restorative | Winding down, sleep debt preparation, quiet reflections, tomorrow readiness |

---

## 4. Dual-Tier Hybrid Synthesis Engine

### Tier 1: Deterministic Local Synthesizer (`<10ms`)
- Evaluates metrics from all 6 hubs deterministically using empathetic domain rules.
- **Empathetic Smoking Reduction Coaching**: Recognizes tobacco/heaters as an active habit to conquer. When daily smoke count is below baseline, praises restraint; when elevated, gently encourages hydration and mindful pacing without clinical guilt.
- Generates structured narrative blocks:
  - `greeting`
  - `weatherSummary`
  - `healthSummary`
  - `habitsSummary`
  - `financesSummary`
  - `tagdosSummary`
  - `newsSummary`
  - `actionableSuggestion`
- Prepares numeric telemetry snapshot backing Swift Charts (`SmartBriefingMetrics`).

### Tier 2: Google Gemini Cloud AI (`gemini-2.5-flash` / `gemini-1.5-flash`)
- Activated when user provides an API key in **Settings > Smart Briefing & AI**.
- Structured `responseSchema` forces type-safe JSON directly matching `SmartBriefingNarrative`.
- Strict **3.5-second timeout** ensures instant fallback to Tier 1 local synthesis with zero app freezing or delayed presentation.

---

## 5. UI Presentation & Streamlined Card Architecture

### Pre-arranged Samsung Galaxy AI-Style Fading Cards (`SmartBriefingOverlayView.swift`)
- **Zero Layout Jitter**: All card frames, headers, icons, and metric badges are rendered and geometrically locked from millisecond 0 using transparent typography placeholders.
- **Word-by-Word Progressive Reveal**: Words stream smoothly across the cards with an opacity ramp, subtle Gaussian blur, and a glowing `✨` lead cursor.
- **Active Card Aura**: The active card being written displays an ambient cyan specular border glow.
- **Tap-to-Complete**: Tapping anywhere instantly reveals all words across all cards.

### Integrated Visual Cards
- **⛅ Weather & Atmosphere**: Local temperature and condition badge + concise atmospheric outlook.
- **🛏️ Sleep & Recovery**: Sleep score / resting HR badge + restorative recovery narrative.
- **💧 Habits & Balance**: Hydration volume and smoke reduction count badge + empathetic pacing coach.
- **💳 Financial Snapshot**: Today's net cashflow or overall net worth badge + financial telemetry.
- **🏷️ TagDoS Focus**: Active streams and pending memos badge + priority focus guidance.
- **📰 Headlines Radar**: Top headline badge + curated world news radar.
- **✨ Mindful Focus**: Slot-specific actionable suggestion and mindfulness guidance.

### Diurnal Navigation & Contextual Wishes
- **Warm Top Greeting Pill**: Replaces technical slot ranges (e.g. `Morning Briefing · 05:00-11:59`) with a warm, personal greeting:
  - **Morning**: `☀️ Bună dimineața, Mihai!`
  - **Intra-day**: `☀️ O zi excelentă, Mihai!`
  - **Evening**: `🌆 Bună seara, Mihai!`
  - **Nightly**: `🌙 Noapte bună, Mihai!`
- **Contextual Closing Wish Button**: The bottom action button presents an adapted closing wish and symbol:
  - **Standard**: `[ ☀️ Have a productive day! ]` / `[ ☀️ Have a great day! ]` / `[ 🛏️ Sleep tight & rest well! ]`
  - **Rain-Aware**: When rain, drizzle, or showers are detected in the forecast, the button dynamically adapts to `[ ☂️ Ia o umbrelă azi :)) ]` (`umbrella.fill`).

### Data Realism Across 6 Core Hubs
- **Finances (`SmartLedgerStore`)**: Real Romanian `Lei` formatted with European dot separators (`127.156 Lei`), realistic monthly cash flow (`16.0k / 16.0k Lei`), removing all hardcoded dollar symbols.
- **Tagdos Integration**: Extracts live driving and active uncompleted pills from active streams (e.g. `MG`, `WRK`, `FIT`) and surfaces actionable guidance: `"Uite, asta ai de rezolvat azi: MG, WRK, FIT."` with SF Symbol `"checklist"` and label `"Tagdos"`.
- **Health & Sleep**: Honest reporting; if no sleep session is recorded for today, reports vitals syncing rather than inventing placeholder sleep scores.
- **Habits & Cravings**: Realistic hydration progress tracking and empathetic smoking cessation reinforcement.
- **Weather & Climate**: Real localized temperature in °C, sky conditions, wind speed, and rain detection.

### Companion Enhancements
- **Hero Card Sparkle**: Cleaned up the dashboard hero header by removing the heavy capsule outline around "Briefing", leaving an ambient pulsing `sparkles` icon with full card tap target.
- **Sleep Studio Radial Score Scroll**: Tapping the Sleep Score radial ring triggers a smooth easeInOut scroll down directly to the clinical 4-stage hypnogram container.
- **Habits Widget Water Quick-Add**: Order adjusted to ascending order: `[ 100 ]` (espresso/coffee), `[ 150 ]` (tea/cup), and `[ 300 ]` (glass/bottle).

---

## 6. Database Schema (`public.daily_smart_summaries`)

```sql
CREATE TABLE IF NOT EXISTS public.daily_smart_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    time_slot VARCHAR(20) NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    data_hash VARCHAR(64) NOT NULL,
    narrative JSONB NOT NULL,
    metrics JSONB NOT NULL,
    ai_provider VARCHAR(50) NOT NULL DEFAULT 'local',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_daily_smart_summaries_user_slot UNIQUE (user_id, time_slot)
);

CREATE INDEX IF NOT EXISTS idx_daily_smart_summaries_lookup 
ON public.daily_smart_summaries (user_id, time_slot, generated_at DESC);

ALTER TABLE public.daily_smart_summaries ENABLE ROW LEVEL SECURITY;
```

---

## 7. Quality & Verification
- **Unit Tests**: 41/41 unit tests in `DailyCore` passing 100% green, including diurnal greeting formatting, Tagdos pill resolution, and currency handling.
- **SimulaPhone Verification**: Tested and captured screenshots on iPhone 16 Pro simulator:
  - `simulaphone_dashboard_v3.png`: Hero sparkle, `[ 100 ] [ 150 ] [ 300 ]` water buttons, Romanian `Lei` finances.
  - `simulaphone_briefing_top_v3.png`: `☀️ O zi excelentă, Mihai!`, Tagdos active pills, `Lei` finances, `Have a productive day!` closing button.
  - `simulaphone_sleep_studio_scrolled.png`: Sleep Studio radial ring tap smooth scroll to 4-stage hypnogram and nap breakdown.
- **Physical Device Deployment**: Successfully built arm64 debug package and deployed live to iPhone 16 Pro "Schmitz" (`62990754-1EE9-5A95-A45E-F4A69DA6E591`).
