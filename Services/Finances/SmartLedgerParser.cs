using System;
using System.Text.RegularExpressions;
using System.Linq;
using System.Collections.Generic;
using Daily.Models.Finances;

namespace Daily.Services.Finances
{
    public class SmartLedgerParser
    {
        public static readonly string DefaultLedgerText = @"**Incoming**

---

Card = 151 (Rz/141/Ing/10/Rev/0/Mom/9/!!!!/9)

Cash = 9 (SG-1/A/3M)

---

Total = 160

---

**Outgoing**

Itp/Rvg/4.27//Ghs/Prk/Csc/Rca/1.27 = 0

V/N/Y/O/AI/M/W/E/I/Ap/Am/Sy/Ad/Sp = 9

Rata/Rds/Gaz/Înt/Hid/(45)/Mom/(4) = 49

Cora/Mega/Bringo/Fresh (Edn/3) = 10

Tigari (40/45) = 10

Car/Benzina/Honda (1/4) = 3 (SPL!/CER?)

Serviciu/(0/*100)/Outs/(0*200) = 0

Acasa/Tuns/Cadouri = 10 (M&T=5/!!!!!/5)

Vacante/Noi/Iesiri/Other = 68 (C$40/B$20)

Subs (APL-21.01-$5/RED-14.03-$1/CSP-29.05-$5)(PRL-11.08-$6/365-25.08-$7/NSK-29.8-$2)(MRG-31.8-$2/STRS-22.09-$1)(EMG-13.12-$1) = 1

---

Total = 160

---

**Balance** 

---

Total = 0

---

**Dentist**

---

(Total = 106)

---

**Deposit**

---

ECO/ME! = 44.000L(//~8.400€)

ECO/B!A = 30.000L(//~5.600€)

EUR = 0€

ERO = 0€

DEP = 0

BIA = 0€

---

INT = 53.156,47 (-IMP-VER)//(~10.200€)

---

(Concediu = 14/23 (SEE/+5!))

---

(Chirie x7y ~ 37.000€ // Plati x7y ~ 9.000€)

(Mașini x8y~(x7-27.000€)+(x8+-27.000€)$";

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
            var updated = RecalculateTotalsInLines(lines);
            return string.Join("\n", updated);
        }

        public static string[] RecalculateTotalsInLines(string[] lines)
        {
            var updated = (string[])lines.Clone();
            string currentSection = "";
            decimal incomingSum = 0m;
            decimal outgoingSum = 0m;

            int incomingTotalLineIndex = -1;
            int outgoingTotalLineIndex = -1;
            int balanceTotalLineIndex = -1;

            for (int idx = 0; idx < updated.Length; idx++)
            {
                string trimmed = updated[idx].Trim();
                if (trimmed.StartsWith("**") && trimmed.EndsWith("**") && trimmed.Length > 4)
                {
                    currentSection = trimmed.Substring(2, trimmed.Length - 4).Trim();
                    continue;
                }

                // Skip pure parenthesized notes like (Total = 106) or (Concediu = ...)
                if (trimmed.StartsWith("(") && trimmed.EndsWith(")"))
                {
                    continue;
                }

                int eqIdx = trimmed.IndexOf('=');
                if (eqIdx >= 0)
                {
                    string key = trimmed.Substring(0, eqIdx).Trim();
                    string valStr = trimmed.Substring(eqIdx + 1).Trim();

                    if (string.Equals(key, "Total", StringComparison.OrdinalIgnoreCase))
                    {
                        if (string.Equals(currentSection, "Incoming", StringComparison.OrdinalIgnoreCase))
                            incomingTotalLineIndex = idx;
                        else if (string.Equals(currentSection, "Outgoing", StringComparison.OrdinalIgnoreCase))
                            outgoingTotalLineIndex = idx;
                        else if (string.Equals(currentSection, "Balance", StringComparison.OrdinalIgnoreCase))
                            balanceTotalLineIndex = idx;
                        continue;
                    }

                    var parsed = ParseNumericDetailed(valStr, isScaled: false);
                    if (string.Equals(currentSection, "Incoming", StringComparison.OrdinalIgnoreCase))
                        incomingSum += parsed.Raw;
                    else if (string.Equals(currentSection, "Outgoing", StringComparison.OrdinalIgnoreCase))
                        outgoingSum += parsed.Raw;
                }
            }

            static string FormatTotalLine(string existingLine, decimal totalVal)
            {
                int commentIdx = existingLine.IndexOf("//", StringComparison.Ordinal);
                string commentSuffix = commentIdx >= 0 ? " " + existingLine.Substring(commentIdx).Trim() : "";
                string formatted = totalVal % 1 == 0
                    ? ((long)totalVal).ToString(System.Globalization.CultureInfo.InvariantCulture)
                    : totalVal.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
                return $"Total = {formatted}{commentSuffix}";
            }

            if (incomingTotalLineIndex >= 0)
            {
                updated[incomingTotalLineIndex] = FormatTotalLine(updated[incomingTotalLineIndex], incomingSum);
            }

            if (outgoingTotalLineIndex >= 0)
            {
                updated[outgoingTotalLineIndex] = FormatTotalLine(updated[outgoingTotalLineIndex], outgoingSum);
            }

            if (balanceTotalLineIndex >= 0)
            {
                decimal bal = incomingSum - outgoingSum;
                updated[balanceTotalLineIndex] = FormatTotalLine(updated[balanceTotalLineIndex], bal);
            }

            return updated;
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
                    string cleanKey = CleanKeyName(keyPart);

                    var item = new SmartLedgerItem
                    {
                        SectionName = currentSectionName,
                        LineIndex = lineIndex,
                        RawLine = rawLine,
                        Key = cleanKey,
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

        private static string CleanKeyName(string key)
        {
            var k = key.Trim();
            k = Regex.Replace(k, @"\(.*?\)", "").Trim();
            while (k.EndsWith("/"))
            {
                k = k.Substring(0, k.Length - 1).Trim();
            }
            return k;
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
            int eqIdx = line.IndexOf('=');
            if (eqIdx < 0) return text;

            string valuePart = line.Substring(eqIdx + 1).Trim();
            var parsed = ParseNumericDetailed(valuePart, isScaled: false);
            decimal newRaw = Math.Max(0m, parsed.Raw + deltaRaw);
            return SetItemAmount(text, lineIndex, newRaw);
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

            string oldLine = lines[lineIndex];
            int eqIdx = oldLine.IndexOf('=');
            if (eqIdx < 0) return text;

            string keyPart = oldLine.Substring(0, eqIdx + 1).TrimEnd(); // e.g. "Card =" or "ECO/ME! ="
            string afterEq = oldLine.Substring(eqIdx + 1);

            // Find where notes '(' or comments '//' begin after '='
            int noteOrCommentIdx = afterEq.Length;
            int parenIdx = afterEq.IndexOf('(');
            if (parenIdx >= 0)
            {
                noteOrCommentIdx = Math.Min(noteOrCommentIdx, parenIdx);
            }
            int slashIdx = afterEq.IndexOf("//", StringComparison.Ordinal);
            if (slashIdx >= 0)
            {
                noteOrCommentIdx = Math.Min(noteOrCommentIdx, slashIdx);
            }

            string numRegion = afterEq.Substring(0, noteOrCommentIdx);
            string restOfLine = afterEq.Substring(noteOrCommentIdx);

            // Preserve currency / units suffix if present in numRegion
            string suffix = "";
            if (numRegion.Contains("€"))
                suffix = "€";
            else if (numRegion.IndexOf("EUR", StringComparison.OrdinalIgnoreCase) >= 0)
                suffix = " EUR";
            else if (numRegion.Contains("L"))
                suffix = "L";
            else if (numRegion.Contains("$"))
                suffix = "$";

            string formattedNum = FormatNumberForDsl(Math.Max(0m, newRaw), numRegion);
            string spaceBeforeRest = string.IsNullOrEmpty(restOfLine) || restOfLine.StartsWith(" ") || restOfLine.StartsWith("(") && suffix == "L"
                ? ""
                : " ";

            lines[lineIndex] = $"{keyPart} {formattedNum}{suffix}{spaceBeforeRest}{restOfLine}".TrimEnd();
            var recalculated = RecalculateTotalsInLines(lines);
            return string.Join("\n", recalculated);
        }

        public static string UpdateItemAmountAndNote(string text, int lineIndex, decimal newRaw, string? updatedNote, string originalNotesJoined)
        {
            string updatedText = SetItemAmount(text, lineIndex, newRaw);
            var trimmedNew = (updatedNote ?? string.Empty).Trim();
            var trimmedOrig = (originalNotesJoined ?? string.Empty).Trim();
            if (string.Equals(trimmedNew, trimmedOrig, StringComparison.Ordinal))
            {
                return updatedText;
            }

            var lines = updatedText.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);
            if (lineIndex < 0 || lineIndex >= lines.Length) return updatedText;

            string line = lines[lineIndex];
            int eqIdx = line.IndexOf('=');
            if (eqIdx < 0) return updatedText;

            string keyPart = line.Substring(0, eqIdx + 1).TrimEnd();
            string afterEq = line.Substring(eqIdx + 1);

            // Preserve any '//' trailing comment outside parentheses while replacing trailing '(...)' note after '='
            string trailingSlashComment = "";
            string withoutParenAfterEq = Regex.Replace(afterEq, @"\s*\([^)]*\)", "").Trim();
            int slashIdx = withoutParenAfterEq.IndexOf("//", StringComparison.Ordinal);
            if (slashIdx >= 0)
            {
                trailingSlashComment = " " + withoutParenAfterEq.Substring(slashIdx).Trim();
                withoutParenAfterEq = withoutParenAfterEq.Substring(0, slashIdx).Trim();
            }

            string noteSegment = string.IsNullOrWhiteSpace(trimmedNew) ? "" : $" ({trimmedNew})";
            lines[lineIndex] = $"{keyPart} {withoutParenAfterEq}{noteSegment}{trailingSlashComment}".TrimEnd();
            return string.Join("\n", RecalculateTotalsInLines(lines));
        }

        private static string FormatNumberForDsl(decimal value, string originalNumRegion)
        {
            var roCulture = (System.Globalization.NumberFormatInfo)System.Globalization.CultureInfo.InvariantCulture.NumberFormat.Clone();
            roCulture.NumberGroupSeparator = ".";
            roCulture.NumberDecimalSeparator = ",";

            if (originalNumRegion.Contains(','))
            {
                return value % 1 == 0
                    ? value.ToString("#,0", roCulture)
                    : value.ToString("#,0.00", roCulture);
            }

            if (originalNumRegion.Contains('.'))
            {
                // Check if original used '.' as European thousands separator (e.g. 44.000)
                var digitsAndDots = Regex.Match(originalNumRegion, @"[\d\.]+").Value;
                var dotParts = digitsAndDots.Split('.');
                if (dotParts.Length == 2 && dotParts[1].Length == 3 && value >= 1000m && value % 1 == 0)
                {
                    return value.ToString("#,0", roCulture);
                }
            }

            return value % 1 == 0
                ? ((long)value).ToString(System.Globalization.CultureInfo.InvariantCulture)
                : value.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
        }

        public static string AddItem(string text, string sectionName, string key, decimal rawAmount, string currency, bool isScaled)
        {
            string suffix = string.Equals(currency, "EUR", StringComparison.OrdinalIgnoreCase) ? "€" : "";
            return AddItem(text, sectionName, key, rawAmount, note: null, currencySuffix: suffix);
        }

        public static string AddItem(string text, string sectionName, string key, decimal rawAmount, string? note = null, string currencySuffix = "")
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None).ToList();
            int sectionHeaderIndex = -1;

            for (int i = 0; i < lines.Count; i++)
            {
                string trimmed = lines[i].Trim();
                if (trimmed.StartsWith("**") && trimmed.EndsWith("**") && trimmed.Length > 4)
                {
                    string secName = trimmed.Substring(2, trimmed.Length - 4).Trim();
                    if (string.Equals(secName, sectionName, StringComparison.OrdinalIgnoreCase))
                    {
                        sectionHeaderIndex = i;
                        break;
                    }
                }
            }

            if (sectionHeaderIndex < 0)
            {
                return text;
            }

            int insertIndex = lines.Count;
            for (int idx = sectionHeaderIndex + 1; idx < lines.Count; idx++)
            {
                string trimmed = lines[idx].Trim();
                if (trimmed.StartsWith("**") && trimmed.EndsWith("**") && trimmed.Length > 4)
                {
                    insertIndex = idx;
                    break;
                }

                if (trimmed == "---" || trimmed == "- - -")
                {
                    bool isBeforeTotal = false;
                    int lookAheadMax = Math.Min(idx + 5, lines.Count);
                    for (int nextIdx = idx + 1; nextIdx < lookAheadMax; nextIdx++)
                    {
                        string nextTrimmed = lines[nextIdx].Trim();
                        if (nextTrimmed.StartsWith("Total =", StringComparison.OrdinalIgnoreCase) ||
                            nextTrimmed.StartsWith("Total=", StringComparison.OrdinalIgnoreCase) ||
                            nextTrimmed.StartsWith("(Total", StringComparison.OrdinalIgnoreCase))
                        {
                            isBeforeTotal = true;
                            break;
                        }
                    }

                    if (isBeforeTotal)
                    {
                        insertIndex = idx;
                        break;
                    }
                }
                else if (trimmed.StartsWith("Total =", StringComparison.OrdinalIgnoreCase) ||
                         trimmed.StartsWith("Total=", StringComparison.OrdinalIgnoreCase))
                {
                    insertIndex = idx;
                    break;
                }
            }

            string formattedNum = rawAmount % 1 == 0
                ? ((long)rawAmount).ToString(System.Globalization.CultureInfo.InvariantCulture)
                : rawAmount.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);

            string trimmedNote = (note ?? string.Empty).Trim();
            string notePart = string.IsNullOrEmpty(trimmedNote) ? "" : $" ({trimmedNote})";
            string newLine = $"{key.Trim()} = {formattedNum}{currencySuffix}{notePart}";

            lines.Insert(insertIndex, newLine);
            lines.Insert(insertIndex + 1, "");

            var updated = RecalculateTotalsInLines(lines.ToArray());
            return string.Join("\n", updated);
        }

        public static string DeleteItem(string text, int lineIndex)
        {
            var lines = text.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None).ToList();
            if (lineIndex >= 0 && lineIndex < lines.Count)
            {
                lines.RemoveAt(lineIndex);
                if (lineIndex < lines.Count && string.IsNullOrWhiteSpace(lines[lineIndex]))
                {
                    if (lineIndex - 1 >= 0 && string.IsNullOrWhiteSpace(lines[lineIndex - 1]))
                    {
                        lines.RemoveAt(lineIndex);
                    }
                }
            }
            var updated = RecalculateTotalsInLines(lines.ToArray());
            return string.Join("\n", updated);
        }
    }
}
