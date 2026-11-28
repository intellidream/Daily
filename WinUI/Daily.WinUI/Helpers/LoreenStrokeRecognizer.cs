using System;
using System.Collections.Generic;
using System.Linq;

namespace Daily_WinUI.Helpers;

public sealed record LoreenRecognitionCandidate(char Letter, double Distance);

public sealed record LoreenRecognitionResult(
    char Letter,
    double Distance,
    IReadOnlyList<LoreenRecognitionCandidate> TopCandidates
);

/// <summary>
/// Offline $P Point-Cloud Multistroke Recognizer tuned for Loreen Script.
/// Stroke-order and direction invariant with geometric disambiguation guards for mirror/cross pairs.
/// </summary>
public static class LoreenStrokeRecognizer
{
    private const int SampleCount = 32;

    private sealed record NormalizedCloud(
        List<LoreenPoint> Points,
        double CentroidY,
        double AspectRatio,
        int HorizontalStrokeCount,
        int VerticalStrokeCount,
        int StrokeCount,
        double LeftMassFraction
    );

    private sealed record Template(char Letter, NormalizedCloud Cloud);

    private static readonly Lazy<List<Template>> _templates = new(() =>
        LoreenGlyphCatalog.AllGlyphs
            .Select(g => new Template(g.Id, Normalize(g.Strokes)))
            .ToList());

    public static LoreenRecognitionResult? Recognize(IReadOnlyList<IReadOnlyList<LoreenPoint>> strokes)
    {
        var validStrokes = strokes.Where(s => s.Count > 0).ToList();
        int totalRawPoints = validStrokes.Sum(s => s.Count);
        if (validStrokes.Count == 0 || totalRawPoints < 2) return null;

        var candidate = Normalize(validStrokes);
        var scored = _templates.Value
            .Select(t => new LoreenRecognitionCandidate(
                t.Letter,
                GreedyCloudMatch(candidate.Points, t.Cloud.Points) + DisambiguationPenalty(candidate, t.Letter)))
            .OrderBy(c => c.Distance)
            .ToList();

        if (scored.Count == 0) return null;
        return new LoreenRecognitionResult(scored[0].Letter, scored[0].Distance, scored.Take(4).ToList());
    }

    public static bool Matches(IReadOnlyList<IReadOnlyList<LoreenPoint>> strokes, char expected)
    {
        char target = char.ToUpperInvariant(expected);
        var result = Recognize(strokes);
        if (result == null) return false;

        var validStrokes = strokes.Where(s => s.Count > 0).ToList();
        double totalLen = validStrokes.Sum(PathLength);
        if (totalLen <= 0.18) return false;

        if (result.Letter == target)
        {
            return result.Distance < 0.42;
        }

        if (result.TopCandidates.Count >= 2 && result.TopCandidates[1].Letter == target)
        {
            double bestDist = Math.Max(0.001, result.TopCandidates[0].Distance);
            double targetDist = result.TopCandidates[1].Distance;
            return targetDist < 0.36 && (targetDist / bestDist) <= 1.15;
        }

        return false;
    }

    private static double DisambiguationPenalty(NormalizedCloud candidate, char target)
    {
        double penalty = 0.0;
        switch (target)
        {
            case 'I': if (candidate.HorizontalStrokeCount >= 2) penalty += 0.14; break;
            case 'T': if (candidate.HorizontalStrokeCount <= 1 && candidate.StrokeCount <= 2) penalty += 0.14; break;
            case 'U': if (candidate.HorizontalStrokeCount >= 1 && candidate.StrokeCount >= 2) penalty += 0.14; break;
            case 'V':
                if (candidate.StrokeCount == 1) penalty += 0.10;
                if (candidate.HorizontalStrokeCount >= 2) penalty += 0.10;
                break;
            case 'W': if (candidate.HorizontalStrokeCount < 2 && candidate.StrokeCount < 3) penalty += 0.12; break;
            case 'K': if (candidate.CentroidY > 0.56) penalty += 0.14; break;
            case 'L': if (candidate.CentroidY < 0.44) penalty += 0.14; break;
            case 'P': if (candidate.LeftMassFraction > 0.58) penalty += 0.08; break;
            case 'R': if (candidate.LeftMassFraction < 0.42) penalty += 0.08; break;
            case 'S': if (candidate.VerticalStrokeCount >= 2 && candidate.HorizontalStrokeCount == 0) penalty += 0.16; break;
            case 'Z': if (candidate.HorizontalStrokeCount >= 2 && candidate.VerticalStrokeCount == 0) penalty += 0.16; break;
            case 'H': if (candidate.AspectRatio < 0.95 && candidate.StrokeCount == 1) penalty += 0.12; break;
            case 'A': if (candidate.StrokeCount >= 3) penalty += 0.12; break;
            case 'Q': if (candidate.StrokeCount <= 2) penalty += 0.14; break;
        }
        return penalty;
    }

