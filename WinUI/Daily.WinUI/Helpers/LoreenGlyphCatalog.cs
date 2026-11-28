using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Daily_WinUI.Helpers;

public readonly record struct LoreenPoint(double X, double Y);

public enum LoreenGlyphOrigin
{
    Original,
    Completed
}

public sealed record LoreenGlyphDefinition(
    char Id,
    LoreenGlyphOrigin Origin,
    string Family,
    string Summary,
    IReadOnlyList<IReadOnlyList<LoreenPoint>> Strokes
);

public static class LoreenGlyphCatalog
{
    public static string NormalizeChallengeWord(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return string.Empty;
        var sb = new StringBuilder();
        foreach (char ch in raw.ToUpperInvariant())
        {
            switch (ch)
            {
                case 'Ă': case 'Â': case 'Á': case 'À': case 'Ä': case 'Å': sb.Append('A'); break;
                case 'Î': case 'Í': case 'Ì': case 'Ï': sb.Append('I'); break;
                case 'Ș': case 'Ş': sb.Append('S'); break;
                case 'Ț': case 'Ţ': sb.Append('T'); break;
                case 'É': case 'È': case 'Ê': case 'Ë': sb.Append('E'); break;
                case 'Ó': case 'Ò': case 'Ô': case 'Ö': sb.Append('O'); break;
                case 'Ú': case 'Ù': case 'Û': case 'Ü': sb.Append('U'); break;
                case 'Ñ': sb.Append('N'); break;
                case 'Ç': sb.Append('C'); break;
                default:
                    if (ch >= 'A' && ch <= 'Z') sb.Append(ch);
                    break;
            }
        }
        return sb.ToString();
    }

    public static string ChallengeWord(string? firstName)
    {
        if (string.IsNullOrWhiteSpace(firstName)) return "LOREEN";
        var normalized = NormalizeChallengeWord(firstName);
        if (normalized.Length < 2) return "LOREEN";
        return normalized.Length > 10 ? normalized[..10] : normalized;
    }

    private static LoreenPoint Pt(double sx, double sy) => new(sx / 100.0, sy / 120.0);

    private static List<LoreenPoint> Circle(double cx, double cy, double r, int steps = 24) =>
        Ellipse(cx, cy, r, r, steps);

    private static List<LoreenPoint> Ellipse(double cx, double cy, double rx, double ry, int steps = 24)
    {
        var pts = new List<LoreenPoint>(steps + 1);
        for (int k = 0; k <= steps; k++)
        {
            double a = (2.0 * Math.PI * k) / steps;
            pts.Add(Pt(cx + rx * Math.Cos(a), cy + ry * Math.Sin(a)));
        }
        return pts;
    }

    private static List<LoreenPoint> Line(double x1, double y1, double x2, double y2, int steps = 8)
    {
        var pts = new List<LoreenPoint>(steps + 1);
        for (int k = 0; k <= steps; k++)
        {
            double t = (double)k / steps;
            pts.Add(Pt(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t));
        }
        return pts;
    }

    private static List<LoreenPoint> Cubic(
        (double X, double Y) p0,
        (double X, double Y) p1,
        (double X, double Y) p2,
        (double X, double Y) p3,
        int steps = 14)
    {
        var pts = new List<LoreenPoint>(steps + 1);
        for (int k = 0; k <= steps; k++)
        {
            double t = (double)k / steps;
            double mt = 1.0 - t;
            double x = mt * mt * mt * p0.X + 3 * mt * mt * t * p1.X + 3 * mt * t * t * p2.X + t * t * t * p3.X;
            double y = mt * mt * mt * p0.Y + 3 * mt * mt * t * p1.Y + 3 * mt * t * t * p2.Y + t * t * t * p3.Y;
            pts.Add(Pt(x, y));
        }
        return pts;
    }

    private static List<LoreenPoint> Concat(params List<LoreenPoint>[] segments)
    {
        var res = new List<LoreenPoint>();
        foreach (var seg in segments) res.AddRange(seg);
        return res;
    }

