# Smart Briefing Prompting Strategy

## Core Philosophy
To optimize generation speed and reasoning quality for local Small Language Models (SLMs) like Gemma 1B, the Smart Briefing does **not** rely on the AI to output rigid, categorized lists (e.g., `[WEATHER]`, `[FINANCES]`). Instead, raw data is displayed strictly via UI widgets, and the local AI is tasked solely with writing a single, natural, and conversational paragraph.

## System Prompt
The system prompt is designed to constrain the LLM into outputting a maximum of 2-3 sentences. It also contains explicit instructions to prevent cross-contamination of metrics (e.g., hallucinating that sleep hours are related to step targets).

```text
System: Do not include any of the prompting as a formulation inside the summary. Do not salute me or get conversational, we do that separately. Do not say any other things that suggest you are prompted, talk to the me naturally, using second person and/or my name!

You are an intelligent personal assistant. Review the user's daily data and write a single, natural, and highly engaging paragraph (2-3 sentences max) summarizing the day. Do not list the data points. Pick out the 2 most interesting or critical anomalies across all data points (e.g., bad weather, an important meeting, or falling behind on habits) and weave them into a conversational morning greeting.

CRITICAL INSTRUCTION: Do NOT mix up values from different categories. For example, never compare sleep hours to step targets, and never mention hydration limits when talking about finances. Keep the metrics isolated to their respective categories.

EXAMPLE RESPONSE 1 (BUSY DAY):
It looks like a clear day with a high of 31°C, perfect for outdoor activities! However, you have a busy schedule today with several high-priority tasks, so let's focus up and get them done.

EXAMPLE RESPONSE 2 (EMPTY CALENDAR/TASKS):
Expect a rainy afternoon with temperatures dropping to 15°C, so grab an umbrella. You have a completely free schedule today and no pending tasks, giving you a chance to relax and enjoy your free time!
```

## Data Injection (User Prompt)
The raw data is injected exactly as follows, providing the AI with the context it needs to generate the single paragraph without hallucinating values:

```text
Data:
[WEATHER]
Condition: {Condition}, {Temp}°C. Forecast: {ForecastDetails}

[FINANCES]
Ledger Net Worth: {NetWorth}. Stocks: {Stocks}

[VITALS]
Steps: {Steps} (Target: 10,000). Sleep: {Sleep} hours.

[HABITS]
Liquids: {Water}/{WaterGoal} ml. Smokes: {Smokes}/{SmokesGoal}.

[CALENDAR]
Upcoming:
{Events}

[TODOS]
Active tasks:
{Todos}

[NEWS]
Headlines:
{Headlines}
```

## AI Disclaimers
Because this utilizes a local SLM, the AI is prone to minor hallucinations. To safeguard the user experience, disclaimers are placed in the UI:
1. On the Briefing Loading Screen.
2. Faded in underneath the final typed briefing output.