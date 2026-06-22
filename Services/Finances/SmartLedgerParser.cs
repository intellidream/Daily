using System;
using System.Text.RegularExpressions;
using System.Linq;
using System.Collections.Generic;

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

        // Extracts key header metrics (Net Worth, Cash, Investments) from the text directly
        public static (string NetWorth, string Cash, string Investments) ExtractHeaders(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return ("$0", "$0", "$0");

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

            return (nw.ToString("N0") + " RON", cash.ToString("N0") + " RON", investments.ToString("N0") + " RON");
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
    }
}
