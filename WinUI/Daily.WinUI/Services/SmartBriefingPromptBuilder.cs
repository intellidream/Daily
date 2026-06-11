using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Daily.Models;
using Daily.Models.Health;
using Daily.Models.Finances;

namespace Daily_WinUI.Services
{
    public sealed class SmartBriefingPromptBuilder
    {
        public string SystemPrompt { get; private set; } = string.Empty;
        public string UserPrompt { get; private set; } = string.Empty;

        // Current parameters (adjusted by pruning)
        public int CalendarEventCount { get; private set; } = 5;
        public int TodoCount { get; private set; } = 8;
        public int NewsHeadlineCount { get; private set; } = 5;
        public int StockCount { get; private set; } = 10;
        public int DescriptionTruncateLength { get; private set; } = 120;
        public bool IncludeHourlyWeather { get; private set; } = true;
        public bool IncludeBehaviorTelemetry { get; private set; } = true;

        public void Build(SmartBriefingData data, string userName, string behaviorSummary, int budgetLimitTokens)
        {
            CalendarEventCount = 5;
            TodoCount = 8;
            NewsHeadlineCount = 5;
            StockCount = 10;
            DescriptionTruncateLength = 120;
            IncludeHourlyWeather = true;
            IncludeBehaviorTelemetry = true;

            int step = 0;
            while (step < 12)
            {
                SystemPrompt = BuildSystemPrompt();
                UserPrompt = BuildUserPrompt(data, userName, behaviorSummary);

                int estimatedTokens = EstimateTokens(SystemPrompt, UserPrompt);
                System.Diagnostics.Debug.WriteLine($"[SmartBriefingPromptBuilder] Step {step}: Estimated tokens: {estimatedTokens} / Budget: {budgetLimitTokens}. Prune Config: telemetry={IncludeBehaviorTelemetry}, news={NewsHeadlineCount}, stocks={StockCount}, todos={TodoCount}, events={CalendarEventCount}, trunc={DescriptionTruncateLength}, hourlyWeather={IncludeHourlyWeather}");

                if (estimatedTokens <= budgetLimitTokens)
                {
                    break;
                }

                // Prune one level at a time based on the step count
                switch (step)
                {
                    case 0:
                        IncludeBehaviorTelemetry = false;
                        break;
                    case 1:
                        NewsHeadlineCount = 2;
                        break;
                    case 2:
                        StockCount = 5;
                        break;
                    case 3:
                        TodoCount = 4;
                        break;
                    case 4:
                        CalendarEventCount = 2;
                        break;
                    case 5:
                        DescriptionTruncateLength = 60;
                        break;
                    case 6:
                        IncludeHourlyWeather = false;
                        break;
                    case 7:
                        NewsHeadlineCount = 0;
                        break;
                    case 8:
                        StockCount = 0;
                        break;
                    case 9:
                        TodoCount = 1;
                        break;
                    case 10:
                        CalendarEventCount = 1;
                        break;
                    default:
                        // No more pruning possible, break to prevent infinite loop
                        break;
                }
                step++;
            }
        }

        private string BuildSystemPrompt()
        {
            return 
                "You are DayOne, a helpful personal assistant AI running locally on the user's device. " +
                "Generate a concise, natural, and friendly daily briefing narrative based on the user's data. " +
                "Analyze their weather, calendar events, active tasks/todos, habits, finances, health, and 7-day behavior logs to provide cohesive insights and encouraging advice.\n" +
                "Rules:\n" +
                "- Do NOT write any greeting (like 'Good morning', 'Good evening', 'Hello', etc.) or introductory filler (like 'Here is your briefing' or 'Based on your data'). Start directly with the weather and calendar analysis.\n" +
                "- Keep the briefing structured in 2-3 short, focused paragraphs of conversational flowing text. Keep descriptions extremely concise and direct to stay on point and avoid hallucinating details. Do not use markdown headers or lists.\n" +
                "- Format your paragraphs clearly, using double newlines (\\n\\n) to separate them.\n" +
                "- Integrate the user's scheduled calendar events and active tasks (todos) with their notes naturally, suggesting when they might focus on tasks or highlighting busy periods.\n" +
                "- If finance data is marked as UNINITIALIZED, do not congratulate the user on net worth or mention a $0 net worth. Suggest setting up their ledger or adding an account instead.\n" +
                "- If smoking habit data is present, treat it as a negative target (reduction/cessation). Do NOT congratulate the user for smoking or logging smokes; instead, encourage reduction or praise staying under limit.\n" +
                "- Evaluate the weather forecast over the next hours and next 5 days, highlighting key transitions (e.g. if it will rain later, recommend taking an umbrella or exercising indoors).\n" +
                "- Evaluate the news headlines provided and concisely summarize the most important trends or events in a paragraph.\n\n" +
                "At the very end of your response, you MUST append a JSON block enclosed in <insights> and </insights> tags. The JSON must contain short advice strings (1 sentence each) for the widgets: " +
                "{\n" +
                "  \"weatherAdvice\": \"short advice based on weather forecast\",\n" +
                "  \"healthAdvice\": \"short advice based on vitals/sleep\",\n" +
                "  \"financeAdvice\": \"short advice based on ledger/watchlist\",\n" +
                "  \"habitsAdvice\": \"short advice based on water/smoking\"\n" +
                "}\n" +
                "Do not write any introductory or transition text before or after the JSON block. Go directly from the end of your narrative text to the <insights> tag. Do not write any text after the </insights> tag.";
        }

