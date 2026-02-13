using Microsoft.Maui.Controls;
using Microsoft.Maui.Graphics;

namespace Daily.Helpers
{
    public static class IconFonts
    {
        public const string MaterialSymbolsOutlined = "MaterialSymbolsOutlined";

        public static FontImageSource CreateMaterialIcon(string glyph, Color color, double size)
        {
            return new FontImageSource
            {
                FontFamily = MaterialSymbolsOutlined,
                Glyph = glyph,
                Color = color,
                Size = size
            };
        }
    }
}
