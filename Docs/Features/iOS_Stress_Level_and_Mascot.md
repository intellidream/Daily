# Stress Level & Stylized Monkey Mascot Feature (iOS)

## 1. Overview
The **Stress Level** feature brings real-time autonomic nervous system (ANS) tone tracking to Daily, inspired by the clinical ergonomics of *StressWatch*. It correlates Heart Rate Variability (HRV - SDNN / rMSSD), sedentary heart rate elevation above resting baseline, and sleep recovery multipliers.

To make serious physiological data engaging, uplifting, and accessible, advice is personified through an expressive, procedurally drawn **vector Monkey Mascot** with 4 distinct autonomic states:
- **Zen Monkey** (Restful, 0–25)
- **Curious Monkey** (Calm, 26–50)
- **Busy Monkey** (Moderate, 51–75)
- **Overheated Monkey** (High, 76–100)

---

## 2. Core Clinical Engine (`StressAnalysisEngine.swift`)

The clinical engine computes an intraday stress score on a 0–100 continuous scale:

$$\text{Stress Score} = 0.50 \cdot S_{\text{HRV}} + 0.30 \cdot S_{\text{HR\_elevation}} + 0.20 \cdot S_{\text{sleep\_penalty}}$$

### Component Models:
1. **HRV Sigmoid Transfer Function ($S_{\text{HRV}}$)**:
   - Evaluated against user's individual baseline (default: 45 ms SDNN).
   - Uses a smooth hyperbolic tangent ($\tanh$) sigmoid to prevent hard-clipping artifacts.
   - High HRV indicates parasympathetic tone (score $\to 0$); low HRV indicates sympathetic dominance (score $\to 100$).
2. **Sedentary HR Arousal with Workout Gating ($S_{\text{HR\_elevation}}$)**:
   - Measures elevation of heart rate above resting floor ($HR - RHR$).
   - Active workout hours and step-heavy windows ($>300$ steps/hour) are filtered out so exercise-induced cardiovascular exertion is not misclassified as emotional distress.
3. **Sleep Recovery Multiplier ($S_{\text{sleep\_penalty}}$)**:
   - $100 - \text{SleepScore}$, reflecting nocturnal autonomic restoration.
4. **Intraday 24-Hour Rhythm Generation**:
   - Synthesizes 24 hourly data points reflecting physiological circadian stress curves.

---

## 3. Stylized Procedural Vector Monkey Mascot (`MonkeyMascotView.swift`)

Built purely with declarative SwiftUI vector shapes:
- Expressive stylized face: Head oval, inner face mask, animated expressive eyes with gaze direction, snout, nose, and smiling/concerned mouth.
- Distinct ears with inner ear depth.
- Animated breathing aura: Pulsing radial halo synchronized with parasympathetic rhythm.
- Contextual accessories per mood:
  - **Zen Monkey**: Floating green leaf accessory.
  - **Curious Monkey**: Bright sparkle thought bubble.
  - **Busy Monkey**: Dynamic thermal sweat droplets.
  - **Overheated Monkey**: Animated cooling ice pack.
- Scalable design sizes: `.badge` (22pt), `.mini` (38pt), `.card` (56pt), `.hero` (84pt).

---

## 4. Health Hub Integration (`StressStudioView.swift`)

Integrated seamlessly into the Health Hub:
- **SubTab Switcher**: Added `.stress` ("Stress Studio") with concise tab titles (`Overview`, `Sleep`, `Stress`, `Vitals`, `Trends`) ensuring perfect horizontal proportions.
- **Hero Autonomic Card**: Features the animated vector monkey mascot, current stress score, clinical classification pill, and contextual wisdom snippet.
- **Autonomic Tone Balance Bar**: Visualizes Parasympathetic (Rest & Digest) vs. Sympathetic (Fight or Flight) ratio.
- **Biometric Drivers Grid**: 4 equalized liquid glass cards (104pt fixed height, strict single-line layout ensuring perfect cross-column row alignment):
  - HRV (SDNN) with delta vs baseline.
  - Resting Heart Rate with cardiovascular baseline reference.
  - Sedentary Heart Rate Elevation with arousal classification.
  - Sleep Readiness score with hours asleep.
