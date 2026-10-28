using System;
using System.Text.RegularExpressions;
using System.Linq;
using System.Collections.Generic;
using Daily.Models.Finances;

namespace Daily.Services.Finances
{
    public class SmartLedgerParser
    {
        public class LedgerCommand
        {
            public string action { get; set; } = string.Empty; // e.g. "transfer", "schedule"
            public string source { get; set; } = string.Empty; // e.g. "Card", "Cash"
            public string target { get; set; } = string.Empty; // e.g. "Mega", "Gaz"
            public decimal amount { get; set; }
            public string? frequency { get; set; } // e.g. "daily", "weekly", "monthly"
        }

        public static string ExecuteCommand(string ledgerText, LedgerCommand command)
        {
            if (command.action?.ToLower() == "transfer")
            {
                // Subtract from source
                if (!string.IsNullOrEmpty(command.source))
                {
                    ledgerText = AdjustValue(ledgerText, command.source, -command.amount);
                }
                
                // Add to target
                if (!string.IsNullOrEmpty(command.target))
                {
                    ledgerText = AdjustValue(ledgerText, command.target, command.amount);
                }
            }
            
            return RecalculateTotals(ledgerText);
        }

        private static string AdjustValue(string text, string targetAbbreviation, decimal amountDelta)
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            
            for (int i = 0; i < lines.Length; i++)
            {
                var line = lines[i];
                if (line.Contains(targetAbbreviation, StringComparison.OrdinalIgnoreCase))
                {
                    // Split out the comment first
                    int commentIdx = line.IndexOf("//");
                    string mathPart = commentIdx >= 0 ? line.Substring(0, commentIdx) : line;
                    string commentPart = commentIdx >= 0 ? line.Substring(commentIdx) : "";

                    // Match the primary value assigned and capture everything after it as suffix
                    var match = Regex.Match(mathPart, @"=\s*([\-\d\.\,]+)(.*)");
                    if (match.Success)
                    {
                        var valStr = match.Groups[1].Value.Replace(',', '.'); // standardize decimal separator
                        var suffix = match.Groups.Count > 2 ? match.Groups[2].Value : "";

                        if (decimal.TryParse(valStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal currentVal))
                        {
                            var newVal = currentVal + amountDelta;
                            // Re-format to avoid too many decimal places
                            string newStr = newVal % 1 == 0 ? newVal.ToString("F0") : newVal.ToString("G");
                            
                            string replacement = $"= {newStr}{suffix}";
                            
                            // We replace the entire matched part, which is essentially the entire assignment portion
                            mathPart = Regex.Replace(mathPart, @"=\s*[\-\d\.\,]+.*", replacement);
                            lines[i] = mathPart + commentPart;
                            break;
                        }
                    }
                }
            }
            
            return string.Join(Environment.NewLine, lines);
        }

        public static decimal ParseValue(string mathPart)
        {
            // 1. Asset Tracking: Quantity @ Price (e.g., 10 @ 415.50 or 10 shares @ 415.50)
            var assetMatch = Regex.Match(mathPart, @"=\s*([\-\d\.\,]+)\s*(?:shares|units|@)?\s*@\s*([\-\d\.\,]+)", RegexOptions.IgnoreCase);
            if (assetMatch.Success)
            {
                var qtyStr = assetMatch.Groups[1].Value.Replace(',', '.');
                var priceStr = assetMatch.Groups[2].Value.Replace(',', '.');
                if (decimal.TryParse(qtyStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal qty) &&
                    decimal.TryParse(priceStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal price))
                {
                    return qty * price;
                }
            }

            // 2. Goal Yields / Targets: Current => Target (+APY%) OR Current / Target
            // We just need to extract the first number after =
            var match = Regex.Match(mathPart, @"=\s*([\-\d\.\,]+)");
            if (match.Success)
            {
                var valStr = match.Groups[1].Value.Replace(',', '.');
                if (decimal.TryParse(valStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal val))
                {
                    return val;
                }
            }

            return 0;
        }

