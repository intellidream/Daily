#!/usr/bin/env dotnet-script
#r "nuget: Svg, 3.4.7"
#r "nuget: System.Drawing.Common, 9.0.0"

using Svg;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

var assetsDir = Path.Combine(Directory.GetCurrentDirectory(), "Assets");
var svgPath   = Path.Combine(assetsDir, "appicon.theme-dark.svg");

// Colors
var navyBg      = Color.FromArgb(255, 11,  17,  33);   // #0B1121
var yellowFg    = Color.FromArgb(255, 245, 240, 232);  // #F5F0E8 (light yellowish-gray)
var whiteFg     = Color.FromArgb(255, 255, 255, 255);  // white  (for light-bg version)

// ── Helpers ──────────────────────────────────────────────────────────────────

// Load SVG, replace fill color, rasterize at given size on given background
Bitmap Render(string svgFile, Color iconColor, Color bgColor, int size)
{
    var svgText = File.ReadAllText(svgFile)
        .Replace("fill:white", $"fill:rgb({iconColor.R},{iconColor.G},{iconColor.B})")
        .Replace("style=\"fill:white", $"style=\"fill:rgb({iconColor.R},{iconColor.G},{iconColor.B})");

    var doc = SvgDocument.FromSvg<SvgDocument>(svgText);
    doc.Width  = new SvgUnit(SvgUnitType.Pixel, size);
    doc.Height = new SvgUnit(SvgUnitType.Pixel, size);

    var bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    using var g = Graphics.FromImage(bmp);
    g.Clear(bgColor);
    g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
    doc.Draw(bmp);
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

// Manifest PNG assets — dark-theme icon (yellowish on navy) for all sizes
var specs = new (string file, int size)[]
{
    ("Square44x44Logo.scale-100.png",                    44),
    ("Square44x44Logo.targetsize-24_altform-unplated.png", 24),
    ("Square44x44Logo.targetsize-48_altform-lightunplated.png", 48),
    ("Square150x150Logo.scale-100.png",                 150),
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
        g.Clear(navyBg);
        var icon = Render(svgPath, yellowFg, navyBg, 110);
        g.DrawImage(icon, (310 - 110) / 2, (150 - 110) / 2);
        Save(bmp310, Path.Combine(assetsDir, file));
    }
    else if (file.StartsWith("SplashScreen"))
    {
        var bmp = new Bitmap(620, 300, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.Clear(navyBg);
        var icon = Render(svgPath, yellowFg, navyBg, 200);
        g.DrawImage(icon, (620 - 200) / 2, (300 - 200) / 2);
        Save(bmp, Path.Combine(assetsDir, file));
    }
    else
    {
        using var bmp = Render(svgPath, yellowFg, navyBg, size);
        Save(bmp, Path.Combine(assetsDir, file));
    }
}

// ICO — 16,32,48,256
var icoSizes = new[] { 16, 32, 48, 256 };
var icoBmps  = icoSizes.Select(s => Render(svgPath, yellowFg, navyBg, s)).ToList();
SaveIco(icoBmps, Path.Combine(assetsDir, "AppIcon.ico"));
foreach (var b in icoBmps) b.Dispose();

// StoreLogo: light-theme version (dark icon on light bg) for Store
var storeLight = Render(
    Path.Combine(assetsDir, "appicon.theme-light.svg"),
    navyBg, yellowFg, 50);
Save(storeLight, Path.Combine(assetsDir, "StoreLogo.png"));
storeLight.Dispose();

Console.WriteLine("Done!");
