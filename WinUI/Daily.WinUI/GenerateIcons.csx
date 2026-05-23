#!/usr/bin/env dotnet-script
#r "nuget: Svg, 3.4.7"
#r "nuget: System.Drawing.Common, 9.0.0"

using Svg;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;

var assetsDir = Path.Combine(Directory.GetCurrentDirectory(), "Assets");
var svgPath   = Path.Combine(assetsDir, "GemIcon.svg");

// ── Helpers ──────────────────────────────────────────────────────────────────

// Load SVG as-is (no color/background changes) and rasterize with supersampling
Bitmap Render(string svgFile, int size, Dictionary<string, string> replacements = null)
{
    var svgText = File.ReadAllText(svgFile);
    if (replacements != null)
    {
        foreach (var kvp in replacements)
        {
            svgText = svgText.Replace(kvp.Key, kvp.Value);
        }
    }

    // Supersample factor — render 4× larger then downsample for crisp edges
    int scale = size <= 48 ? 8 : 4;
    int hiSize = size * scale;

    var doc = SvgDocument.FromSvg<SvgDocument>(svgText);
    doc.Width  = new SvgUnit(SvgUnitType.Pixel, hiSize);
    doc.Height = new SvgUnit(SvgUnitType.Pixel, hiSize);

    var hiBmp = new Bitmap(hiSize, hiSize, PixelFormat.Format32bppArgb);
    using (var gHi = Graphics.FromImage(hiBmp))
    {
        gHi.Clear(Color.Transparent);
        gHi.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        gHi.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        gHi.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
        doc.Draw(hiBmp);
    }

    // Downsample to target size with high-quality bicubic
    var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp))
    {
        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
        g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
        g.DrawImage(hiBmp, 0, 0, size, size);
    }
    hiBmp.Dispose();
    return bmp;
}

void Save(Bitmap bmp, string path)
{
    bmp.Save(path, ImageFormat.Png);
    Console.WriteLine($"  saved {Path.GetFileName(path)} ({bmp.Width}x{bmp.Height})");
}

// Create ICO from multiple bitmaps
void SaveIco(IEnumerable<Bitmap> bitmaps, string path)
{
    using var ms = new MemoryStream();
    var bmList = bitmaps.ToList();
    int count = bmList.Count;

    ms.Write(new byte[] { 0, 0, 1, 0 }, 0, 4);           // reserved, ICO type
    ms.Write(BitConverter.GetBytes((short)count), 0, 2);  // image count

    var pngStreams = bmList.Select(b => { var s = new MemoryStream(); b.Save(s, ImageFormat.Png); s.Position = 0; return s; }).ToList();
    int offset = 6 + count * 16;

    foreach (var (b, ps) in bmList.Zip(pngStreams))
    {
        int w = b.Width > 255 ? 0 : b.Width;
        int h = b.Height > 255 ? 0 : b.Height;
        ms.WriteByte((byte)w);
        ms.WriteByte((byte)h);
        ms.WriteByte(0); ms.WriteByte(0);               // color count, reserved
        ms.Write(new byte[] { 1, 0 }, 0, 2);             // color planes
        ms.Write(new byte[] { 32, 0 }, 0, 2);            // bits per pixel
        ms.Write(BitConverter.GetBytes((int)ps.Length), 0, 4);
        ms.Write(BitConverter.GetBytes(offset), 0, 4);
        offset += (int)ps.Length;
    }
    foreach (var ps in pngStreams) ps.CopyTo(ms);

    File.WriteAllBytes(path, ms.ToArray());
    Console.WriteLine($"  saved {Path.GetFileName(path)} (multi-size ICO)");
}

// ── Generate ──────────────────────────────────────────────────────────────────
Console.WriteLine("Generating app icons...");

// Use user-provided theme-specific SVG files
Console.WriteLine("Using user-provided theme-specific SVG files...");

// Manifest PNG assets — dark-theme icon (yellowish on navy) for all sizes
var specs = new (string file, int size)[]
{
    ("Square44x44Logo.png",                              44),   // base (manifest reference)
    ("Square44x44Logo.scale-100.png",                    44),
    ("Square44x44Logo.scale-200.png",                    88),
    ("Square44x44Logo.targetsize-24_altform-unplated.png", 24),
    ("Square44x44Logo.targetsize-48_altform-unplated.png", 48),
    ("Square44x44Logo.targetsize-48_altform-lightunplated.png", 48),
    ("Square150x150Logo.scale-100.png",                 150),
    ("Square150x150Logo.scale-200.png",                 300),
    ("Wide310x150Logo.scale-200.png",                   310),   // width; will square-crop below
    ("SplashScreen.scale-200.png",                      620),
    ("StoreLogo.png",                                    50),
};

foreach (var (file, size) in specs)
{
    // Wide logo needs special treatment: 310x150
    if (file.StartsWith("Wide310x150"))
    {
        var bmp310 = new Bitmap(310, 150, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp310);
        g.Clear(Color.Transparent);
        var icon = Render(svgPath, 110);
        g.DrawImage(icon, (310 - 110) / 2, (150 - 110) / 2);
        Save(bmp310, Path.Combine(assetsDir, file));
    }
    else if (file.StartsWith("SplashScreen"))
    {
        var bmp = new Bitmap(620, 300, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.Clear(Color.Transparent);
        var icon = Render(svgPath, 200);
        g.DrawImage(icon, (620 - 200) / 2, (300 - 200) / 2);
        Save(bmp, Path.Combine(assetsDir, file));
    }
    else
    {
        using var bmp = Render(svgPath, size);
        Save(bmp, Path.Combine(assetsDir, file));
    }
}

// Extra targetsize assets Windows uses for title bar / small icons
var extraSizes = new (string file, int size)[]
{
    ("Square44x44Logo.targetsize-16_altform-unplated.png", 16),
    ("Square44x44Logo.targetsize-20_altform-unplated.png", 20),
    ("Square44x44Logo.targetsize-32_altform-unplated.png", 32),
    ("Square44x44Logo.targetsize-256_altform-unplated.png", 256),
};
foreach (var (file, size) in extraSizes)
{
    using var bmp = Render(svgPath, size);
    Save(bmp, Path.Combine(assetsDir, file));
}

// ICO — 16,20,24,32,48,256
var icoSizes = new[] { 16, 20, 24, 32, 48, 256 };
var icoBmps  = icoSizes.Select(s => Render(svgPath, s)).ToList();
SaveIco(icoBmps, Path.Combine(assetsDir, "AppIcon.ico"));
foreach (var b in icoBmps) b.Dispose();

// StoreLogo — same SVG, just 50px
var storeBmp = Render(svgPath, 50);
Save(storeBmp, Path.Combine(assetsDir, "StoreLogo.png"));
storeBmp.Dispose();

// Tray Icons (Theme-specific)
Console.WriteLine("Generating system tray icons...");
var traySizes = new[] { 16, 20, 24, 32, 48, 256 };

var darkTrayBmps = traySizes.Select(s => Render(svgPath, s)).ToList();
SaveIco(darkTrayBmps, Path.Combine(assetsDir, "TrayIconDarkTheme.ico"));
foreach (var b in darkTrayBmps) b.Dispose();

var lightTrayBmps = traySizes.Select(s => Render(svgPath, s)).ToList();
SaveIco(lightTrayBmps, Path.Combine(assetsDir, "TrayIconLightTheme.ico"));
foreach (var b in lightTrayBmps) b.Dispose();

Console.WriteLine("Done!");