        public static string RecalculateTotals(string ledgerText)
        {
            var lines = ledgerText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            
            decimal currentSectionSum = 0;
            bool inSection = false;

            // Recalculate all sections except Balance/Dentist/Deposit which are free-form or tracked differently
            for (int i = 0; i < lines.Length; i++)
            {
                var line = lines[i].Trim();
                
                if (line.StartsWith("**") && line.EndsWith("**"))
                {
                    if (line == "**Incoming**" || line == "**Outgoing**")
                    {
                        inSection = true;
                        currentSectionSum = 0;
                    }
                    else
                    {
                        inSection = false;
                    }
                    continue;
                }

                if (inSection && line.Contains("=") && !line.StartsWith("Total"))
                {
                    int commentIdx = line.IndexOf("//");
                    string mathPart = commentIdx >= 0 ? line.Substring(0, commentIdx) : line;

                    currentSectionSum += ParseValue(mathPart);
                }

                if (inSection && line.StartsWith("Total ="))
                {
                    int commentIdx = line.IndexOf("//");
                    string mathPart = commentIdx >= 0 ? line.Substring(0, commentIdx) : line;
                    string commentPart = commentIdx >= 0 ? line.Substring(commentIdx) : "";

                    string sumStr = currentSectionSum % 1 == 0 ? currentSectionSum.ToString("F0") : currentSectionSum.ToString("G");
                    lines[i] = $"Total = {sumStr} " + commentPart;
                    lines[i] = lines[i].TrimEnd();
                    inSection = false; 
                    currentSectionSum = 0;
                }
            }

            // Balance Calculation
            decimal incomingTotal = ExtractTotal(lines, "**Incoming**");
            decimal outgoingTotal = ExtractTotal(lines, "**Outgoing**");
            
            for (int i = 0; i < lines.Length; i++)
            {
                if (lines[i].Trim() == "**Balance**")
                {
                    for (int j = i + 1; j < lines.Length; j++)
                    {
                        if (lines[j].Trim().StartsWith("Total ="))
                        {
                            int commentIdx = lines[j].IndexOf("//");
                            string commentPart = commentIdx >= 0 ? lines[j].Substring(commentIdx) : "";

                            decimal diff = incomingTotal - outgoingTotal;
                            string sumStr = diff % 1 == 0 ? diff.ToString("F0") : diff.ToString("G");
                            lines[j] = $"Total = {sumStr} " + commentPart;
                            lines[j] = lines[j].TrimEnd();
                            break;
                        }
                    }
                    break;
                }
            }

            return string.Join(Environment.NewLine, lines);
        }

        public static decimal ExtractTotal(string[] lines, string sectionHeader)
        {
            bool inSection = false;
            foreach (var line in lines)
            {
                if (line.Trim() == sectionHeader) inSection = true;
                else if (line.Trim().StartsWith("**") && line.Trim().EndsWith("**") && line.Trim() != sectionHeader)
                {
                    inSection = false; // exited section
                }
                else if (inSection && line.Trim().StartsWith("Total ="))
                {
                    int commentIdx = line.IndexOf("//");
                    string mathPart = commentIdx >= 0 ? line.Substring(0, commentIdx) : line;

                    return ParseValue(mathPart);
                }
            }
            return 0;
        }

        // Extracts raw decimal values for charting
        public static (decimal NetWorth, decimal Cash, decimal Investments) ExtractHeaderValues(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return (0, 0, 0);

            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            
            decimal cash = ExtractTotal(lines, "**Incoming**");
            
            decimal investments = 0;
            bool inInvestments = false;
            foreach (var line in lines)
            {
                if (line.Trim() == "**Deposit**" || line.Trim() == "**Investments**") inInvestments = true;
                else if (line.Trim().StartsWith("**") && line.Trim() != "**Deposit**" && line.Trim() != "**Investments**") inInvestments = false;

                if (inInvestments && line.Contains("=") && !line.StartsWith("Total"))
                {
                    int commentIdx = line.IndexOf("//");
                    string mathPart = commentIdx >= 0 ? line.Substring(0, commentIdx) : line;

                    investments += ParseValue(mathPart);
                }
            }

            decimal nw = cash + investments;
            return (nw, cash, investments);
        }