    private static NormalizedCloud Normalize(IReadOnlyList<IReadOnlyList<LoreenPoint>> strokes)
    {
        int hCount = 0;
        int vCount = 0;

        double minX = double.PositiveInfinity, maxX = double.NegativeInfinity;
        double minY = double.PositiveInfinity, maxY = double.NegativeInfinity;
        foreach (var stroke in strokes)
        {
            foreach (var p in stroke)
            {
                if (p.X < minX) minX = p.X;
                if (p.X > maxX) maxX = p.X;
                if (p.Y < minY) minY = p.Y;
                if (p.Y > maxY) maxY = p.Y;
            }
        }

        double rawW = Math.Max(1e-6, maxX - minX);
        double rawH = Math.Max(1e-6, maxY - minY);
        double aspect = rawW / rawH;
        double scale = Math.Max(rawW, rawH);

        foreach (var stroke in strokes)
        {
            if (stroke.Count < 2) continue;
            double sMinX = double.PositiveInfinity, sMaxX = double.NegativeInfinity;
            double sMinY = double.PositiveInfinity, sMaxY = double.NegativeInfinity;
            foreach (var p in stroke)
            {
                if (p.X < sMinX) sMinX = p.X;
                if (p.X > sMaxX) sMaxX = p.X;
                if (p.Y < sMinY) sMinY = p.Y;
                if (p.Y > sMaxY) sMaxY = p.Y;
            }
            double sw = sMaxX - sMinX;
            double sh = sMaxY - sMinY;
            double len = PathLength(stroke);
            bool isClosed = Dist(stroke[0], stroke[^1]) < scale * 0.18 && len > scale * 0.8;
            if (!isClosed)
            {
                if (sw > sh * 2.2 && sw > scale * 0.25) hCount++;
                else if (sh > sw * 2.2 && sh > scale * 0.25) vCount++;
            }
        }

        var resampled = ResampleMultistroke(strokes, SampleCount);
        double rMinX = double.PositiveInfinity, rMaxX = double.NegativeInfinity;
        double rMinY = double.PositiveInfinity, rMaxY = double.NegativeInfinity;
        foreach (var p in resampled)
        {
            if (p.X < rMinX) rMinX = p.X;
            if (p.X > rMaxX) rMaxX = p.X;
            if (p.Y < rMinY) rMinY = p.Y;
            if (p.Y > rMaxY) rMaxY = p.Y;
        }
        double rScale = Math.Max(1e-6, Math.Max(rMaxX - rMinX, rMaxY - rMinY));
        var scaled = resampled.Select(p => new LoreenPoint((p.X - rMinX) / rScale, (p.Y - rMinY) / rScale)).ToList();

        double cx = scaled.Sum(p => p.X) / scaled.Count;
        double cy = scaled.Sum(p => p.Y) / scaled.Count;
        double leftMass = (double)scaled.Count(p => p.X < 0.45) / scaled.Count;
        var centered = scaled.Select(p => new LoreenPoint(p.X - cx + 0.5, p.Y - cy + 0.5)).ToList();

        return new NormalizedCloud(centered, cy, aspect, hCount, vCount, strokes.Count, leftMass);
    }

