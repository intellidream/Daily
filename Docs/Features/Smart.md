# Feature: Local Smart Intelligence (On-Device NPU/GPU AI)

The Local Smart Intelligence feature integrates lightweight, privacy-first, on-device Small Language Models (SLMs) into the Daily application. It utilizes hardware-accelerated NPUs (Neural Processing Units) and GPUs to power local content summarization, vitals trend analysis, budget recommendations, and daily schedule narrative briefings, all without transmitting personal user data to third-party cloud servers.

---

## 1. Functional Specification

### 1.1 Local Intelligence Engine
- **Hardware-Aware Execution**: The app detects the host machine's hardware capabilities at launch to determine execution strategies:
  - **Copilot+ NPU Acceleration**: On Copilot+ PCs (e.g., ARM64 Snapdragon X Elite, or Intel Lunar Lake / AMD Strix Point devices with 40+ TOPS NPUs), the app runs workloads on the dedicated NPU.
  - **GPU Acceleration**: On devices with dedicated GPUs (NVIDIA/AMD/Intel) or capable integrated graphics, the app falls back to GPU execution via DirectML.
  - **CPU Fallback**: For older hardware, workloads run on the CPU (using optimized INT4 quantized weights) or degrade gracefully by using a secure, remote API (Supabase Edge Functions / OpenRouter).
- **Zero-Installer Bloat (Download-on-Demand)**: To keep the initial application installer small (~80MB), the local AI model is not pre-packaged. Instead, users are prompted in the Settings screen to download a **Local Intelligence Pack** (~1.2GB) containing the model weights. The pack is saved locally in `%LocalAppData%\Daily\models\`.

### 1.2 Smart Features Suite

#### 1.2.1 News Smart Summarizer
- **Distraction-Free Summary**: Extracts bullet points of the key facts, estimated reading time, and sentiment analysis for subscribed RSS/WordPress articles.
- **Interactive Reader Q&A**: Lets users ask questions about the article context (e.g., "What was the company's Q3 revenue mentioned in the text?").

#### 1.2.2 Vitals & Health Coach
- **7-Day Trend Analysis**: Synthesizes Step, Sleep, Heart Rate, Calories, Weight, and HRV trends to provide actionable suggestions.
- **Correlative Insights**: Identifies relationships between distinct metrics (e.g., "Your HRV dropped by 18% on the 2 days you logged less than 1.5L of water. Focus on reaching your water goal today to improve your recovery.").

#### 1.2.3 Financial & Budget Advisory
- **Portfolio Health Commentary**: Generates textual summaries of stock watchlists and asset performance.
- **Weekly Budget Optimizer**: Analyzes transaction categories to recommend adjustments (e.g., "Dining Out expenses are up 15% this week. We suggest reallocating $20 to your emergency savings goal.").

#### 1.2.4 Habits Companion
- **Streak & Consistency Insights**: Analyzes habit history to identify behavioral triggers.
- **Proactive Prompts**: Generates context-aware notifications (e.g., "You typically complete your 'Evening Walk' habit on days you finish your tasks before 5 PM. You have 1 task left—finish it now to keep your walk streak alive!").

#### 1.2.5 Weather & Daily Narrative Briefing
- **Dynamic Morning Narrative**: Merges weather forecast, calendar events, high-priority tasks, and habits into a cohesive "Daily Briefing".
- **Example output**: *"Good morning, Mihai! It's going to be rainy (18°C) today, so we recommend doing your daily cardio habit indoors. You have 3 high-priority tasks due today, and a meeting at 2 PM. Let's make it a great day!"*

#### 1.2.6 Smart Behavior Personalization
- **Behavior-Aware Narrative**: Integrates aggregated 7-day semantic behavior profile statistics (e.g., hydration trends, preferred news topics) to personalize the daily narrative.
- **Dynamic Recommendations**: Tailors news feed suggestions and habit streak warnings based on user pattern history. For full details on database schemas and sync mechanisms, refer to the [Smart Behavior Guide](SmartBehavior.md).

---

## 2. Technical Architecture & Data Model

### 2.1 Native Windows AI vs. Bring-Your-Own-Model (BYOM)
The app implements a **Hybrid AI Provider** model to bridge the gap between platform capabilities:

```mermaid
graph TD
    A["Initialize AI Engine"] --> B{"Is Copilot+ NPU Available?"}
    B -- "Yes (Win 11 24H2)" --> C["Use Windows App SDK AI APIs: Phi Silica"]
    B -- "No" --> D{"Is Local Model Downloaded?"}
    D -- "Yes" --> E["Use ONNX Runtime GenAI + DirectML/QNN EP"]
    D -- "No" --> F["Prompt User to Download Model / Fallback to Remote API"]