- **Intraday Stress Rhythm**: 24-hour visual bar chart highlighting peak stress and restful valleys.
- **Interactive Guided Breathwork Player**:
  - 4 clinical protocols:
    - *Physiological Sigh* (Dr. Andrew Huberman: Inhale 4s, Sip 1s, Exhale 8s).
    - *Box Breathing* (Navy SEALs: 4-4-4-4).
    - *Resonance Frequency Flow* (Heart rate variability biofeedback: 5.5s in, 5.5s out).
    - *4-7-8 Relaxation Flow* (Dr. Andrew Weil: 4s in, 7s hold, 8s out).
  - Haptic feedback on phase changes and dynamic animated breathing circle with duration countdown.
- **Overview Preview Card**: Compact preview in Health Overview providing quick navigation to Stress Studio.
- **7-Day Evolution Trends Hub**: Integrated into `HealthTrendsView.swift` and `HealthDataService.swift` with dynamic daily recovery gradient capsule bars, mascot header, and high/low/average/latest statistics.

---

## 5. Widgets Integration

### A. In-App Modular Dashboard Cards
1. **Dedicated Stress Card (`StressDashboardCard.swift`)**:
   - Supports Small, Wide, Tall, and Large layout configurations on the custom dashboard grid.
   - Deep links directly into `daily://health/stress`.
2. **Modular Health Dashboard Card (`HealthDashboardCard.swift`)**:
   - Added Stress across all 4 grid sizes:
     - **Small (1x1)**: Header badge with monkey mascot emoji and score capsule (`🐵 41`).
     - **Wide (2x1)**: 4-column layout (`STEPS` | `HEART` | `SLEEP` | `STRESS`).
     - **Tall (1x2)**: 4 stacked vitals cards with mascot, score, and level pill.
     - **Large (2x2)**: Stress tile in primary vitals grid with mascot, score, and recovery gauge.

### B. Standalone iOS Home Screen Widget (`StressWidget.swift`)
- Supported families: `.systemSmall`, `.systemMedium`, `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`.
- Displays real-time score ring, monkey mascot emoji and mood, HRV metric, autonomic balance bar, and wisdom snippets.

### C. Reorganized Executive Combined Widget (`CombinedWidget.swift`)
- Reworked `.systemSmall` with relaxed vertical spacing (`VStack(spacing: 7.5)`):
  - **Row 1**: 3 Liquid Progress Rings (Sleep, Water, Smokes).
  - **Row 2**: Horizontal Stress bar with 🐵 monkey face, score, status pill, and mini gradient gauge (omits "STRESS" label text to optimize horizontal space).
  - **Row 3**: Single combined row pairing Money (left: `creditcard.fill` + net worth formatted in EUR) and TagDoS (right: compact 4.5pt purple dot indicator + driving task title).
- Updated `.systemMedium` left hero column to include the compact monkey stress pill alongside Sleep Arc and Net Worth.
- Updated `.systemLarge` habits row to a balanced 3-card layout (Hydration, Smokes, and Stress).

---

## 6. Smart Briefing Integration

- `SmartBriefingModels.swift`: Added `stressText` to `SmartBriefingNarrative`; added `stressScore`, `stressStatus`, and `monkeyMood` to `SmartBriefingMetrics`.
- `SmartBriefingService.swift`: Gathers stress telemetry; synthesizes deterministic local narrative voiced by the Monkey Mascot; incorporates stress into data hashing and cache invalidation.
- `GeminiApiService.swift`: Enhanced prompt with `stress` payload and structured JSON schema for AI-generated briefings.
- `SmartBriefingOverlayView.swift`: Added dedicated `Stress & Mind Balance 🐵` briefing card with dynamic status badge color.
- Deep Link: `daily://health/stress` routes directly to the Health tab and selects `.stress` subtab.