    private static List<LoreenPoint> ResampleMultistroke(IReadOnlyList<IReadOnlyList<LoreenPoint>> strokes, int n)
    {
        double totalLen = strokes.Sum(PathLength);
        if (totalLen <= 1e-6)
        {
            var fallback = strokes.FirstOrDefault()?.FirstOrDefault() ?? new LoreenPoint(0.5, 0.5);
            return Enumerable.Repeat(fallback, n).ToList();
        }

        var lengths = strokes.Select(PathLength).ToList();
        var counts = lengths.Select(l => Math.Max(1, (int)Math.Round((l / totalLen) * n))).ToList();

        int diff = counts.Sum() - n;
        while (diff != 0)
        {
            if (diff > 0)
            {
                int idx = 0;
                for (int i = 1; i < counts.Count; i++) if (counts[i] > counts[idx]) idx = i;
                if (counts[idx] > 1) { counts[idx]--; diff--; } else break;
            }
            else
            {
                int idx = 0;
                for (int i = 1; i < lengths.Count; i++) if (lengths[i] > lengths[idx]) idx = i;
                counts[idx]++; diff++;
            }
        }

        var result = new List<LoreenPoint>(n);
        for (int i = 0; i < strokes.Count; i++)
        {
            result.AddRange(ResampleSingle(strokes[i], counts[i]));
        }
        return result;
    }

    private static List<LoreenPoint> ResampleSingle(IReadOnlyList<LoreenPoint> raw, int n)
    {
        if (raw.Count == 0) return new List<LoreenPoint>();
        if (raw.Count == 1 || n == 1) return Enumerable.Repeat(raw[0], n).ToList();

        var pts = raw.ToList();
        double len = PathLength(pts);
        if (len <= 1e-6) return Enumerable.Repeat(pts[0], n).ToList();

        double interval = len / (n - 1);
        double acc = 0.0;
        var newPts = new List<LoreenPoint>(n) { pts[0] };
        int i = 1;
        while (i < pts.Count)
        {
            double d = Dist(pts[i - 1], pts[i]);
            if (acc + d >= interval && d > 1e-9)
            {
                double qx = pts[i - 1].X + ((interval - acc) / d) * (pts[i].X - pts[i - 1].X);
                double qy = pts[i - 1].Y + ((interval - acc) / d) * (pts[i].Y - pts[i - 1].Y);
                var q = new LoreenPoint(qx, qy);
                newPts.Add(q);
                pts.Insert(i, q);
                acc = 0.0;
            }
            else
            {
                acc += d;
            }
            i++;
        }
        while (newPts.Count < n) newPts.Add(pts[^1]);
        return newPts.Count > n ? newPts.Take(n).ToList() : newPts;
    }

    private static double GreedyCloudMatch(List<LoreenPoint> a, List<LoreenPoint> b)
    {
        const double eps = 0.5;
        int step = Math.Max(1, (int)Math.Floor(Math.Pow(a.Count, 1.0 - eps)));
        double minDist = double.PositiveInfinity;
        for (int i = 0; i < a.Count; i += step)
        {
            double d1 = CloudDistance(a, b, i);
            double d2 = CloudDistance(b, a, i);
            minDist = Math.Min(minDist, Math.Min(d1, d2));
        }
        return minDist;
    }

    private static double CloudDistance(List<LoreenPoint> a, List<LoreenPoint> b, int start)
    {
        int n = a.Count;
        var matched = new bool[n];
        double sum = 0.0;
        int i = start;
        int visited = 0;
        do
        {
            double best = double.PositiveInfinity;
            int bestIdx = -1;
            for (int j = 0; j < n; j++)
            {
                if (!matched[j])
                {
                    double d = Dist(a[i], b[j]);
                    if (d < best) { best = d; bestIdx = j; }
                }
            }
            if (bestIdx >= 0)
            {
                matched[bestIdx] = true;
                double weight = 1.0 - (double)visited / n;
                sum += weight * best;
            }
            i = (i + 1) % n;
            visited++;
        } while (i != start);
        return sum / n;
    }

    private static double PathLength(IReadOnlyList<LoreenPoint> pts)
    {
        if (pts.Count < 2) return 0.0;
        double sum = 0.0;
        for (int i = 1; i < pts.Count; i++) sum += Dist(pts[i - 1], pts[i]);
        return sum;
    }

    private static double Dist(LoreenPoint a, LoreenPoint b)
    {
        double dx = a.X - b.X;
        double dy = a.Y - b.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }
}