    private static List<LoreenPoint> Arch(bool topSweep)
    {
        if (topSweep)
        {
            var pts = Line(20, 98, 20, 52, 6);
            for (int k = 1; k <= 15; k++)
            {
                double a = Math.PI + (Math.PI * k) / 16.0;
                pts.Add(Pt(50.0 + 30.0 * Math.Cos(a), 52.0 + 30.0 * Math.Sin(a)));
            }
            pts.AddRange(Line(80, 52, 80, 98, 6));
            return pts;
        }
        else
        {
            var pts = Line(22, 22, 22, 34, 3);
            for (int k = 1; k <= 15; k++)
            {
                double a = Math.PI - (Math.PI * k) / 16.0;
                pts.Add(Pt(50.0 + 28.0 * Math.Cos(a), 34.0 + 28.0 * Math.Sin(a)));
            }
            pts.AddRange(Line(78, 34, 78, 22, 3));
            return pts;
        }
    }

    public static IReadOnlyList<LoreenGlyphDefinition> AllGlyphs { get; } = new List<LoreenGlyphDefinition>
    {
        new('A', LoreenGlyphOrigin.Original, "Radial (Vowel)",
            "Empty circle — root of the radial vowel family",
            new[] { Circle(50, 60, 38) }),
        new('B', LoreenGlyphOrigin.Original, "Disguised Latin",
            "Fluid 2-curve loop",
            new[] { Concat(
                Line(24, 24, 62, 24, 5),
                Cubic((62, 24), (82, 24), (84, 52), (56, 58), 10),
                Line(56, 58, 42, 62, 3),
                Cubic((42, 62), (16, 68), (18, 96), (38, 96), 10),
                Line(38, 96, 78, 96, 5)) }),
        new('C', LoreenGlyphOrigin.Original, "Bars & Rungs",
            "Open twin-pillar frame (0 rungs)",
            new[] { Line(20, 22, 80, 22), Line(20, 98, 80, 98), Line(37, 22, 37, 98), Line(63, 22, 63, 98) }),
        new('D', LoreenGlyphOrigin.Original, "Bars & Rungs",
            "Closed ladder frame with 3 rungs",
            new[] {
                Concat(Line(24, 22, 76, 22), Line(76, 22, 76, 98), Line(76, 98, 24, 98), Line(24, 98, 24, 22)),
                Line(24, 41, 76, 41), Line(24, 60, 76, 60), Line(24, 79, 76, 79)
            }),
        new('E', LoreenGlyphOrigin.Original, "Radial (Vowel)",
            "Circle enclosing a 4-way cross",
            new[] { Circle(50, 60, 38), Line(12, 60, 88, 60), Line(50, 22, 50, 98) }),
        new('F', LoreenGlyphOrigin.Original, "Recalled (PDF)",
            "Inverted triangle bisected by a full cross",
            new[] {
                Concat(Line(18, 22, 82, 22), Line(82, 22, 50, 96), Line(50, 96, 18, 22)),
                Line(50, 22, 50, 98), Line(24, 58, 76, 58)
            }),
        new('G', LoreenGlyphOrigin.Completed, "Radial",
            "Circle enclosing a diagonal X cross",
            new[] { Circle(50, 60, 38), Line(23.1, 33.1, 76.9, 86.9), Line(76.9, 33.1, 23.1, 86.9) }),
        new('H', LoreenGlyphOrigin.Completed, "Radial",
            "Two full-height adjacent touching loops (infinity)",
            new[] { Ellipse(26.5, 60, 23.5, 38, 20), Ellipse(73.5, 60, 23.5, 38, 20) }),
        new('I', LoreenGlyphOrigin.Original, "Radial / Cross",
            "Bare Latin cross",
            new[] { Line(50, 22, 50, 98), Line(28, 46, 72, 46) }),
        new('J', LoreenGlyphOrigin.Original, "Architectural",
            "Vertical spine with top-left & bottom-right flags",
            new[] {
                Concat(Line(20, 22, 50, 22), Line(50, 22, 50, 40), Line(50, 40, 20, 40), Line(20, 40, 20, 22)),
                Line(50, 40, 50, 80),
                Concat(Line(50, 80, 80, 80), Line(80, 80, 80, 98), Line(80, 98, 50, 98), Line(50, 98, 50, 80))
            }),
        new('K', LoreenGlyphOrigin.Completed, "Architectural",
            "Inverted L — wide top block with descending stem",
            new[] {
                Concat(Line(16, 22, 84, 22), Line(84, 22, 84, 48), Line(84, 48, 16, 48), Line(16, 48, 16, 22)),
                Concat(Line(40, 48, 40, 98), Line(40, 98, 60, 98), Line(60, 98, 60, 48))
            }),
        new('L', LoreenGlyphOrigin.Original, "Architectural",
            "Pedestal / top-hat — wide base block with rising stem",
            new[] {
                Concat(Line(16, 72, 84, 72), Line(84, 72, 84, 98), Line(84, 98, 16, 98), Line(16, 98, 16, 72)),
                Concat(Line(40, 72, 40, 22), Line(40, 22, 60, 22), Line(60, 22, 60, 72))
            }),
        new('M', LoreenGlyphOrigin.Original, "Disguised Latin",
            "M with crossed inner legs",
            new[] { Concat(Line(16, 98, 34, 22), Line(34, 22, 62, 98)), Concat(Line(38, 98, 66, 22), Line(66, 22, 84, 98)) }),
        new('N', LoreenGlyphOrigin.Original, "Symmetric",
            "Opposing arches meeting at the center",
            new[] {
                Concat(Cubic((20, 22), (20, 56), (36, 60), (50, 60), 8), Cubic((50, 60), (64, 60), (80, 56), (80, 22), 8)),
                Concat(Cubic((20, 98), (20, 64), (36, 60), (50, 60), 8), Cubic((50, 60), (64, 60), (80, 64), (80, 98), 8))
            }),
        new('O', LoreenGlyphOrigin.Original, "Radial (Vowel)",
            "Bare 8-ray star",
            new[] { Line(50, 22, 50, 98), Line(12, 60, 88, 60), Line(23.1, 33.1, 76.9, 86.9), Line(76.9, 33.1, 23.1, 86.9) }),
        new('P', LoreenGlyphOrigin.Completed, "Mirror Pair",
            "Horizontal mirror of R (triangle pointing left)",
            new[] { Line(22, 22, 22, 98), Line(78, 22, 78, 98), Concat(Line(78, 22, 22, 60), Line(22, 60, 78, 98)) }),
        new('Q', LoreenGlyphOrigin.Original, "Radial",
            "Circle enclosing an 8-ray star (A + O)",
            new[] { Circle(50, 60, 38), Line(50, 22, 50, 98), Line(12, 60, 88, 60), Line(23.1, 33.1, 76.9, 86.9), Line(76.9, 33.1, 23.1, 86.9) }),
        new('R', LoreenGlyphOrigin.Original, "Mirror Pair",
            "Triangle pointing right between vertical rails",
            new[] { Line(22, 22, 22, 98), Line(78, 22, 78, 98), Concat(Line(22, 22, 78, 60), Line(78, 60, 22, 98)) }),
        new('S', LoreenGlyphOrigin.Completed, "Hourglass",
            "Empty vertical hourglass",
            new[] { Concat(Line(20, 22, 80, 22), Line(80, 22, 20, 98), Line(20, 98, 80, 98), Line(80, 98, 20, 22)) }),
        new('T', LoreenGlyphOrigin.Completed, "Crosses",
            "Cross of Lorraine (paired with I)",
            new[] { Line(50, 22, 50, 98), Line(32, 42, 68, 42), Line(22, 62, 78, 62) }),
        new('U', LoreenGlyphOrigin.Original, "Arch & Bars",
            "Inverted open arch (0 crossbars)",
            new[] { Arch(topSweep: true) }),
        new('V', LoreenGlyphOrigin.Original, "Arch & Bars",
            "Inverted arch with 1 crossbar",
            new[] { Arch(topSweep: true), Line(20, 60, 80, 60) }),
        new('W', LoreenGlyphOrigin.Original, "Arch & Bars",
            "Inverted arch with 2 crossbars",
            new[] { Arch(topSweep: true), Line(20, 52, 80, 52), Line(20, 72, 80, 72) }),
        new('X', LoreenGlyphOrigin.Original, "Symmetric",
            "Curved vertical vesica with 4 flared ends",
            new[] {
                Cubic((20, 22), (80, 34), (80, 86), (20, 98), 14),
                Cubic((80, 22), (20, 34), (20, 86), (80, 98), 14)
            }),
        new('Y', LoreenGlyphOrigin.Completed, "Arch & Bars",
            "Chalice / trident with tall inner vertical stem",
            new[] { Arch(topSweep: false), Line(50, 30, 50, 98) }),
        new('Z', LoreenGlyphOrigin.Completed, "Hourglass",
            "90-degree rotation of S (empty horizontal bowtie)",
            new[] { Concat(Line(16, 22, 16, 98), Line(16, 98, 84, 22), Line(84, 22, 84, 98), Line(84, 98, 16, 22)) })
    };

    public static LoreenGlyphDefinition? Definition(char letter)
    {
        char up = char.ToUpperInvariant(letter);
        return AllGlyphs.FirstOrDefault(g => g.Id == up);
    }
}