        // Extracts key header metrics formatted as strings
        public static (string NetWorth, string Cash, string Investments) ExtractHeaders(string text)
        {
            var values = ExtractHeaderValues(text);
            return (values.NetWorth.ToString("N0") + " RON", values.Cash.ToString("N0") + " RON", values.Investments.ToString("N0") + " RON");
        }

        public static List<Daily.Models.Finances.AccountBalance> ExtractBalances(string text)
        {
            var results = new List<Daily.Models.Finances.AccountBalance>();
            if (string.IsNullOrWhiteSpace(text)) return results;

            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            
            string currentSection = "";
            foreach (var line in lines)
            {
                var trimmed = line.Trim();
                if (trimmed.StartsWith("**") && trimmed.EndsWith("**"))
                {
                    currentSection = trimmed.Replace("*", "");
                    continue;
                }

                if (string.IsNullOrEmpty(currentSection)) continue;
                if (!trimmed.Contains("=") || trimmed.StartsWith("Total =") || trimmed.StartsWith("INT =") || trimmed.StartsWith("BIA =")) continue;

                int eqIdx = trimmed.IndexOf("=");
                if (eqIdx > 0)
                {
                    string accountName = trimmed.Substring(0, eqIdx).Trim();
                    
                    int commentIdx = trimmed.IndexOf("//");
                    string mathPart = commentIdx >= 0 ? trimmed.Substring(0, commentIdx) : trimmed;
                    
                    decimal balance = ParseValue(mathPart);
                    
                    if (balance > 0)
                    {
                        results.Add(new Daily.Models.Finances.AccountBalance
                        {
                            Category = currentSection,
                            AccountName = accountName,
                            Balance = balance
                        });
                    }
                }
            }

            return results;
        }

        public static Dictionary<string, string> ExtractTags(string commentPart)
        {
            var tags = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            
            if (string.IsNullOrWhiteSpace(commentPart))
                return tags;

            // Matches #tag or #key:value
            var matches = Regex.Matches(commentPart, @"#([a-zA-Z0-9_]+)(?::([^\s]+))?");
            foreach (Match match in matches)
            {
                var key = match.Groups[1].Value;
                var val = match.Groups.Count > 2 && match.Groups[2].Success ? match.Groups[2].Value : "true";
                tags[key] = val;
            }

            return tags;
        }

        // ==========================================
        // COMPREHENSIVE AST PARSER & MUTATION ENGINE
        // ==========================================

        public static ParsedSmartLedger Parse(string text, decimal eurRate = 5.0m)
        {
            var sections = new List<SmartLedgerSection>();
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);

            string currentSectionName = "Overview";
            var currentItems = new List<SmartLedgerItem>();
            bool currentSectionScaled = true;
            decimal? currentSectionExplicitTotal = null;
            decimal? currentSectionRawTotal = null;
            bool hasEncounteredDeposit = false;

            void FinishCurrentSection()
            {
                if (!currentItems.Any() && currentSectionExplicitTotal == null) return;

                decimal itemsCalculatedSum = currentItems.Where(x => !x.IsPureNote).Sum(x => x.CalculatedAmount);
                decimal itemsRawSum = currentItems.Where(x => !x.IsPureNote).Sum(x => x.RawAmount);

                decimal finalCalculatedTotal = currentSectionExplicitTotal ?? itemsCalculatedSum;
                decimal finalRawTotal = currentSectionRawTotal ?? itemsRawSum;

                if (finalCalculatedTotal > 0)
                {
                    foreach (var it in currentItems)
                    {
                        if (!it.IsPureNote)
                        {
                            it.PercentageOfSection = it.CalculatedAmount / finalCalculatedTotal;
                        }
                    }
                }

                var sec = new SmartLedgerSection
                {
                    Name = currentSectionName,
                    Items = new List<SmartLedgerItem>(currentItems),
                    TotalCalculated = finalCalculatedTotal,
                    TotalRaw = finalRawTotal,
                    IsScaled = currentSectionScaled
                };
                sections.Add(sec);

                currentItems.Clear();
                currentSectionExplicitTotal = null;
                currentSectionRawTotal = null;
            }

