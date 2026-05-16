namespace Daily_WinUI.Services;

/// <summary>
/// Generates atmospheric SVG banner art (1400×110) based on an OpenWeatherMap icon code.
/// The SVG is returned as a UTF-8 string ready for loading via SvgImageSource.
/// </summary>
public static class WeatherTopBarGenerator
{
    // ── Public entry point ────────────────────────────────────────────────────

    public static string Generate(string iconCode)
    {
        bool isNight = iconCode.EndsWith("n", StringComparison.OrdinalIgnoreCase);
        string group = iconCode.Length >= 2 ? iconCode[..2] : "01";

        return group switch
        {
            "01" => isNight ? ClearNight()   : ClearDay(),
            "02" => isNight ? FewCloudsNight(): FewCloudsDay(),
            "03" => isNight ? CloudyNight()  : CloudyDay(),
            "04" => BrokenClouds(),
            "09" => ShowerRain(),
            "10" => isNight ? RainNight()    : RainDay(),
            "11" => Thunderstorm(),
            "13" => Snow(),
            "50" => Fog(),
            _    => isNight ? ClearNight()   : ClearDay(),
        };
    }

    // ── SVG builder helper ────────────────────────────────────────────────────

    private static string Svg(string defs, string body) => $"""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1400 110" preserveAspectRatio="xMidYMid slice">
          <defs>{defs}</defs>
          {body}
        </svg>
        """;

    // ── Condition scenes ──────────────────────────────────────────────────────