```

1. **Windows Copilot Runtime (Built-in Phi Silica)**
   - Utilizes Windows 11's built-in **Phi Silica** (3.3B parameter SLM) via native Windows App SDK APIs.
   - **Advantage**: Requires zero additional downloads, uses the NPU directly with high energy efficiency, and lifecycle management is handled by the OS.
2. **ONNX Runtime GenAI (BYOM fallback)**
   - Executes custom quantized models (e.g., **Qwen-2.5-1.5B-Instruct-INT4** or **Llama-3.2-1B-Instruct-INT4**) using `Microsoft.ML.OnnxRuntimeGenAI.DirectML` or the `QNN` Execution Provider.
   - **Advantage**: Works across all Windows hardware (GPU, Intel/AMD/Qualcomm NPUs, and CPUs).

### 2.2 API Blueprint & Implementation

#### 2.2.1 Service Interface
```csharp
public interface ISmartIntelligenceService
{
    Task<bool> IsModelReadyAsync();
    Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default);
    IAsyncEnumerable<string> GenerateResponseStreamAsync(string systemPrompt, string userPrompt, CancellationToken ct = default);
}
```

#### 2.2.2 Windows App SDK (Phi Silica) Integration
```csharp
using Microsoft.Windows.AI.Generative;

public class PhiSilicaSmartService : ISmartIntelligenceService
{
    private LanguageModel? _model;

    public async Task<bool> IsModelReadyAsync()
    {
        return await LanguageModel.IsAvailableAsync() == LanguageModelReadyState.Ready;
    }

    public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
    {
        if (_model == null)
        {
            _model = await LanguageModel.CreateAsync();
        }
        
        string combinedPrompt = $"<system>{systemPrompt}</system><user>{userPrompt}</user>";
        var result = await _model.GenerateResponseAsync(combinedPrompt).AsTask(ct);
        return result.Response;
    }
    
    // Streaming API utilizes GenerateResponseStreamAsync
}
```

#### 2.2.3 ONNX Runtime GenAI (DirectML/QNN) Integration
Requires the `Microsoft.ML.OnnxRuntimeGenAI.DirectML` or `Microsoft.ML.OnnxRuntime.QNN` NuGet packages.

```csharp
using Microsoft.ML.OnnxRuntimeGenAI;

public class OnnxGenAiSmartService : ISmartIntelligenceService
{
    private Model? _model;
    private Tokenizer? _tokenizer;
    private string _modelPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Daily", "models", "qwen1.5b");

    public Task<bool> IsModelReadyAsync()
    {
        return Task.FromResult(Directory.Exists(_modelPath) && File.Exists(Path.Combine(_modelPath, "model.onnx")));
    }

