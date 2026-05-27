# Local LLM Optimization & Alternative Models Research

This document outlines the architectural research, bottlenecks, and optimization strategies for running local generative AI models (such as the Smart Briefing) on Windows desktop devices (Intel/AMD/Qualcomm NPUs and GPUs) compared to mobile AI architectures.

---

## 1. NPU Acceleration Bottleneck on Windows PC
While Windows Copilot+ and Ryzen AI PCs advertise 40-50+ TOPS (Trillions of Operations Per Second) of raw compute, running custom ONNX models via generic libraries can result in slow generation speeds (low Tokens Per Second):

### DirectML vs. Native Hardware SDKs
* **The Current Implementation:** We utilize the `DirectML` execution provider inside the ONNX Runtime GenAI library. DirectML is highly mature and optimized for discrete and integrated graphics cards (GPUs) across NVIDIA, AMD, and Intel.
* **The NPU Deficit:** DirectML does **not** yet have a native, fully-optimized path for Intel AI Boost or AMD Ryzen AI NPUs in generative (auto-regressive) transformer workflows. Targeting NPUs via DirectML often falls back to slow driver paths or CPU-like processing, resulting in sluggish performance.
* **Qualcomm's Built-in Integration:** On Windows Copilot+ PCs, Microsoft's native `LanguageModel` API runs **Phi Silica** on the Qualcomm Hexagon NPU using Qualcomm's native **QNN (Qualcomm Neural Network)** driver. This direct communication bypasses high-level APIs like DirectML, which explains why Phi Silica is extremely fast and power-efficient.

### Recommendation for Native NPU Performance
To harness the true speed of Intel/AMD NPUs, we must utilize vendor-specific compiler execution providers:
* **Intel NPU:** Compile and run the ONNX model using the **OpenVINO Execution Provider** (`OpenVINOExecutionProvider`). OpenVINO provides the highest compilation throughput for Intel hardware.
* **AMD NPU:** Compile and run the model using the **Vitis AI Execution Provider** (part of the AMD Ryzen AI Software stack), designed specifically for the Strix Point and Hawk Point architectures.

---

## 2. Phone AI Speed Analysis (e.g. Samsung Assistant / Gemini Nano)
On-device assistants on mobile flagships feel instantaneous due to key OS and hardware integrations:

1. **System Service Architecture (Android AICore):**
   Unlike a desktop app that loads the model into RAM when triggered, Android runs a persistent background service called **AICore**. The LLM weights (Gemini Nano) are **loaded once during boot** and kept warm in system memory. When an app requests inference, there is zero initialization delay.
2. **Dedicated NPU Drivers:**
   Mobile SOC vendors tightly couple their hardware drivers directly with AICore. The models are quantized to aggressive 4-bit integer weights (INT4) optimized to run directly in the NPU's registers.
3. **Unified Memory Architectures:**
   Mobile chipsets feature unified memory directly accessible by the NPU, minimizing data-transfer latency between CPU and NPU cores.

---

## 3. Alternative On-Device Models
To improve summary accuracy and reduce hallucinations, we can explore alternative open weights:

| Model | Parameter Size | Performance & Quality Profile |
| :--- | :--- | :--- |
| **Llama 3.2 1B** | ~1.2B | *Current Baseline.* Fast on CPU/GPU, but prone to logic hallucinations on structured tabular data. |
| **Qwen 2.5 1.5B / Qwen 3.5 2B** | ~1.5B - 2B | *Recommended.* Exceptional quality-to-speed ratio. Highly accurate for tabular summaries and reasoning tasks, with very fast generation. |
| **Google Gemma 2 2B / Gemma 3 1B** | ~1B - 2B | Extremely high quality for its parameter size. Runs very well on integrated graphics cards but requires optimization for direct NPU runtimes. |
| **Phi-3.5-mini / Phi-4-mini** | ~3.8B | Exceptional reasoning and accuracy, but parameters require ~2.4GB RAM and will run slowly on standard CPU/GPU without NPU acceleration. |

*Note: Google's Gemini Nano weights are proprietary and locked behind the Android/ChromeOS system layer; they cannot be downloaded for direct desktop app integration.*

---

## 4. Next-Steps Strategy for Daily Application

To achieve the best user experience on Intel/AMD machines, the Daily app should adopt a hybrid local AI roadmap:

1. **Model Upgrades:** Add **Qwen 2.5 1.5B Instruct** (quantized INT4) as an alternative downloadable model pack. Its structured JSON/metric handling is vastly superior to Llama 3.2 1B.
2. **Warm-Boot / Pre-loading:** Pre-load the model asynchronously in a background task at application startup rather than waiting for the user to open the Smart Briefing panel.
3. **Multi-Backend Architecture:** Dynamically query and load vendor libraries (Intel OpenVINO / AMD Vitis AI) when the corresponding hardware is detected, moving away from a singular DirectML package.