    private static string ClearDay() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#1a6fa8"/>
          <stop offset="100%" stop-color="#78c8f0"/>
        </linearGradient>
        <radialGradient id="sun" cx="85%" cy="30%" r="18%">
          <stop offset="0%"   stop-color="#fff9c4" stop-opacity="0.9"/>
          <stop offset="60%"  stop-color="#ffd54f" stop-opacity="0.4"/>
          <stop offset="100%" stop-color="#ff8f00" stop-opacity="0"/>
        </radialGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <rect width="1400" height="110" fill="url(#sun)"/>
        <!-- sun disc -->
        <circle cx="1190" cy="33" r="22" fill="#fff9c4" opacity="0.85"/>
        <!-- haze rings -->
        <circle cx="1190" cy="33" r="38" fill="none" stroke="#ffd54f" stroke-width="4" opacity="0.25"/>
        <circle cx="1190" cy="33" r="54" fill="none" stroke="#ffd54f" stroke-width="2" opacity="0.12"/>
        <!-- horizon shimmer -->
        <rect x="0" y="88" width="1400" height="22" fill="#a8dff5" opacity="0.18"/>
        """);

    private static string ClearNight() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#060d1a"/>
          <stop offset="100%" stop-color="#0e2044"/>
        </linearGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <!-- moon -->
        <circle cx="1180" cy="36" r="16" fill="#e8eaf6" opacity="0.88"/>
        <circle cx="1192" cy="28" r="14" fill="#0a1628" opacity="0.88"/>
        <!-- stars -->
        <circle cx="120"  cy="18" r="1.5" fill="white" opacity="0.7"/>
        <circle cx="340"  cy="30" r="1"   fill="white" opacity="0.5"/>
        <circle cx="580"  cy="14" r="1.5" fill="white" opacity="0.8"/>
        <circle cx="760"  cy="25" r="1"   fill="white" opacity="0.6"/>
        <circle cx="950"  cy="12" r="1.5" fill="white" opacity="0.7"/>
        <circle cx="1050" cy="40" r="1"   fill="white" opacity="0.5"/>
        <circle cx="220"  cy="45" r="1"   fill="white" opacity="0.4"/>
        <circle cx="670"  cy="42" r="1.5" fill="white" opacity="0.6"/>
        <circle cx="870"  cy="48" r="1"   fill="white" opacity="0.5"/>
        """);

    private static string FewCloudsDay() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#2176ae"/>
          <stop offset="100%" stop-color="#89d0ef"/>
        </linearGradient>
        <radialGradient id="sun" cx="80%" cy="25%" r="15%">
          <stop offset="0%"   stop-color="#fff9c4" stop-opacity="0.7"/>
          <stop offset="100%" stop-color="#ffd54f" stop-opacity="0"/>
        </radialGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <rect width="1400" height="110" fill="url(#sun)"/>
        <circle cx="1120" cy="28" r="18" fill="#fffde7" opacity="0.80"/>
        <!-- cloud 1 -->
        <ellipse cx="420" cy="55" rx="110" ry="28" fill="white" opacity="0.40"/>
        <ellipse cx="480" cy="44" rx="70"  ry="24" fill="white" opacity="0.35"/>
        <ellipse cx="350" cy="50" rx="60"  ry="20" fill="white" opacity="0.30"/>
        <!-- cloud 2 (smaller) -->
        <ellipse cx="900" cy="62" rx="80"  ry="20" fill="white" opacity="0.28"/>
        <ellipse cx="950" cy="53" rx="52"  ry="18" fill="white" opacity="0.25"/>
        """);

    private static string FewCloudsNight() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#07101f"/>
          <stop offset="100%" stop-color="#112036"/>
        </linearGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <circle cx="1150" cy="32" r="14" fill="#dde3f0" opacity="0.80"/>
        <circle cx="1161" cy="25" r="12" fill="#081420" opacity="0.80"/>
        <!-- cloud -->
        <ellipse cx="500" cy="60" rx="100" ry="24" fill="#c9d4e8" opacity="0.12"/>
        <ellipse cx="550" cy="50" rx="68"  ry="20" fill="#c9d4e8" opacity="0.10"/>
        <!-- stars -->
        <circle cx="200"  cy="20" r="1.2" fill="white" opacity="0.55"/>
        <circle cx="650"  cy="15" r="1.5" fill="white" opacity="0.60"/>
        <circle cx="900"  cy="28" r="1"   fill="white" opacity="0.50"/>
        """);

    private static string CloudyDay() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#6e8fa8"/>
          <stop offset="100%" stop-color="#b0c8d8"/>
        </linearGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <ellipse cx="200"  cy="60" rx="160" ry="36" fill="white" opacity="0.32"/>
        <ellipse cx="300"  cy="46" rx="110" ry="30" fill="white" opacity="0.28"/>
        <ellipse cx="700"  cy="55" rx="200" ry="38" fill="white" opacity="0.30"/>
        <ellipse cx="820"  cy="40" rx="130" ry="28" fill="white" opacity="0.25"/>
        <ellipse cx="1200" cy="58" rx="160" ry="34" fill="white" opacity="0.28"/>
        <ellipse cx="1280" cy="44" rx="100" ry="26" fill="white" opacity="0.22"/>
        """);

    private static string CloudyNight() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#151e2a"/>
          <stop offset="100%" stop-color="#2a3848"/>
        </linearGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <ellipse cx="250"  cy="58" rx="150" ry="32" fill="#4a5568" opacity="0.40"/>
        <ellipse cx="350"  cy="44" rx="100" ry="26" fill="#4a5568" opacity="0.32"/>
        <ellipse cx="750"  cy="52" rx="190" ry="34" fill="#4a5568" opacity="0.36"/>
        <ellipse cx="1250" cy="56" rx="150" ry="30" fill="#4a5568" opacity="0.38"/>
        """);

    private static string BrokenClouds() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#4a6070"/>
          <stop offset="100%" stop-color="#8ea8b8"/>
        </linearGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <ellipse cx="180"  cy="65" rx="180" ry="40" fill="#d0d8e0" opacity="0.35"/>
        <ellipse cx="290"  cy="48" rx="120" ry="32" fill="#d0d8e0" opacity="0.30"/>
        <ellipse cx="640"  cy="60" rx="220" ry="42" fill="#d0d8e0" opacity="0.32"/>
        <ellipse cx="760"  cy="42" rx="150" ry="30" fill="#d0d8e0" opacity="0.28"/>
        <ellipse cx="1100" cy="62" rx="180" ry="38" fill="#d0d8e0" opacity="0.30"/>
        <ellipse cx="1220" cy="46" rx="120" ry="28" fill="#d0d8e0" opacity="0.25"/>
        """);

    private static string ShowerRain() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#3a4a58"/>
          <stop offset="100%" stop-color="#6a8090"/>
        </linearGradient>
        """,
        RainBody(opacity: "0.55"));

    private static string RainDay() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#3d5060"/>
          <stop offset="100%" stop-color="#7090a0"/>
        </linearGradient>
        """,
        RainBody(opacity: "0.50"));

    private static string RainNight() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#0e1820"/>
          <stop offset="100%" stop-color="#2a3840"/>
        </linearGradient>
        """,
        RainBody(opacity: "0.40"));

    private static string RainBody(string opacity)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("<rect width=\"1400\" height=\"110\" fill=\"url(#bg)\"/>");
        // cloud mass
        sb.AppendLine($"<ellipse cx=\"400\"  cy=\"50\" rx=\"280\" ry=\"38\" fill=\"#8090a0\" opacity=\"{opacity}\"/>");
        sb.AppendLine($"<ellipse cx=\"900\"  cy=\"46\" rx=\"320\" ry=\"36\" fill=\"#8090a0\" opacity=\"{opacity}\"/>");
        // rain streaks
        int[] xs = [80, 160, 260, 380, 460, 560, 660, 740, 840, 940, 1040, 1140, 1240, 1320];
        foreach (var x in xs)
        {
            int y1 = 65 + (x % 18);
            sb.AppendLine($"<line x1=\"{x}\" y1=\"{y1}\" x2=\"{x - 5}\" y2=\"{y1 + 22}\" stroke=\"#a8d0e8\" stroke-width=\"1.2\" opacity=\"0.55\"/>");
            sb.AppendLine($"<line x1=\"{x + 28}\" y1=\"{y1 + 4}\" x2=\"{x + 23}\" y2=\"{y1 + 20}\" stroke=\"#a8d0e8\" stroke-width=\"1\" opacity=\"0.40\"/>");
        }
        return sb.ToString();
    }

    private static string Thunderstorm() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#1a1a2e"/>
          <stop offset="100%" stop-color="#2e3050"/>
        </linearGradient>
        <radialGradient id="flash" cx="50%" cy="40%" r="30%">
          <stop offset="0%"   stop-color="#fff9c4" stop-opacity="0.25"/>
          <stop offset="100%" stop-color="#fff9c4" stop-opacity="0"/>
        </radialGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <rect width="1400" height="110" fill="url(#flash)"/>
        <!-- dark cloud mass -->
        <ellipse cx="350"  cy="52" rx="260" ry="38" fill="#2a2a40" opacity="0.70"/>
        <ellipse cx="800"  cy="48" rx="300" ry="36" fill="#2a2a40" opacity="0.65"/>
        <ellipse cx="1150" cy="54" rx="220" ry="34" fill="#2a2a40" opacity="0.60"/>
        <!-- lightning bolts -->
        <polyline points="560,40 548,64 558,64 542,88" fill="none" stroke="#fff59d" stroke-width="2.5" opacity="0.90"/>
        <polyline points="860,38 848,60 857,60 840,85" fill="none" stroke="#fff59d" stroke-width="2"   opacity="0.70"/>
        <!-- rain -->
        <line x1="400"  y1="72" x2="394"  y2="90" stroke="#90b8d0" stroke-width="1.2" opacity="0.50"/>
        <line x1="650"  y1="70" x2="644"  y2="88" stroke="#90b8d0" stroke-width="1.2" opacity="0.50"/>
        <line x1="950"  y1="74" x2="944"  y2="92" stroke="#90b8d0" stroke-width="1.2" opacity="0.50"/>
        <line x1="1100" y1="70" x2="1094" y2="88" stroke="#90b8d0" stroke-width="1.2" opacity="0.50"/>
        """);

    private static string Snow() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#7890a0"/>
          <stop offset="100%" stop-color="#c8d8e8"/>
        </linearGradient>
        """,
        SnowBody());

    private static string SnowBody()
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("<rect width=\"1400\" height=\"110\" fill=\"url(#bg)\"/>");
        // cloud
        sb.AppendLine("<ellipse cx=\"500\"  cy=\"46\" rx=\"300\" ry=\"34\" fill=\"#e8eef4\" opacity=\"0.50\"/>");
        sb.AppendLine("<ellipse cx=\"1000\" cy=\"44\" rx=\"280\" ry=\"32\" fill=\"#e8eef4\" opacity=\"0.45\"/>");
        // snowflakes (simple crosses)
        (int x, int y)[] flakes = [(100,75),(200,82),(320,68),(430,88),(560,72),(680,90),(780,70),(890,84),(1010,74),(1130,86),(1240,70),(1360,80)];
        foreach (var (x, y) in flakes)
        {
            sb.AppendLine($"<line x1=\"{x - 5}\" y1=\"{y}\" x2=\"{x + 5}\" y2=\"{y}\" stroke=\"white\" stroke-width=\"1.5\" opacity=\"0.70\"/>");
            sb.AppendLine($"<line x1=\"{x}\" y1=\"{y - 5}\" x2=\"{x}\" y2=\"{y + 5}\" stroke=\"white\" stroke-width=\"1.5\" opacity=\"0.70\"/>");
            sb.AppendLine($"<line x1=\"{x - 4}\" y1=\"{y - 4}\" x2=\"{x + 4}\" y2=\"{y + 4}\" stroke=\"white\" stroke-width=\"1\" opacity=\"0.45\"/>");
            sb.AppendLine($"<line x1=\"{x + 4}\" y1=\"{y - 4}\" x2=\"{x - 4}\" y2=\"{y + 4}\" stroke=\"white\" stroke-width=\"1\" opacity=\"0.45\"/>");
        }
        return sb.ToString();
    }

    private static string Fog() => Svg(
        """
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#6a7880"/>
          <stop offset="100%" stop-color="#a8b8c0"/>
        </linearGradient>
        """,
        """
        <rect width="1400" height="110" fill="url(#bg)"/>
        <!-- horizontal fog bands -->
        <rect x="0" y="30" width="1400" height="14" rx="7" fill="white" opacity="0.18"/>
        <rect x="0" y="52" width="1400" height="12" rx="6" fill="white" opacity="0.14"/>
        <rect x="0" y="72" width="1400" height="10" rx="5" fill="white" opacity="0.12"/>
        <rect x="0" y="90" width="1400" height="10" rx="5" fill="white" opacity="0.10"/>
        <!-- soft left/right fades -->
        <rect x="0"    y="0" width="120" height="110" fill="url(#bg)" opacity="0.5"/>
        <rect x="1280" y="0" width="120" height="110" fill="url(#bg)" opacity="0.5"/>
        """);
}