            for (int lineIndex = 0; lineIndex < lines.Length; lineIndex++)
            {
                string rawLine = lines[lineIndex];
                string line = rawLine.Trim();

                if (string.IsNullOrEmpty(line) || line == "---" || line == "- - -")
                {
                    continue;
                }

                if (line.StartsWith("**") && line.EndsWith("**") && line.Length > 4)
                {
                    FinishCurrentSection();
                    string secName = line.Substring(2, line.Length - 4).Trim();
                    currentSectionName = secName;

                    if (string.Equals(secName, "Deposit", StringComparison.OrdinalIgnoreCase))
                    {
                        hasEncounteredDeposit = true;
                    }

                    currentSectionScaled = !hasEncounteredDeposit;
                    continue;
                }

                if (line.StartsWith("(") && line.EndsWith(")"))
                {
                    string inner = line.Substring(1, line.Length - 2).Trim();
                    if (inner.StartsWith("Total =", StringComparison.OrdinalIgnoreCase) || inner.StartsWith("Total=", StringComparison.OrdinalIgnoreCase))
                    {
                        var parts = inner.Split('=');
                        if (parts.Length >= 2)
                        {
                            var parsedVal = ParseNumericDetailed(parts[1], currentSectionScaled, eurRate);
                            currentSectionExplicitTotal = parsedVal.Calculated;
                            currentSectionRawTotal = parsedVal.Raw;
                        }
                        continue;
                    }
                    else
                    {
                        var item = new SmartLedgerItem
                        {
                            SectionName = currentSectionName,
                            LineIndex = lineIndex,
                            RawLine = rawLine,
                            Key = inner,
                            RawAmount = 0,
                            CalculatedAmount = 0,
                            Currency = "Lei",
                            IsScaled = currentSectionScaled,
                            Notes = new List<string> { inner },
                            IsPureNote = true
                        };
                        currentItems.Add(item);
                        continue;
                    }
                }

                if (line.Contains("="))
                {
                    int eqIdx = line.IndexOf("=");
                    string keyPart = line.Substring(0, eqIdx).Trim();
                    string valuePart = line.Substring(eqIdx + 1).Trim();

                    if (string.Equals(keyPart, "Total", StringComparison.OrdinalIgnoreCase))
                    {
                        var parsedVal = ParseNumericDetailed(valuePart, currentSectionScaled, eurRate);
                        currentSectionExplicitTotal = parsedVal.Calculated;
                        currentSectionRawTotal = parsedVal.Raw;
                        continue;
                    }

                    var notes = ExtractParentheses(line);
                    var parsedNum = ParseNumericDetailed(valuePart, currentSectionScaled, eurRate);

                    var item = new SmartLedgerItem
                    {
                        SectionName = currentSectionName,
                        LineIndex = lineIndex,
                        RawLine = rawLine,
                        Key = keyPart,
                        RawAmount = parsedNum.Raw,
                        CalculatedAmount = parsedNum.Calculated,
                        Currency = parsedNum.IsEUR ? "EUR" : "Lei",
                        IsScaled = currentSectionScaled,
                        Notes = notes,
                        IsPureNote = false
                    };
                    currentItems.Add(item);
                }
                else
                {
                    var item = new SmartLedgerItem
                    {
                        SectionName = currentSectionName,
                        LineIndex = lineIndex,
                        RawLine = rawLine,
                        Key = line,
                        RawAmount = 0,
                        CalculatedAmount = 0,
                        Currency = "Lei",
                        IsScaled = currentSectionScaled,
                        Notes = new List<string> { line },
                        IsPureNote = true
                    };
                    currentItems.Add(item);
                }
            }

            FinishCurrentSection();

            var incomingSec = sections.FirstOrDefault(x => string.Equals(x.Name, "Incoming", StringComparison.OrdinalIgnoreCase));
            var outgoingSec = sections.FirstOrDefault(x => string.Equals(x.Name, "Outgoing", StringComparison.OrdinalIgnoreCase));
            var balanceSec = sections.FirstOrDefault(x => string.Equals(x.Name, "Balance", StringComparison.OrdinalIgnoreCase));
            var dentistSec = sections.FirstOrDefault(x => string.Equals(x.Name, "Dentist", StringComparison.OrdinalIgnoreCase));
            var depositSec = sections.FirstOrDefault(x => string.Equals(x.Name, "Deposit", StringComparison.OrdinalIgnoreCase));