    public async Task<string> GenerateResponseAsync(string systemPrompt, string userPrompt, CancellationToken ct = default)
    {
        if (_model == null)
        {
            // Set up hardware acceleration options (DirectML for GPU, or QNN for NPU)
            using var o = new OgaHandle();
            _model = new Model(_modelPath);
            _tokenizer = new Tokenizer(_model);
        }

        string formattedPrompt = $"<|im_start|>system\n{systemPrompt}<|im_end|>\n<|im_start|>user\n{userPrompt}<|im_end|>\n<|im_start|>assistant\n";
        
        using var tokens = _tokenizer.Encode(formattedPrompt);
        using var generatorParams = new GeneratorParams(_model);
        generatorParams.SetSearchOption("max_length", 2048);
        generatorParams.SetInputSequences(tokens);

        using var generator = new Generator(_model, generatorParams);
        StringBuilder responseText = new StringBuilder();

        while (!generator.IsDone() && !ct.IsCancellationRequested)
        {
            generator.ComputeLogits();
            generator.GenerateNextToken();
            int nextToken = generator.GetSequence(0)[generator.GetSequence(0).Length - 1];
            string chunk = _tokenizer.Decode(new int[] { nextToken });
            responseText.Append(chunk);
        }

        return responseText.ToString();
    }
}
```

### 2.3 Local Manifest Data Model (`settings.json` entry)
```json
{
  "AI": {
    "IsEnabled": true,
    "SelectedProvider": "Auto",
    "ModelPath": "%LocalAppData%/Daily/models/qwen1.5b",
    "HardwareDevice": "NPU",
    "UseStreaming": true
  }
}
```

---

## 3. UI/UX & Layout

### 3.1 Integrated Views & Interacting Panels
- **Smart Briefing Overlay**: A premium welcome screen that overlays the main dashboard (frosted glassmorphism, adapting to light/dark themes).
  - *Dynamic Typing Narrative*: A Samsung Bixby/Assistant-style text typing block displaying time-adapted greetings and summarized daily highlights.
  - *Typewriter Animation Milestones*: Visual cards slide up and fade into view sequentially as typing progress metrics are reached:
    - **20% Progress**: Fades in the *Weather Forecast card* (max temp, 3-day preview).
    - **40% Progress**: Fades in the *Health & Vitals card* (steps progress, sleep duration, resting heart rate).
    - **60% Progress**: Fades in the *Finances & Watchlist card* (net worth, ticker changes).
    - **80% Progress**: Fades in the *Habits Tracker card* (completion ratio, circular progress).
    - **92% Progress**: Fades in the *AI News Recommendations card* (embedded `NewsRecommendationsWidgetControl` showing custom feed topics).
  - *Responsive Layout & Docking*: Listens to window resizing to toggle layouts. Wide window widths display narrative and cards side-by-side (24px margins). When docked or resized under 850px width, panels stack vertically with narrow margins (6px margins) to optimize layout density.
  - *Start My Day Centering*: The primary action button and "Show at startup" checkbox are vertically and horizontally centered in the actions panel.
- **Settings Panel (AI & Accelerator Preferences)**:
  - Toggle switch for "Startup Smart Briefing" which saves state immediately.
  - Local AI Accelerator combo box to select the hardware device (`Auto`, `NPU`, `Intel AI Boost / AMD IPU`, `DirectML GPU`, `CPU Fallback`).
  - NPU/Hardware engine detection displaying active TOPS metrics and execution provider readiness.
  - "Download AI Pack" button running simulated download progress bar for the 1.2GB model weights and updating status to "Local Engine Active" on finish.

---

## 4. Platform Implementation Differences (WinUI vs. MAUI / Blazor Hybrid)

| Characteristic | WinUI Implementation | MAUI / Blazor Hybrid Implementation |
| :--- | :--- | :--- |
| **Model Runtime** | Direct access to `ONNX Runtime GenAI` and Windows Copilot Runtime APIs | Integrates via native platform-specific OS runtime bindings |
| **NPU Interface** | DirectML / QNN Execution Provider (`QnnHtp.dll` for Snapdragon) | iOS: Apple Intelligence / CoreML (Apple Neural Engine). Android: Gemini Nano / Google AICore APIs |
| **Model Size / Options** | Custom 1.5B–3.8B parameters models (INT4 quantized) | System-managed models (Gemini Nano on Android, Apple intelligence models on iOS) |
| **User Settings UI** | Custom WinUI Settings panel with download-on-demand progress bars | Platform system settings or Blazor settings configurations |
