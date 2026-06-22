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
            public string action { get; set; } = string.Empty; // e.g. "transfer"
            public string source { get; set; } = string.Empty; // e.g. "Card", "Cash"
            public string target { get; set; } = string.Empty; // e.g. "Mega", "Gaz"
            public decimal amount { get; set; }
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

                    // Match the primary value assigned (e.g. "Card = 108" -> captures 108)
                    var match = Regex.Match(mathPart, @"=\s*([\-\d\.\,]+)");
                    if (match.Success)
                    {
                        var valStr = match.Groups[1].Value.Replace(',', '.'); // standardize decimal separator
                        if (decimal.TryParse(valStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal currentVal))
                        {
                            var newVal = currentVal + amountDelta;
                            // Re-format to avoid too many decimal places
                            string newStr = newVal % 1 == 0 ? newVal.ToString("F0") : newVal.ToString("G");
                            mathPart = Regex.Replace(mathPart, @"=\s*[\-\d\.\,]+", $"= {newStr}");
                            lines[i] = mathPart + commentPart;
                            break;
                        }
                    }
                }
            }
            
            return string.Join(Environment.NewLine, lines);
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

                    var match = Regex.Match(mathPart, @"=\s*([\-\d\.\,]+)");
                    if (match.Success)
                    {
                        var valStr = match.Groups[1].Value.Replace(',', '.');
                        if (decimal.TryParse(valStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal val))
                        {
                            currentSectionSum += val;
                        }
                    }
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

                    var match = Regex.Match(mathPart, @"=\s*([\-\d\.\,]+)");
                    if (match.Success)
                    {
                        var valStr = match.Groups[1].Value.Replace(',', '.');
                        if (decimal.TryParse(valStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal val))
                        {
                            return val;
                        }
                    }
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
            
            // Assuming INT is Investments and BIA is deposit/investments in **Deposit** section.
            // For simplicity based on the DSL:
            decimal investments = 0;
            bool inDeposit = false;
            foreach (var line in lines)
            {
                if (line.Trim() == "**Deposit**") inDeposit = true;
                else if (line.Trim().StartsWith("**") && line.Trim() != "**Deposit**") inDeposit = false;

                if (inDeposit && line.StartsWith("INT ="))
                {
                    int commentIdx = line.IndexOf("//");
                    string mathPart = commentIdx >= 0 ? line.Substring(0, commentIdx) : line;

                    // Match INT = 139.604,51
                    var match = Regex.Match(mathPart, @"=\s*([\-\d\.]+,\d+)");
                    if (match.Success)
                    {
                        // Parse romanian number format: 139.604,51 -> 139604.51
                        var valStr = match.Groups[1].Value.Replace(".", "").Replace(",", ".");
                        if (decimal.TryParse(valStr, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out decimal val))
                        {
                            investments += val;
                        }
                    }
                }
            }

            decimal nw = cash + investments;

            return (nw.ToString("N0") + " RON", cash.ToString("N0") + " RON", investments.ToString("N0") + " RON");
        }
    }
}