            decimal inTotal = incomingSec?.TotalCalculated ?? 0m;
            decimal outTotal = outgoingSec?.TotalCalculated ?? 0m;
            decimal balTotal = balanceSec?.TotalCalculated ?? Math.Max(0, inTotal - outTotal);
            decimal dentTotal = dentistSec?.TotalCalculated ?? 0m;
            decimal depTotal = depositSec?.TotalCalculated ?? 0m;

            decimal nw = depTotal + balTotal;
            decimal nwEUR = eurRate > 0 ? nw / eurRate : 0m;

            return new ParsedSmartLedger
            {
                Sections = sections,
                IncomingTotal = inTotal,
                OutgoingTotal = outTotal,
                BalanceTotal = balTotal,
                DentistTotal = dentTotal,
                DepositTotal = depTotal,
                NetWorth = nw,
                NetWorthEUR = nwEUR,
                RawText = text
            };
        }

        private static (decimal Raw, decimal Calculated, bool IsEUR) ParseNumericDetailed(string valStr, bool isScaled, decimal eurRate = 5.0m)
        {
            string clean = Regex.Replace(valStr, @"\(.*?\)", "").Trim();
            int commentIdx = clean.IndexOf("//");
            if (commentIdx >= 0)
            {
                clean = clean.Substring(0, commentIdx).Trim();
            }

            bool isEUR = clean.Contains("€") || clean.IndexOf("EUR", StringComparison.OrdinalIgnoreCase) >= 0;

            var unwantedChars = new[] { 'L', '€', '$', '~', '%', ' ' };
            foreach (var ch in unwantedChars)
            {
                clean = clean.Replace(ch.ToString(), "");
            }
            clean = Regex.Replace(clean, "EUR", "", RegexOptions.IgnoreCase).Trim();

            if (string.IsNullOrEmpty(clean)) return (0m, 0m, isEUR);

            string normalized = clean;
            if (normalized.Contains(","))
            {
                normalized = normalized.Replace(".", "").Replace(",", ".");
            }
            else if (normalized.Contains("."))
            {
                var parts = normalized.Split('.');
                if (parts.Length == 2 && parts[1].Length == 3)
                {
                    normalized = normalized.Replace(".", "");
                }
            }

            if (decimal.TryParse(normalized, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal num))
            {
                decimal baseCalc = isScaled ? num * 100m : num;
                decimal calc = isEUR ? baseCalc * eurRate : baseCalc;
                return (num, calc, isEUR);
            }

            return (0m, 0m, isEUR);
        }

        private static List<string> ExtractParentheses(string line)
        {
            var notes = new List<string>();
            var matches = Regex.Matches(line, @"\((.*?)\)");
            foreach (Match m in matches)
            {
                if (m.Groups.Count > 1)
                {
                    string content = m.Groups[1].Value.Trim();
                    if (!string.IsNullOrEmpty(content))
                    {
                        notes.Add(content);
                    }
                }
            }
            return notes;
        }

        public static string AdjustItemAmount(string text, SmartLedgerItem item, decimal deltaRaw)
        {
            if (item == null) return text;
            return AdjustItemAmount(text, item.LineIndex, deltaRaw);
        }

        public static string AdjustItemAmount(string text, int lineIndex, decimal deltaRaw)
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            if (lineIndex < 0 || lineIndex >= lines.Length) return text;

            string line = lines[lineIndex];
            int eqIdx = line.IndexOf("=");
            if (eqIdx < 0) return text;

            string keyPart = line.Substring(0, eqIdx + 1);
            string remainder = line.Substring(eqIdx + 1).Trim();

            int commentIdx = remainder.IndexOf("//");
            string mathPart = commentIdx >= 0 ? remainder.Substring(0, commentIdx) : remainder;
            string commentPart = commentIdx >= 0 ? remainder.Substring(commentIdx) : "";

            var match = Regex.Match(mathPart, @"^\s*([\-\d\.\,]+)(.*)");
            if (match.Success)
            {
                string numStr = match.Groups[1].Value.Replace(',', '.');
                string suffix = match.Groups.Count > 2 ? match.Groups[2].Value : "";

                if (decimal.TryParse(numStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal currentVal))
                {
                    decimal newVal = currentVal + deltaRaw;
                    string formattedNum = newVal % 1 == 0 ? newVal.ToString("F0") : newVal.ToString("G");
                    lines[lineIndex] = $"{keyPart} {formattedNum}{suffix} {commentPart}".TrimEnd();
                }
            }

            return RecalculateTotals(string.Join(Environment.NewLine, lines));
        }

        public static string SetItemAmount(string text, SmartLedgerItem item, decimal newRaw)
        {
            if (item == null) return text;
            return SetItemAmount(text, item.LineIndex, newRaw);
        }

        public static string SetItemAmount(string text, int lineIndex, decimal newRaw)
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            if (lineIndex < 0 || lineIndex >= lines.Length) return text;

            string line = lines[lineIndex];
            int eqIdx = line.IndexOf("=");
            if (eqIdx < 0) return text;

            string keyPart = line.Substring(0, eqIdx + 1);
            string remainder = line.Substring(eqIdx + 1).Trim();

            int commentIdx = remainder.IndexOf("//");
            string mathPart = commentIdx >= 0 ? remainder.Substring(0, commentIdx) : remainder;
            string commentPart = commentIdx >= 0 ? remainder.Substring(commentIdx) : "";

            var match = Regex.Match(mathPart, @"^\s*([\-\d\.\,]+)(.*)");
            if (match.Success)
            {
                string suffix = match.Groups.Count > 2 ? match.Groups[2].Value : "";
                string formattedNum = newRaw % 1 == 0 ? newRaw.ToString("F0") : newRaw.ToString("G");
                lines[lineIndex] = $"{keyPart} {formattedNum}{suffix} {commentPart}".TrimEnd();
            }

            return RecalculateTotals(string.Join(Environment.NewLine, lines));
        }

        public static string AddItem(string text, string sectionName, string key, decimal rawAmount, string currency, bool isScaled)
        {
            string? note = isScaled ? "Scaled" : null;
            return AddItem(text, sectionName, key, rawAmount, note);
        }

        public static string AddItem(string text, string sectionName, string key, decimal rawAmount, string? note = null)
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None).ToList();
            int insertIndex = -1;
            bool insideTargetSection = false;

            for (int i = 0; i < lines.Count; i++)
            {
                string line = lines[i].Trim();
                if (line.StartsWith("**") && line.EndsWith("**"))
                {
                    string secName = line.Substring(2, line.Length - 4).Trim();
                    if (string.Equals(secName, sectionName, StringComparison.OrdinalIgnoreCase))
                    {
                        insideTargetSection = true;
                        continue;
                    }
                    else if (insideTargetSection)
                    {
                        insertIndex = i;
                        break;
                    }
                }

                if (insideTargetSection && line.StartsWith("Total =", StringComparison.OrdinalIgnoreCase))
                {
                    insertIndex = i;
                    break;
                }
            }

            if (insertIndex < 0)
            {
                insertIndex = lines.Count;
            }

            string formattedNum = rawAmount % 1 == 0 ? rawAmount.ToString("F0") : rawAmount.ToString("G");
            string newLine = string.IsNullOrWhiteSpace(note) 
                ? $"{key} = {formattedNum}" 
                : $"{key} = {formattedNum} ({note})";

            lines.Insert(insertIndex, newLine);
            lines.Insert(insertIndex + 1, "");

            return RecalculateTotals(string.Join(Environment.NewLine, lines));
        }

        public static string DeleteItem(string text, int lineIndex)
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None).ToList();
            if (lineIndex >= 0 && lineIndex < lines.Count)
            {
                lines.RemoveAt(lineIndex);
            }
            return RecalculateTotals(string.Join(Environment.NewLine, lines));
        }
    }
}