        private string BuildUserPrompt(SmartBriefingData data, string userName, string behaviorSummary)
        {
            var sb = new StringBuilder();
            sb.AppendLine($"User Name: {userName}");
            sb.AppendLine($"Current Time: {DateTime.Now:f}");
            sb.AppendLine();

            sb.AppendLine("--- WEATHER DATA ---");
            sb.AppendLine($"Condition: {data.WeatherCondition} (Temp: {data.WeatherTemp}°C)");
            if (IncludeHourlyWeather && !string.IsNullOrEmpty(data.WeatherHourlyDetails))
            {
                sb.AppendLine("Hourly Forecast (next 8 hours):");
                sb.AppendLine(data.WeatherHourlyDetails.TrimEnd());
            }
            if (!string.IsNullOrEmpty(data.WeatherFiveDayDetails))
            {
                sb.AppendLine("5-Day Forecast:");
                sb.AppendLine(data.WeatherFiveDayDetails.TrimEnd());
            }
            sb.AppendLine();

            sb.AppendLine("--- CALENDAR EVENTS TODAY ---");
            if (data.CalendarEventsToday.Count > 0 && CalendarEventCount > 0)
            {
                var limitEvents = data.CalendarEventsToday.Take(CalendarEventCount).ToList();
                foreach (var ev in limitEvents)
                {
                    string timeStr = ev.IsAllDay ? "All Day" : $"{ev.Start.ToLocalTime():t} - {ev.End.ToLocalTime():t}";
                    string desc = ev.Description ?? "";
                    if (desc.Length > DescriptionTruncateLength)
                    {
                        desc = desc.Substring(0, DescriptionTruncateLength) + "...";
                    }
                    sb.AppendLine($"- {ev.Title} ({timeStr}){(string.IsNullOrEmpty(ev.Location) ? "" : $" at {ev.Location}")} - Description: {desc}");
                }
                if (data.CalendarEventsToday.Count > CalendarEventCount)
                {
                    sb.AppendLine($"- ... and {data.CalendarEventsToday.Count - CalendarEventCount} more calendar event(s).");
                }
            }
            else
            {
                sb.AppendLine("No events scheduled for today.");
            }
            sb.AppendLine();

            sb.AppendLine("--- ACTIVE TASKS & TODOS ---");
            if (data.ActiveTodos.Count > 0 && TodoCount > 0)
            {
                var limitTodos = data.ActiveTodos
                    .OrderByDescending(t => t.Importance?.ToLower() == "high")
                    .Take(TodoCount)
                    .ToList();
                foreach (var td in limitTodos)
                {
                    string dueStr = td.DueDate.HasValue ? $"Due: {td.DueDate.Value.ToLocalTime():d}" : "No due date";
                    string notes = td.Notes ?? "";
                    if (notes.Length > DescriptionTruncateLength)
                    {
                        notes = notes.Substring(0, DescriptionTruncateLength) + "...";
                    }
                    sb.AppendLine($"- {td.Title} ({dueStr}, Priority: {td.Importance}) - Notes: {notes}");
                }
                if (data.ActiveTodos.Count > TodoCount)
                {
                    sb.AppendLine($"- ... and {data.ActiveTodos.Count - TodoCount} more active task(s).");
                }
            }
            else
            {
                sb.AppendLine("No active tasks/todos.");
            }
            sb.AppendLine();

            sb.AppendLine("--- NEWS HEADLINES ---");
            if (data.TopNewsHeadlines.Count > 0 && NewsHeadlineCount > 0)
            {
                var headlines = data.TopNewsHeadlines.Take(NewsHeadlineCount).ToList();
                foreach (var headline in headlines)
                {
                    sb.AppendLine(headline);
                }
                if (data.TopNewsHeadlines.Count > NewsHeadlineCount)
                {
                    sb.AppendLine($"- ... and {data.TopNewsHeadlines.Count - NewsHeadlineCount} more news headline(s).");
                }
            }
            else
            {
                sb.AppendLine("No news headlines available.");
            }
            sb.AppendLine();

            sb.AppendLine("--- HEALTH DATA ---");
            sb.AppendLine($"Steps Today: {data.HealthSteps}");
            sb.AppendLine($"Sleep Last Night: {data.HealthSleepHours:F1} hours");
            sb.AppendLine($"Average Heart Rate: {data.HealthAvgHr} BPM");
            if (data.HealthWeight > 0) sb.AppendLine($"Weight: {data.HealthWeight:F1} kg");
            if (data.HealthActiveEnergy > 0) sb.AppendLine($"Active Energy Burned: {data.HealthActiveEnergy:F0} kcal");
            if (data.HealthHrv > 0) sb.AppendLine($"Heart Rate Variability (HRV): {data.HealthHrv:F0} ms");
            if (data.HealthBpSystolic > 0 && data.HealthBpDiastolic > 0)
                sb.AppendLine($"Blood Pressure: {data.HealthBpSystolic:F0}/{data.HealthBpDiastolic:F0} mmHg");
            if (data.HealthSpO2 > 0) sb.AppendLine($"Oxygen Saturation (SpO2): {data.HealthSpO2:F1}%");
            sb.AppendLine();

            sb.AppendLine("--- FINANCE DATA ---");
            if (data.HasLedgerData)
            {
                sb.AppendLine($"Net Worth: {data.NetWorth:C0}");
                StringBuilder stocksBuilder = new StringBuilder();
                var limitStocks = data.WatchlistStocks.Take(StockCount).ToList();
                foreach (var stock in limitStocks)
                {
                    stocksBuilder.Append($"{stock.Symbol}: {stock.Price:F2} ({stock.FormattedChange}), ");
                }
                if (data.WatchlistStocks.Count > StockCount)
                {
                    stocksBuilder.Append($"... and {data.WatchlistStocks.Count - StockCount} more stocks");
                }
                string watchlistDetails = stocksBuilder.Length > 0 ? stocksBuilder.ToString().TrimEnd(',', ' ', '.') : "None";
                sb.AppendLine($"Watchlist stocks info: {watchlistDetails}");
            }
            else
            {
                sb.AppendLine("Ledger status: UNINITIALIZED (No accounts or transactions logged yet. Do not mention a $0 net worth; suggest setting up their ledger or adding their first account/transaction instead)");
            }
            sb.AppendLine();

            sb.AppendLine("--- HABITS DATA ---");
            sb.AppendLine($"Water target: {data.HabitsWaterGoal:F0} ml, Drank today: {data.HabitsWaterProgress:F0} ml");
            if (data.HabitsSmokesGoal > 0 || data.HabitsSmokesProgress > 0)
            {
                sb.AppendLine($"Cigarettes limit/baseline: {data.HabitsSmokesGoal:F0} today, Smoked today: {data.HabitsSmokesProgress:F0}");
            }
            sb.AppendLine();

            if (IncludeBehaviorTelemetry && !string.IsNullOrEmpty(behaviorSummary) && !behaviorSummary.Contains("No behavior events"))
            {
                sb.AppendLine("--- RECENT USER BEHAVIOR TELEMETRY (Last 7 Days) ---");
                sb.AppendLine(behaviorSummary.TrimEnd());
            }

            return sb.ToString();
        }

        public static int EstimateTokens(string systemPrompt, string userPrompt)
        {
            // Heuristic: 1 token = ~3.8 characters in English
            int totalLength = systemPrompt.Length + userPrompt.Length;
            return (int)Math.Ceiling(totalLength / 3.8);
        }
    }
}
