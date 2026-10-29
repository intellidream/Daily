using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Threading.Tasks;
using Daily.Models;
using Daily_WinUI.Services;
using Daily_WinUI.Services.Cosmos;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Graphics.Canvas;
using Microsoft.Graphics.Canvas.Brushes;
using Microsoft.Graphics.Canvas.Geometry;
using Microsoft.Graphics.Canvas.Text;
using Microsoft.Graphics.Canvas.UI;
using Microsoft.Graphics.Canvas.UI.Xaml;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Foundation;
using Windows.System;
using Windows.UI;

namespace Daily_WinUI.Views
{
    public sealed partial class CosmosDetailPage : Page
    {
        private enum SkyGridMode
        {
            Off = 0,
            HorizontalAltAz = 1,
            EquatorialRaDec = 2
        }

        private sealed class HitTestableTarget
        {
            public string ObjectId { get; init; } = string.Empty;
            public string Name { get; init; } = string.Empty;
            public string Subtitle { get; init; } = string.Empty;
            public string Category { get; init; } = string.Empty;
            public float ScreenX { get; init; }
            public float ScreenY { get; init; }
            public float HitRadius { get; init; }
            public int Priority { get; init; }
            public object Payload { get; init; } = null!;
        }

        private readonly AstronomyService _astronomyService = AstronomyService.Shared;
        private readonly CosmosCatalogRepository _catalogRepo = CosmosCatalogRepository.Shared;
        private readonly CosmosLiveService _liveService = CosmosLiveService.Shared;

        // Observer Location (resolved from SettingsService + LocationService; never hardcoded)
        private double _latitude = 44.4323;
        private double _longitude = 26.1063;
        private double _elevationMeters = 80.0;
        private string _locationLabel = "Local Observatory";
        private int _bortleClass = 5;

        // Camera State (60–120Hz interactive)
        private double _cameraAzimuth = 180.0;
        private double _cameraAltitude = 35.0;
        private double _fieldOfView = 75.0;
        private bool _isZenithPlanisphereLocked;

        // Layer & Mode State
        private bool _isNightVision;
        private bool _showConstellations = true;
        private bool _showDsos = true;
        private bool _showAtmosphere = true;
        private SkyGridMode _gridMode = SkyGridMode.Off;
        private bool _isDeckExpanded = true;

        // Time Machine State
        private TimeSpan _timeOffset = TimeSpan.Zero;
        private int _playMultiplier = 1; // 1 = real-time, 0 = paused, 60 = 60x, 600 = 600x
        private DateTime _lastPlayTickUtc = DateTime.UtcNow;
        private bool _suppressTimeControls;

        // Ephemeris & Live Telemetry State (1Hz)
        private List<CelestialCoordinates> _bodies = new();
        private MoonPhaseInfo _moonPhase = new();
        private JupiterMoonsState _jupiterMoons = new();
        private double _saturnRingTiltDeg;
        private StargazingConditions _stargazing = new();
        private CircadianSkyContext _circadian = new();
        private CosmosLiveBundle? _liveBundle;
        private LiveSatellitePosition? _issLivePos;
        private List<CosmosBookmarkRecord> _bookmarks = new();

        // Pointer & Selection State
        private bool _isDragging;
        private Point _dragStartPos;
        private Point _lastPointerPos;
        private bool _dragMoved;
        private Point? _hoverPointerPos;
        private HitTestableTarget? _hoveredTarget;
        private object? _selectedTarget;
        private readonly List<HitTestableTarget> _hitTargets = new(256);

        // Timers
        private DispatcherTimer? _ephemerisTimer;
        private DispatcherTimer? _playTimer;
        private DispatcherTimer? _toastTimer;

        // Win2D Cached Text Formats & Stroke Styles
        private readonly CanvasTextFormat _constellationLabelFormat = new()
        {
            FontFamily = "Segoe UI",
            FontSize = 10.5f,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        };
        private readonly CanvasTextFormat _starLabelFormat = new()
        {
            FontFamily = "Segoe UI",
            FontSize = 10.0f,
            FontWeight = Microsoft.UI.Text.FontWeights.Normal
        };
        private readonly CanvasTextFormat _planetLabelFormat = new()
        {
            FontFamily = "Segoe UI",
            FontSize = 11.0f,
            FontWeight = Microsoft.UI.Text.FontWeights.Bold
        };
        private readonly CanvasTextFormat _cardinalLabelFormat = new()
        {
            FontFamily = "Segoe UI Variable Display",
            FontSize = 12.0f,
            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
            HorizontalAlignment = CanvasHorizontalAlignment.Center,
            VerticalAlignment = CanvasVerticalAlignment.Center
        };
        private readonly CanvasStrokeStyle _dashedStroke = new()
        {
            DashStyle = CanvasDashStyle.Dash
        };
        private readonly CanvasStrokeStyle _dottedStroke = new()
        {
            DashStyle = CanvasDashStyle.Dot
        };

        private DateTime CurrentSimulationUtc => DateTime.UtcNow + _timeOffset;

        public CosmosDetailPage()
        {
            this.InitializeComponent();
            this.Loaded += CosmosDetailPage_Loaded;
            this.Unloaded += CosmosDetailPage_Unloaded;
            this.KeyDown += CosmosDetailPage_KeyDown;

            try
            {
                EpochDatePicker.MinDate = new DateTimeOffset(1900, 1, 1, 0, 0, 0, TimeSpan.Zero);
                EpochDatePicker.MaxDate = new DateTimeOffset(2100, 12, 31, 0, 0, 0, TimeSpan.Zero);
            }
            catch { }
        }

        private async void CosmosDetailPage_Loaded(object sender, RoutedEventArgs e)
        {
            // Hide Back & PopOut if hosted inside a detached DetailWindow
            if (this.Frame != App.Current?.MainWindow?.RootFrame)
            {
                BackButton.Visibility = Visibility.Collapsed;
                PopOutButton.Visibility = Visibility.Collapsed;
            }

            ResolveInitialObserverLocation();
            await _catalogRepo.EnsureLoadedAsync();
            _bortleClass = _catalogRepo.GetBortleClass(_latitude, _longitude);

            RefreshEphemerisSnapshot();
            if (_selectedTarget == null)
            {
                var moon = _bodies.FirstOrDefault(b => b.Body == CelestialBody.Moon);
                if (moon != null) SelectTarget(moon, centerCamera: false);
            }

            ApplyPaletteToChrome();
            UpdateResponsiveDeckLayout(RootLayout.ActualWidth);
            SkyCanvas.Invalidate();

            StartTimers();
            _ = RefreshObserverAndLiveTelemetryAsync();
        }

        private void CosmosDetailPage_Unloaded(object sender, RoutedEventArgs e)
        {
            StopTimers();
        }

        public async Task RefreshFromTitleBarAsync()
        {
            await RefreshObserverAndLiveTelemetryAsync(forceLocation: true);
        }

        private void ResolveInitialObserverLocation()
        {
            try
            {
                var appSettings = SettingsService.Load();
                if (appSettings.LastLatitude.HasValue && appSettings.LastLongitude.HasValue)
                {
                    _latitude = appSettings.LastLatitude.Value;
                    _longitude = appSettings.LastLongitude.Value;
                }
                if (!string.IsNullOrWhiteSpace(appSettings.LastLocationName))
                {
                    _locationLabel = appSettings.LastLocationName!;
                }
                else
                {
                    _locationLabel = FormatCoordinateLabel(_latitude, _longitude);
                }
            }
            catch
            {
                _locationLabel = FormatCoordinateLabel(_latitude, _longitude);
            }
        }

        private async Task RefreshObserverAndLiveTelemetryAsync(bool forceLocation = false)
        {
            try
            {
                var locService = App.Current?.Services?.GetService<LocationService>();
                if (locService != null)
                {
                    var coords = await locService.GetCurrentCoordinatesAsync(forceLocation);
                    if (coords.HasValue)
                    {
                        _latitude = coords.Value.Latitude;
                        _longitude = coords.Value.Longitude;
                        var appSettings = SettingsService.Load();
                        if (string.IsNullOrWhiteSpace(appSettings.LastLocationName))
                            _locationLabel = FormatCoordinateLabel(_latitude, _longitude);
                    }
                }
            }
            catch { }

            _bortleClass = _catalogRepo.GetBortleClass(_latitude, _longitude);
            var bookmarksTask = _liveService.LoadBookmarksAsync();
            var bundleTask = _liveService.FetchLiveBundleAsync(_latitude, _longitude, _elevationMeters);

            await Task.WhenAll(bookmarksTask, bundleTask);

            var bookmarks = await bookmarksTask;
            var bundle = await bundleTask;

            DispatcherQueue.TryEnqueue(() =>
            {
                _bookmarks = bookmarks;
                _liveBundle = bundle;
                RefreshEphemerisSnapshot();
                RenderIssDeck();
                RenderSpaceWeatherDeck();
                RenderBookmarksDeck();
                RenderApodDeck();
                SkyCanvas.Invalidate();
            });
        }

        private static string FormatCoordinateLabel(double lat, double lon)
        {
            string ns = lat >= 0 ? "N" : "S";
            string ew = lon >= 0 ? "E" : "W";
            return string.Create(CultureInfo.InvariantCulture, $"{Math.Abs(lat):F2}°{ns}, {Math.Abs(lon):F2}°{ew}");
        }

        // ── Adaptive Timers (1Hz Ephemeris + Smooth Time Machine Play) ───────────

        private void StartTimers()
        {
            StopTimers();

            _ephemerisTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _ephemerisTimer.Tick += (_, _) =>
            {
                if (_playMultiplier == 0)
                {
                    _timeOffset -= TimeSpan.FromSeconds(1);
                }
                RefreshEphemerisSnapshot();
                SkyCanvas.Invalidate();
            };
            _ephemerisTimer.Start();

            _playTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
            _playTimer.Tick += (_, _) =>
            {
                if (_playMultiplier <= 1) return;
                DateTime now = DateTime.UtcNow;
                double dtSec = Math.Clamp((now - _lastPlayTickUtc).TotalSeconds, 0.0, 0.25);
                _lastPlayTickUtc = now;
                _timeOffset += TimeSpan.FromSeconds(dtSec * (_playMultiplier - 1));
                RefreshEphemerisSnapshot();
                SkyCanvas.Invalidate();
            };
            _lastPlayTickUtc = DateTime.UtcNow;
            if (_playMultiplier > 1) _playTimer.Start();
        }

        private void StopTimers()
        {
            _ephemerisTimer?.Stop();
            _ephemerisTimer = null;
            _playTimer?.Stop();
            _playTimer = null;
            _toastTimer?.Stop();
            _toastTimer = null;
        }

        // ── Ephemeris & Telemetry Snapshot (1Hz) ─────────────────────────────────

        private void RefreshEphemerisSnapshot()
        {
            DateTime simUtc = CurrentSimulationUtc;
            _bodies = _astronomyService.GetAllVisibleBodies(simUtc, _latitude, _longitude, _elevationMeters);
            _moonPhase = _astronomyService.GetMoonPhase(simUtc, _latitude, _longitude);
            _jupiterMoons = _astronomyService.GetJupiterMoons(simUtc, _latitude, _longitude);
            _saturnRingTiltDeg = _astronomyService.GetSaturnRingTiltDegrees(simUtc);
            _circadian = _astronomyService.GetCircadianContext(simUtc, _latitude, _longitude);

            var w = _liveBundle?.WeatherOverlay;
            _stargazing = _astronomyService.EvaluateStargazingConditions(
                _latitude,
                _longitude,
                simUtc,
                w?.CloudTotalPercent,
                w?.CloudLowPercent,
                w?.CloudMidPercent,
                w?.CloudHighPercent,
                _bortleClass,
                w?.SeeingArcseconds,
                w?.TransparencyLabel,
                w?.TemperatureCelsius,
                w?.DewPointCelsius,
                w?.Provenance ?? TelemetryProvenance.OfflineCalculated("Offline Ephemeris + Bortle Grid"));

            if (_liveBundle?.IssOmm != null)
            {
                _issLivePos = SGP4Propagator.LivePosition(_liveBundle.IssOmm, simUtc, _latitude, _longitude, _elevationMeters);
            }
            else
            {
                _issLivePos = null;
            }

            UpdateHudAndDeck(simUtc);
            UpdatePlanetsCarousel();
            if (_selectedTarget != null)
            {
                RefreshSelectedTargetInspector();
            }
        }

        // ── GPU Direct2D Win2D Planetarium Renderer (`SkyCanvas_Draw`) ───────────

        private void SkyCanvas_CreateResources(CanvasControl sender, CanvasCreateResourcesEventArgs args)
        {
            // Vector fonts & procedural surfaces require zero external shader compilation
        }

        private void SkyCanvas_Draw(CanvasControl sender, CanvasDrawEventArgs args)
        {
            float w = (float)sender.ActualWidth;
            float h = (float)sender.ActualHeight;
            if (w < 8f || h < 8f) return;

            var ds = args.DrawingSession;
            ds.Antialiasing = CanvasAntialiasing.Antialiased;

            DateTime simUtc = CurrentSimulationUtc;
            double renderAlt = _isZenithPlanisphereLocked ? 90.0 : _cameraAltitude;
            var matrix = _astronomyService.MakeProjectionMatrix(
                _latitude, _longitude, _elevationMeters,
                simUtc,
                _cameraAzimuth, renderAlt, 0.0,
                _fieldOfView, w, h);

            _hitTargets.Clear();

            // 1. Rayleigh Daylight / Twilight / Scotopic Sky Gradient
            DrawSkyAtmosphereBackground(sender, ds, w, h);

            // 2. 5-Layer Galactic Milky Way Isophotes
            DrawMilkyWayIsophotes(sender, ds, matrix);

            // 3. Coordinate Grids (Alt-Az or Equatorial RA/Dec) & Ecliptic
            if (_gridMode != SkyGridMode.Off)
            {
                DrawCoordinateGrid(ds, matrix, simUtc);
            }
            DrawEclipticCurve(ds, matrix);

            // 4. Constellation Boundaries, 14 Asterisms & 88 Official IAU Constellations
            if (_showConstellations)
            {
                DrawConstellationsAndAsterisms(ds, matrix);
            }

            // 5. All 15,544 Hipparcos Stars (Batch Projected, Pogson Flux, Ballesteros B-V, Airmass Scintillation)
            DrawPackedHipparcosStars(ds, matrix, simUtc);

            // 6. 219 Messier & Caldwell Deep-Sky Objects
            if (_showDsos)
            {
                DrawDeepSkyObjects(ds, matrix);
            }

            // 7. Active IAU Meteor Shower Radiants
            DrawMeteorShowerRadiants(ds, matrix, simUtc);

            // 8. Solar System Bodies (Spherical Lunar Terminator, Saturn Ring Tilt, Jupiter + 4 Galilean Moons)
            DrawSolarSystemBodies(ds, matrix);

            // 9. Native SGP4 ISS Live Marker & Sunlit/Umbra Pass Trajectory
            DrawIssAndPassArc(ds, matrix);

            // 10. Topocentric Horizon Silhouette / Zenith Planisphere Ring + 8 Cardinal Beacons
            DrawHorizonAndCompassBeacons(sender, ds, matrix, w, h);

            // 11. Center Optical Crosshair, Selected Target Lock & Hover Reticle
            DrawReticles(ds, matrix, w, h);
        }

        private void DrawSkyAtmosphereBackground(ICanvasResourceCreator creator, CanvasDrawingSession ds, float w, float h)
        {
            if (_isNightVision)
            {
                ds.Clear(Color.FromArgb(255, 4, 0, 0));
                return;
            }

            var sun = _bodies.FirstOrDefault(b => b.Body == CelestialBody.Sun);
            double sunAlt = sun?.Altitude ?? -25.0;

            if (!_showAtmosphere || sunAlt <= -18.0)
            {
                using var nightBrush = new CanvasLinearGradientBrush(
                    creator,
                    Color.FromArgb(255, 2, 4, 11),
                    Color.FromArgb(255, 7, 13, 28))
                {
                    StartPoint = new Vector2(0, 0),
                    EndPoint = new Vector2(0, h)
                };
                ds.FillRectangle(0, 0, w, h, nightBrush);
                return;
            }

            Color topColor, botColor;
            if (sunAlt > 4.0)
            {
                // Astronomical daytime sapphire so stars and constellations stay legible
                topColor = Color.FromArgb(255, 10, 31, 76);
                botColor = Color.FromArgb(255, 25, 64, 122);
            }
            else if (sunAlt > -6.0)
            {
                // Civil twilight golden/cobalt
                topColor = Color.FromArgb(255, 11, 24, 62);
                botColor = Color.FromArgb(255, 86, 56, 78);
            }
            else
            {
                // Nautical/Astronomical twilight indigo
                double t = (sunAlt + 18.0) / 12.0;
                topColor = Color.FromArgb(255, (byte)(3 + 6 * t), (byte)(5 + 12 * t), (byte)(14 + 28 * t));
                botColor = Color.FromArgb(255, (byte)(8 + 26 * t), (byte)(14 + 22 * t), (byte)(30 + 40 * t));
            }

            using var brush = new CanvasLinearGradientBrush(creator, topColor, botColor)
            {
                StartPoint = new Vector2(0, 0),
                EndPoint = new Vector2(0, h)
            };
            ds.FillRectangle(0, 0, w, h, brush);
        }

        private void DrawMilkyWayIsophotes(ICanvasResourceCreator creator, CanvasDrawingSession ds, SkyProjectionMatrix matrix)
        {
            var sun = _bodies.FirstOrDefault(b => b.Body == CelestialBody.Sun);
            if (_showAtmosphere && sun != null && sun.Altitude > -6.0) return;

            double bortleFactor = Math.Clamp((9.5 - _bortleClass) / 7.5, 0.22, 1.0);
            foreach (var layer in _catalogRepo.MilkyWayLayers)
            {
                byte baseAlpha = (byte)Math.Clamp((int)Math.Round((10 + layer.Level * 6) * bortleFactor), 4, 34);
                Color fill = _isNightVision
                    ? Color.FromArgb((byte)(baseAlpha * 0.75), 140, 8, 16)
                    : Color.FromArgb(baseAlpha, 128, 158, 225);

                for (int r = 0; r < layer.RingsUx.Length; r++)
                {
                    var ux = layer.RingsUx[r];
                    var uy = layer.RingsUy[r];
                    var uz = layer.RingsUz[r];
                    if (ux.Length < 3) continue;

                    using var pb = new CanvasPathBuilder(creator);
                    bool started = false;
                    float prevX = 0, prevY = 0;
                    bool validRing = true;

                    for (int i = 0; i < ux.Length; i++)
                    {
                        var p = matrix.ProjectEQJUnitVector(ux[i], uy[i], uz[i], margin: 500.0);
                        if (p == null || p.Value.Cz < -0.25)
                        {
                            validRing = false;
                            break;
                        }
                        float sx = (float)p.Value.X;
                        float sy = (float)p.Value.Y;
                        if (!started)
                        {
                            pb.BeginFigure(sx, sy);
                            started = true;
                        }
                        else
                        {
                            if (Math.Abs(sx - prevX) > matrix.ViewportWidth * 0.85 ||
                                Math.Abs(sy - prevY) > matrix.ViewportHeight * 0.85)
                            {
                                validRing = false;
                                break;
                            }
                            pb.AddLine(sx, sy);
                        }
                        prevX = sx;
                        prevY = sy;
                    }

                    if (started && validRing)
                    {
                        pb.EndFigure(CanvasFigureLoop.Closed);
                        using var geom = CanvasGeometry.CreatePath(pb);
                        ds.FillGeometry(geom, fill);
                    }
                    else if (started)
                    {
                        pb.EndFigure(CanvasFigureLoop.Open);
                    }
                }
            }
        }

        private void DrawCoordinateGrid(CanvasDrawingSession ds, SkyProjectionMatrix matrix, DateTime simUtc)
        {
            Color gridColor = _isNightVision
                ? Color.FromArgb(46, 255, 24, 36)
                : (_gridMode == SkyGridMode.HorizontalAltAz
                    ? Color.FromArgb(38, 90, 195, 255)
                    : Color.FromArgb(38, 190, 145, 255));

            if (_gridMode == SkyGridMode.HorizontalAltAz)
            {
                for (int alt = 0; alt <= 75; alt += 15)
                {
                    ProjectedSkyPoint? prev = null;
                    for (int az = 0; az <= 360; az += 5)
                    {
                        var cur = matrix.ProjectHorizontal(az, alt, 180.0);
                        if (prev != null && cur != null && (prev.Value.IsVisible || cur.Value.IsVisible))
                        {
                            double dx = cur.Value.X - prev.Value.X;
                            double dy = cur.Value.Y - prev.Value.Y;
                            if (dx * dx + dy * dy < 90_000)
                                ds.DrawLine((float)prev.Value.X, (float)prev.Value.Y, (float)cur.Value.X, (float)cur.Value.Y, gridColor, 0.8f);
                        }
                        prev = cur;
                    }
                }

                for (int az = 0; az < 360; az += 30)
                {
                    ProjectedSkyPoint? prev = null;
                    for (int alt = -15; alt <= 90; alt += 5)
                    {
                        var cur = matrix.ProjectHorizontal(az, alt, 180.0);
                        if (prev != null && cur != null && (prev.Value.IsVisible || cur.Value.IsVisible))
                        {
                            double dx = cur.Value.X - prev.Value.X;
                            double dy = cur.Value.Y - prev.Value.Y;
                            if (dx * dx + dy * dy < 90_000)
                                ds.DrawLine((float)prev.Value.X, (float)prev.Value.Y, (float)cur.Value.X, (float)cur.Value.Y, gridColor, 0.8f);
                        }
                        prev = cur;
                    }
                }
            }
            else if (_gridMode == SkyGridMode.EquatorialRaDec)
            {
                for (int dec = -75; dec <= 75; dec += 15)
                {
                    ProjectedSkyPoint? prev = null;
                    double decRad = dec * (Math.PI / 180.0);
                    double cosD = Math.Cos(decRad), sinD = Math.Sin(decRad);
                    for (int raDeg = 0; raDeg <= 360; raDeg += 5)
                    {
                        double r = raDeg * (Math.PI / 180.0);
                        var cur = matrix.ProjectEQJUnitVector(cosD * Math.Cos(r), cosD * Math.Sin(r), sinD, 180.0);
                        if (prev != null && cur != null && (prev.Value.IsVisible || cur.Value.IsVisible))
                        {
                            double dx = cur.Value.X - prev.Value.X;
                            double dy = cur.Value.Y - prev.Value.Y;
                            if (dx * dx + dy * dy < 90_000)
                                ds.DrawLine((float)prev.Value.X, (float)prev.Value.Y, (float)cur.Value.X, (float)cur.Value.Y, gridColor, 0.8f);
                        }
                        prev = cur;
                    }
                }

                for (int raH = 0; raH < 24; raH += 2)
                {
                    ProjectedSkyPoint? prev = null;
                    double r = raH * 15.0 * (Math.PI / 180.0);
                    double cosR = Math.Cos(r), sinR = Math.Sin(r);
                    for (int dec = -85; dec <= 85; dec += 5)
                    {
                        double d = dec * (Math.PI / 180.0);
                        var cur = matrix.ProjectEQJUnitVector(Math.Cos(d) * cosR, Math.Cos(d) * sinR, Math.Sin(d), 180.0);
                        if (prev != null && cur != null && (prev.Value.IsVisible || cur.Value.IsVisible))
                        {
                            double dx = cur.Value.X - prev.Value.X;
                            double dy = cur.Value.Y - prev.Value.Y;
                            if (dx * dx + dy * dy < 90_000)
                                ds.DrawLine((float)prev.Value.X, (float)prev.Value.Y, (float)cur.Value.X, (float)cur.Value.Y, gridColor, 0.8f);
                        }
                        prev = cur;
                    }
                }
            }
        }

        private void DrawEclipticCurve(CanvasDrawingSession ds, SkyProjectionMatrix matrix)
        {
            Color eclipticColor = _isNightVision
                ? Color.FromArgb(65, 210, 20, 30)
                : Color.FromArgb(60, 255, 198, 92);
            const double eps = 23.4392911 * (Math.PI / 180.0);
            double cosE = Math.Cos(eps), sinE = Math.Sin(eps);

            ProjectedSkyPoint? prev = null;
            for (int lon = 0; lon <= 360; lon += 4)
            {
                double l = lon * (Math.PI / 180.0);
                double vx = Math.Cos(l);
                double vy = Math.Sin(l) * cosE;
                double vz = Math.Sin(l) * sinE;
                var cur = matrix.ProjectEQJUnitVector(vx, vy, vz, 150.0);
                if (prev != null && cur != null && (prev.Value.IsVisible || cur.Value.IsVisible))
                {
                    double dx = cur.Value.X - prev.Value.X;
                    double dy = cur.Value.Y - prev.Value.Y;
                    if (dx * dx + dy * dy < 90_000)
                    {
                        ds.DrawLine(
                            new Vector2((float)prev.Value.X, (float)prev.Value.Y),
                            new Vector2((float)cur.Value.X, (float)cur.Value.Y),
                            eclipticColor, 1.0f, _dashedStroke);
                    }
                }
                prev = cur;
            }
        }

        private void DrawConstellationsAndAsterisms(CanvasDrawingSession ds, SkyProjectionMatrix matrix)
        {
            var packed = _catalogRepo.PackedStars;
            if (packed.Count == 0) return;

            // Subtle IAU Borders when zoomed below 75°
            if (_fieldOfView <= 75.0)
            {
                Color borderCol = _isNightVision
                    ? Color.FromArgb(30, 180, 18, 28)
                    : Color.FromArgb(26, 110, 150, 210);
                foreach (var arc in _catalogRepo.ConstellationBorders)
                {
                    ProjectedSkyPoint? prev = null;
                    foreach (var pt in arc.Points)
                    {
                        if (pt.Count < 2) continue;
                        double raRad = pt[0] * 15.0 * (Math.PI / 180.0);
                        double decRad = pt[1] * (Math.PI / 180.0);
                        var cur = matrix.ProjectEQJUnitVector(Math.Cos(decRad) * Math.Cos(raRad), Math.Cos(decRad) * Math.Sin(raRad), Math.Sin(decRad), 120.0);
                        if (prev != null && cur != null && (prev.Value.IsVisible || cur.Value.IsVisible))
                        {
                            double dx = cur.Value.X - prev.Value.X;
                            double dy = cur.Value.Y - prev.Value.Y;
                            if (dx * dx + dy * dy < 70_000)
                            {
                                ds.DrawLine(
                                    new Vector2((float)prev.Value.X, (float)prev.Value.Y),
                                    new Vector2((float)cur.Value.X, (float)cur.Value.Y),
                                    borderCol, 0.75f, _dottedStroke);
                            }
                        }
                        prev = cur;
                    }
                }
            }

            // 88 Official IAU Constellations ([hipA, hipB] segment pairs)
            Color lineCol = _isNightVision
                ? Color.FromArgb(95, 235, 22, 34)
                : Color.FromArgb(88, 72, 168, 255);
            Color labelCol = _isNightVision
                ? Color.FromArgb(150, 235, 24, 36)
                : Color.FromArgb(145, 138, 195, 255);

            foreach (var c in _catalogRepo.Constellations)
            {
                foreach (var seg in c.Segments)
                {
                    if (seg.Count < 2) continue;
                    if (!packed.IndexByHip.TryGetValue(seg[0], out int idxA) ||
                        !packed.IndexByHip.TryGetValue(seg[1], out int idxB))
                        continue;

                    var pA = matrix.ProjectEQJUnitVector(packed.Ux[idxA], packed.Uy[idxA], packed.Uz[idxA], 160.0);
                    var pB = matrix.ProjectEQJUnitVector(packed.Ux[idxB], packed.Uy[idxB], packed.Uz[idxB], 160.0);
                    if (pA == null || pB == null || (!pA.Value.IsVisible && !pB.Value.IsVisible)) continue;

                    double dx = pB.Value.X - pA.Value.X;
                    double dy = pB.Value.Y - pA.Value.Y;
                    if (dx * dx + dy * dy < 180_000)
                    {
                        ds.DrawLine((float)pA.Value.X, (float)pA.Value.Y, (float)pB.Value.X, (float)pB.Value.Y, lineCol, 1.05f);
                    }
                }

                // Rank-aware Constellation Label
                if (_fieldOfView <= 95.0 || c.Rank <= 1)
                {
                    double raRad = c.CenterRaHours * 15.0 * (Math.PI / 180.0);
                    double decRad = c.CenterDecDeg * (Math.PI / 180.0);
                    double vx = Math.Cos(decRad) * Math.Cos(raRad);
                    double vy = Math.Cos(decRad) * Math.Sin(raRad);
                    double vz = Math.Sin(decRad);
                    double hz = matrix.H20 * vx + matrix.H21 * vy + matrix.H22 * vz;
                    if (hz > -0.05)
                    {
                        var pC = matrix.ProjectEQJUnitVector(vx, vy, vz, 40.0);
                        if (pC != null && pC.Value.IsVisible)
                        {
                            string lbl = c.NameLa.ToUpperInvariant();
                            ds.DrawText(lbl, (float)pC.Value.X - lbl.Length * 3.1f, (float)pC.Value.Y - 7f, labelCol, _constellationLabelFormat);
                            _hitTargets.Add(new HitTestableTarget
                            {
                                ObjectId = $"CONST-{c.Id}",
                                Name = $"{c.NameLa} ({c.NameEn})",
                                Subtitle = $"IAU Constellation • {c.Code}",
                                Category = "Constellation",
                                ScreenX = (float)pC.Value.X,
                                ScreenY = (float)pC.Value.Y,
                                HitRadius = 22f,
                                Priority = 1,
                                Payload = c
                            });
                        }
                    }
                }
            }

            // 14 Seasonal Asterisms
            Color astCol = _isNightVision
                ? Color.FromArgb(65, 255, 45, 58)
                : Color.FromArgb(64, 255, 214, 112);
            foreach (var ast in _catalogRepo.Asterisms)
            {
                foreach (var seg in ast.Segments)
                {
                    if (seg.Count < 2) continue;
                    if (!packed.IndexByHip.TryGetValue(seg[0], out int idxA) ||
                        !packed.IndexByHip.TryGetValue(seg[1], out int idxB))
                        continue;
                    var pA = matrix.ProjectEQJUnitVector(packed.Ux[idxA], packed.Uy[idxA], packed.Uz[idxA], 160.0);
                    var pB = matrix.ProjectEQJUnitVector(packed.Ux[idxB], packed.Uy[idxB], packed.Uz[idxB], 160.0);
                    if (pA == null || pB == null || (!pA.Value.IsVisible && !pB.Value.IsVisible)) continue;
                    double dx = pB.Value.X - pA.Value.X;
                    double dy = pB.Value.Y - pA.Value.Y;
                    if (dx * dx + dy * dy < 180_000)
                    {
                        ds.DrawLine(
                            new Vector2((float)pA.Value.X, (float)pA.Value.Y),
                            new Vector2((float)pB.Value.X, (float)pB.Value.Y),
                            astCol, 0.9f, _dashedStroke);
                    }
                }
            }
        }

        private void DrawPackedHipparcosStars(CanvasDrawingSession ds, SkyProjectionMatrix matrix, DateTime simUtc)
        {
            var packed = _catalogRepo.PackedStars;
            if (packed.Count == 0) return;

            var sun = _bodies.FirstOrDefault(b => b.Body == CelestialBody.Sun);
            double daylightDim = (_showAtmosphere && sun != null && sun.Altitude > -4.0)
                ? Math.Clamp((4.0 - sun.Altitude) / 8.0, 0.08, 1.0)
                : 1.0;

            double nelm = Math.Max(3.6, _stargazing.LimitingMagnitude);
            double zoomGain = 5.0 * Math.Log10(Math.Max(1.0, 68.0 / _fieldOfView));
            float magCutoff = (float)Math.Min(7.1, nelm + zoomGain);
            float labelMagCutoff = _fieldOfView <= 8.0 ? 4.8f : (_fieldOfView <= 30.0 ? 3.2f : 1.95f);
            double twinklePhase = simUtc.Millisecond * 0.00628318;

            int count = packed.Count;
            var ux = packed.Ux;
            var uy = packed.Uy;
            var uz = packed.Uz;
            var vMag = packed.VMag;
            var colors = packed.PackedArgbColors;
            var hips = packed.HipIds;

            for (int i = 0; i < count; i++)
            {
                float mag = vMag[i];
                if (mag > magCutoff) continue;

                float vx = ux[i], vy = uy[i], vz = uz[i];
                var proj = matrix.ProjectEQJUnitVector(vx, vy, vz, 16.0);
                if (proj == null || !proj.Value.IsVisible) continue;

                double sinAlt = matrix.H20 * vx + matrix.H21 * vy + matrix.H22 * vz;
                if (sinAlt < -0.06) continue; // Below horizon

                // Pogson photometric flux sizing + low-altitude airmass scintillation
                double flux = Math.Pow(10.0, -0.4 * (mag - 1.0));
                float radius = (float)Math.Clamp(0.65 + 1.55 * Math.Pow(flux, 0.36), 0.55, 5.2);

                double twinkle = 1.0;
                if (sinAlt > 0.0 && sinAlt < 0.34 && mag < 3.5f)
                {
                    double airmass = (0.34 - sinAlt) / 0.34;
                    twinkle = 1.0 - 0.22 * airmass * (0.5 + 0.5 * Math.Sin(twinklePhase + (hips[i] % 17) * 0.7));
                }

                double alphaNorm = Math.Clamp((magCutoff - mag + 0.65) / 2.2, 0.16, 1.0) * daylightDim * twinkle;
                byte alpha = (byte)Math.Clamp((int)Math.Round(alphaNorm * 255.0), 18, 255);

                Color starColor;
                if (_isNightVision)
                {
                    starColor = Color.FromArgb(alpha, 255, (byte)Math.Clamp((int)(24 + radius * 8), 24, 58), (byte)Math.Clamp((int)(36 + radius * 8), 36, 70));
                }
                else
                {
                    uint argb = colors[i];
                    byte r = (byte)((argb >> 16) & 0xFF);
                    byte g = (byte)((argb >> 8) & 0xFF);
                    byte b = (byte)(argb & 0xFF);
                    starColor = Color.FromArgb(alpha, r, g, b);
                }

                float sx = (float)proj.Value.X;
                float sy = (float)proj.Value.Y;

                // Soft HDR bloom halo for bright stars
                if (mag < 2.1f && alpha > 60)
                {
                    byte haloA = (byte)Math.Max(10, alpha / 5);
                    ds.FillCircle(sx, sy, radius * 2.8f, Color.FromArgb(haloA, starColor.R, starColor.G, starColor.B));
                    if (mag < 0.6f)
                    {
                        ds.FillCircle(sx, sy, radius * 4.6f, Color.FromArgb((byte)Math.Max(6, alpha / 10), starColor.R, starColor.G, starColor.B));
                    }
                }

                ds.FillCircle(sx, sy, radius, starColor);

                int hip = hips[i];
                if (mag <= 4.3f && _catalogRepo.StarDesignationsByHip.TryGetValue(hip, out var desig))
                {
                    if (mag <= labelMagCutoff && !string.IsNullOrWhiteSpace(desig.Name))
                    {
                        Color txtCol = _isNightVision
                            ? Color.FromArgb(200, 255, 36, 48)
                            : Color.FromArgb(205, 226, 236, 255);
                        ds.DrawText(desig.Name!, sx + radius + 4f, sy - 7f, txtCol, _starLabelFormat);
                    }

                    _hitTargets.Add(new HitTestableTarget
                    {
                        ObjectId = $"HIP-{hip}",
                        Name = desig.PrimaryLabel,
                        Subtitle = $"Star • mag {mag:F2}",
                        Category = "Star",
                        ScreenX = sx,
                        ScreenY = sy,
                        HitRadius = Math.Max(11f, radius + 7f),
                        Priority = 3,
                        Payload = new CosmosStar
                        {
                            Hip = hip,
                            Name = desig.PrimaryLabel,
                            Bayer = desig.Bayer,
                            Constellation = desig.Constellation ?? "",
                            RaHours = packed.RaHours[i],
                            DecDegrees = packed.DecDegrees[i],
                            Mag = mag,
                            ColorIndexBV = packed.Bv[i]
                        }
                    });
                }
            }
        }

        private void DrawDeepSkyObjects(CanvasDrawingSession ds, SkyProjectionMatrix matrix)
        {
            double magLimit = _fieldOfView <= 8.0 ? 11.5 : (_fieldOfView <= 35.0 ? 8.8 : 6.6);
            foreach (var dso in _catalogRepo.DeepSkyObjects)
            {
                if (dso.VisualMag > magLimit) continue;
                var uv = dso.UnitVectorJ2000;
                double sinAlt = matrix.H20 * uv.Ux + matrix.H21 * uv.Uy + matrix.H22 * uv.Uz;
                if (sinAlt < -0.02) continue;

                var proj = matrix.ProjectEQJUnitVector(uv.Ux, uv.Uy, uv.Uz, 24.0);
                if (proj == null || !proj.Value.IsVisible) continue;

                float sx = (float)proj.Value.X;
                float sy = (float)proj.Value.Y;
                float r = (float)Math.Clamp(5.0 + (9.5 - dso.VisualMag) * 1.1, 4.5, 13.0);

                Color dsoCol = _isNightVision
                    ? Color.FromArgb(200, 255, 28, 40)
                    : (dso.TypeCode switch
                    {
                        "GAL" => Color.FromArgb(205, 255, 178, 102),
                        "NEB" or "PN" or "SNR" => Color.FromArgb(205, 232, 118, 255),
                        "GC" => Color.FromArgb(205, 255, 224, 115),
                        _ => Color.FromArgb(205, 98, 228, 255)
                    });

                if (dso.TypeCode == "GAL")
                {
                    var oldT = ds.Transform;
                    ds.Transform = Matrix3x2.CreateRotation(-0.48f, new Vector2(sx, sy)) * oldT;
                    ds.DrawEllipse(sx, sy, r * 1.35f, r * 0.62f, dsoCol, 1.2f);
                    ds.Transform = oldT;
                }
                else if (dso.TypeCode == "GC")
                {
                    ds.DrawCircle(sx, sy, r, dsoCol, 1.2f);
                    ds.DrawLine(sx - r, sy, sx + r, sy, dsoCol, 0.9f);
                    ds.DrawLine(sx, sy - r, sx, sy + r, dsoCol, 0.9f);
                }
                else if (dso.TypeCode == "OC")
                {
                    ds.DrawCircle(new Vector2(sx, sy), r, dsoCol, 1.2f, _dottedStroke);
                }
                else
                {
                    ds.DrawRectangle(sx - r * 0.85f, sy - r * 0.85f, r * 1.7f, r * 1.7f, dsoCol, 1.2f);
                }

                if (_fieldOfView <= 55.0 || dso.VisualMag <= 5.2)
                {
                    ds.DrawText(dso.Id, sx + r + 4f, sy - 7f, dsoCol, _starLabelFormat);
                }

                _hitTargets.Add(new HitTestableTarget
                {
                    ObjectId = dso.Id,
                    Name = $"{dso.Id} · {dso.Name}",
                    Subtitle = $"{dso.Type} • mag {dso.VisualMag:F1}",
                    Category = "Deep-Sky Object",
                    ScreenX = sx,
                    ScreenY = sy,
                    HitRadius = Math.Max(13f, r + 6f),
                    Priority = 4,
                    Payload = dso
                });
            }
        }

        private void DrawMeteorShowerRadiants(CanvasDrawingSession ds, SkyProjectionMatrix matrix, DateTime simUtc)
        {
            Color radCol = _isNightVision
                ? Color.FromArgb(190, 255, 32, 44)
                : Color.FromArgb(190, 92, 242, 195);

            foreach (var shower in _catalogRepo.MeteorShowers)
            {
                if (!shower.IsActiveOn(simUtc)) continue;
                double raRad = shower.RadiantRaHours * 15.0 * (Math.PI / 180.0);
                double decRad = shower.RadiantDecDeg * (Math.PI / 180.0);
                double vx = Math.Cos(decRad) * Math.Cos(raRad);
                double vy = Math.Cos(decRad) * Math.Sin(raRad);
                double vz = Math.Sin(decRad);
                if (matrix.H20 * vx + matrix.H21 * vy + matrix.H22 * vz < 0.0) continue;

                var proj = matrix.ProjectEQJUnitVector(vx, vy, vz, 30.0);
                if (proj == null || !proj.Value.IsVisible) continue;

                float sx = (float)proj.Value.X;
                float sy = (float)proj.Value.Y;
                for (int k = 0; k < 6; k++)
                {
                    double a = k * (Math.PI / 3.0);
                    ds.DrawLine(
                        sx + (float)(4.0 * Math.Cos(a)), sy + (float)(4.0 * Math.Sin(a)),
                        sx + (float)(10.5 * Math.Cos(a)), sy + (float)(10.5 * Math.Sin(a)),
                        radCol, 1.1f);
                }
                ds.DrawText($"{shower.Name} ({shower.Zhr}/h)", sx + 12f, sy - 7f, radCol, _starLabelFormat);

                _hitTargets.Add(new HitTestableTarget
                {
                    ObjectId = $"SHOWER-{shower.Id}",
                    Name = $"{shower.Name} Meteor Shower",
                    Subtitle = $"Active Radiant • ZHR {shower.Zhr}/hr",
                    Category = "Meteor Shower",
                    ScreenX = sx,
                    ScreenY = sy,
                    HitRadius = 15f,
                    Priority = 4,
                    Payload = shower
                });
            }
        }

        private void DrawSolarSystemBodies(CanvasDrawingSession ds, SkyProjectionMatrix matrix)
        {
            foreach (var body in _bodies)
            {
                if (body.Altitude < -4.0) continue;
                var proj = matrix.ProjectHorizontal(body.Azimuth, body.Altitude, 40.0);
                if (proj == null || !proj.Value.IsVisible) continue;

                float sx = (float)proj.Value.X;
                float sy = (float)proj.Value.Y;

                Color baseColor = _isNightVision
                    ? Color.FromArgb(255, 255, 24, 36)
                    : (body.Body switch
                    {
                        CelestialBody.Sun => Color.FromArgb(255, 255, 214, 96),
                        CelestialBody.Moon => Color.FromArgb(255, 238, 241, 248),
                        CelestialBody.Mercury => Color.FromArgb(255, 198, 204, 216),
                        CelestialBody.Venus => Color.FromArgb(255, 255, 244, 214),
                        CelestialBody.Mars => Color.FromArgb(255, 255, 114, 92),
                        CelestialBody.Jupiter => Color.FromArgb(255, 246, 198, 138),
                        CelestialBody.Saturn => Color.FromArgb(255, 244, 218, 146),
                        CelestialBody.Uranus => Color.FromArgb(255, 132, 234, 246),
                        CelestialBody.Neptune => Color.FromArgb(255, 104, 156, 255),
                        _ => Colors.White
                    });

                float zoomScale = (float)Math.Clamp(45.0 / Math.Max(1.0, _fieldOfView), 0.9, 3.4);
                float radius = (body.Body == CelestialBody.Sun || body.Body == CelestialBody.Moon)
                    ? 8.5f * zoomScale
                    : 5.0f * Math.Min(2.2f, zoomScale);

                if (body.Body == CelestialBody.Moon)
                {
                    DrawRealisticMoonDisc(ds, sx, sy, radius, _moonPhase);
                }
                else if (body.Body == CelestialBody.Saturn)
                {
                    ds.FillCircle(sx, sy, radius * 2.1f, Color.FromArgb(35, baseColor.R, baseColor.G, baseColor.B));
                    var oldT = ds.Transform;
                    ds.Transform = Matrix3x2.CreateRotation(-0.18f, new Vector2(sx, sy)) * oldT;
                    float tiltRatio = (float)Math.Clamp(Math.Abs(Math.Sin(_saturnRingTiltDeg * (Math.PI / 180.0))), 0.14, 0.52);
                    ds.DrawEllipse(sx, sy, radius * 2.35f, radius * 2.35f * tiltRatio, baseColor, 1.6f);
                    ds.Transform = oldT;
                    ds.FillCircle(sx, sy, radius, baseColor);
                }
                else if (body.Body == CelestialBody.Jupiter)
                {
                    ds.FillCircle(sx, sy, radius * 2.2f, Color.FromArgb(40, baseColor.R, baseColor.G, baseColor.B));
                    ds.FillCircle(sx, sy, radius, baseColor);

                    // Live 4 Galilean Moons in Binocular/Telescope Zoom (FOV <= 12°)
                    if (_fieldOfView <= 12.0)
                    {
                        float jupRadPx = Math.Max(radius, (float)((0.006 * matrix.Scale)));
                        Color moonCol = _isNightVision
                            ? Color.FromArgb(235, 255, 36, 48)
                            : Color.FromArgb(235, 224, 238, 255);
                        foreach (var gm in _jupiterMoons.All)
                        {
                            if (gm.IsOcculted) continue;
                            float mx = sx + (float)(gm.XRadius * jupRadPx * 0.55);
                            float my = sy - (float)(gm.YRadius * jupRadPx * 0.55);
                            ds.FillCircle(mx, my, 2.2f, moonCol);
                            if (_fieldOfView <= 4.0)
                            {
                                ds.DrawText(gm.Name, mx + 4f, my - 6f, moonCol, _starLabelFormat);
                            }
                        }
                    }
                }
                else
                {
                    ds.FillCircle(sx, sy, radius * 2.4f, Color.FromArgb(45, baseColor.R, baseColor.G, baseColor.B));
                    ds.FillCircle(sx, sy, radius, baseColor);
                }

                string label = body.Body.DisplayName();
                ds.DrawText(label, sx + radius + 5f, sy - 8f, baseColor, _planetLabelFormat);

                _hitTargets.Add(new HitTestableTarget
                {
                    ObjectId = $"BODY-{body.Body}",
                    Name = label,
                    Subtitle = $"{label} • Alt {body.Altitude:+0.0;-0.0}° • mag {body.Magnitude?.ToString("F1", CultureInfo.InvariantCulture) ?? "--"}",
                    Category = "Planet",
                    ScreenX = sx,
                    ScreenY = sy,
                    HitRadius = Math.Max(15f, radius + 8f),
                    Priority = 6,
                    Payload = body
                });
            }
        }

        private void DrawRealisticMoonDisc(CanvasDrawingSession ds, float sx, float sy, float r, MoonPhaseInfo moon)
        {
            Color litColor = _isNightVision
                ? Color.FromArgb(245, 255, 26, 38)
                : Color.FromArgb(248, 240, 242, 248);
            Color earthshineColor = _isNightVision
                ? Color.FromArgb(255, 36, 3, 5)
                : Color.FromArgb(255, 26, 32, 46);
            Color glowColor = _isNightVision
                ? Color.FromArgb(38, 255, 24, 36)
                : Color.FromArgb(42, 215, 228, 255);

            ds.FillCircle(sx, sy, r * 2.2f, glowColor);
            ds.FillCircle(sx, sy, r, earthshineColor);

            float k = (float)Math.Clamp(moon.IlluminatedFraction, 0.0, 1.0);
            if (k > 0.01f)
            {
                // Rotate so bright limb points along BrightLimbAngleDegrees (measured clockwise from local up; +X right = 90°)
                float rotRad = (float)((moon.BrightLimbAngleDegrees - 90.0) * (Math.PI / 180.0));
                var oldT = ds.Transform;
                ds.Transform = Matrix3x2.CreateRotation(rotRad, new Vector2(sx, sy)) * oldT;

                using var pb = new CanvasPathBuilder(ds);
                const int steps = 28;
                float termScale = 2.0f * k - 1.0f; // -1 crescent -> 0 quarter -> +1 full
                for (int i = 0; i <= steps; i++)
                {
                    double a = -Math.PI * 0.5 + Math.PI * i / steps;
                    float px = sx + r * (float)Math.Cos(a);
                    float py = sy + r * (float)Math.Sin(a);
                    if (i == 0) pb.BeginFigure(px, py);
                    else pb.AddLine(px, py);
                }
                for (int i = steps; i >= 0; i--)
                {
                    double a = -Math.PI * 0.5 + Math.PI * i / steps;
                    float px = sx - r * termScale * (float)Math.Cos(a);
                    float py = sy + r * (float)Math.Sin(a);
                    pb.AddLine(px, py);
                }
                pb.EndFigure(CanvasFigureLoop.Closed);
                using var litGeom = CanvasGeometry.CreatePath(pb);
                ds.FillGeometry(litGeom, litColor);

                ds.Transform = oldT;
            }
            ds.DrawCircle(sx, sy, r, Color.FromArgb(90, litColor.R, litColor.G, litColor.B), 0.9f);
        }

        private void DrawIssAndPassArc(CanvasDrawingSession ds, SkyProjectionMatrix matrix)
        {
            // Upcoming or active pass trajectory arc (gold when sunlit, dashed crimson/slate in umbra)
            var nextPass = _liveBundle?.IssPasses?.FirstOrDefault();
            if (nextPass != null && nextPass.Trajectory.Count > 1)
            {
                ProjectedSkyPoint? prev = null;
                bool prevSunlit = true;
                foreach (var sample in nextPass.Trajectory)
                {
                    var cur = matrix.ProjectHorizontal(sample.AzimuthDegrees, sample.AltitudeDegrees, 140.0);
                    if (prev != null && cur != null && (prev.Value.IsVisible || cur.Value.IsVisible))
                    {
                        double dx = cur.Value.X - prev.Value.X;
                        double dy = cur.Value.Y - prev.Value.Y;
                        if (dx * dx + dy * dy < 80_000)
                        {
                            Color arcCol = _isNightVision
                                ? Color.FromArgb(sample.IsSunlit ? (byte)185 : (byte)85, 255, 24, 36)
                                : (sample.IsSunlit
                                    ? Color.FromArgb(190, 255, 209, 102)
                                    : Color.FromArgb(110, 140, 160, 195));
                            if (sample.IsSunlit && prevSunlit)
                            {
                                ds.DrawLine((float)prev.Value.X, (float)prev.Value.Y, (float)cur.Value.X, (float)cur.Value.Y, arcCol, 1.5f);
                            }
                            else
                            {
                                ds.DrawLine(
                                    new Vector2((float)prev.Value.X, (float)prev.Value.Y),
                                    new Vector2((float)cur.Value.X, (float)cur.Value.Y),
                                    arcCol, 1.2f, _dashedStroke);
                            }
                        }
                    }
                    prev = cur;
                    prevSunlit = sample.IsSunlit;
                }
            }

            if (_issLivePos != null && _issLivePos.AltitudeDegrees > -5.0)
            {
                var p = matrix.ProjectHorizontal(_issLivePos.AzimuthDegrees, _issLivePos.AltitudeDegrees, 40.0);
                if (p != null && p.Value.IsVisible)
                {
                    float sx = (float)p.Value.X;
                    float sy = (float)p.Value.Y;
                    Color issCol = _isNightVision
                        ? Color.FromArgb(255, 255, 24, 36)
                        : (_issLivePos.IsSunlit ? Color.FromArgb(255, 255, 214, 92) : Color.FromArgb(220, 165, 195, 235));

                    ds.DrawCircle(sx, sy, 9f, issCol, 1.4f);
                    ds.FillRectangle(sx - 2.5f, sy - 2.5f, 5f, 5f, issCol);
                    ds.DrawLine(sx - 9f, sy, sx - 4f, sy, issCol, 1.6f);
                    ds.DrawLine(sx + 4f, sy, sx + 9f, sy, issCol, 1.6f);
                    ds.DrawText($"ISS ({(_issLivePos.IsSunlit ? "Sunlit" : "Umbra")})", sx + 12f, sy - 8f, issCol, _planetLabelFormat);

                    _hitTargets.Add(new HitTestableTarget
                    {
                        ObjectId = "SAT-25544",
                        Name = "ISS (Zarya)",
                        Subtitle = $"NORAD 25544 • Alt {_issLivePos.AltitudeDegrees:+0.0;-0.0}° • {_issLivePos.RangeKm:F0} km",
                        Category = "Satellite",
                        ScreenX = sx,
                        ScreenY = sy,
                        HitRadius = 16f,
                        Priority = 7,
                        Payload = _issLivePos
                    });
                }
            }
        }

        private void DrawHorizonAndCompassBeacons(ICanvasResourceCreator creator, CanvasDrawingSession ds, SkyProjectionMatrix matrix, float w, float h)
        {
            Color horizonStroke = _isNightVision
                ? Color.FromArgb(175, 255, 24, 36)
                : Color.FromArgb(165, 0, 229, 255);
            Color groundFill = _isNightVision
                ? Color.FromArgb(236, 7, 0, 1)
                : Color.FromArgb(236, 4, 7, 15);

            if (_isZenithPlanisphereLocked)
            {
                // In 360° Zenith Planisphere mode, alt=0° maps to exact stereographic radius = Scale * tan(90°/2) = Scale!
                // Zooming smoothly scales the entire horizon circle with FOV!
                float rHorizon = (float)matrix.Scale;
                float cx = (float)matrix.HalfWidth;
                float cy = (float)matrix.HalfHeight;

                // Mask exterior ground outside the 360° horizon ring using geometry combine
                using var fullRect = CanvasGeometry.CreateRectangle(creator, 0, 0, w, h);
                using var skyDisc = CanvasGeometry.CreateCircle(creator, cx, cy, rHorizon);
                using var maskGeom = fullRect.CombineWith(skyDisc, Matrix3x2.Identity, CanvasGeometryCombine.Exclude);
                ds.FillGeometry(maskGeom, groundFill);
                ds.DrawCircle(cx, cy, rHorizon, horizonStroke, 1.6f);
            }
            else
            {
                // Curved 3D Topocentric Horizon Line + Ground Apron (strictly forward camera hemisphere, left-to-right)
                var pts = new List<Vector2>(96);
                float lastX = float.NegativeInfinity;
                for (int offset = -102; offset <= 102; offset += 3)
                {
                    double az = (_cameraAzimuth + offset + 360.0) % 360.0;
                    double azRad = az * (Math.PI / 180.0);
                    double cz = matrix.Fx * Math.Cos(azRad) + matrix.Fy * (-Math.Sin(azRad));
                    if (cz <= 0.05) continue;

                    var p = matrix.ProjectHorizontal(az, 0.0, Math.Max(w, h) * 0.9);
                    if (p != null && (float)p.Value.X > lastX)
                    {
                        lastX = (float)p.Value.X;
                        pts.Add(new Vector2((float)p.Value.X, (float)p.Value.Y));
                    }
                }

                for (int i = 1; i < pts.Count; i++)
                {
                    float dx = pts[i].X - pts[i - 1].X;
                    float dy = pts[i].Y - pts[i - 1].Y;
                    if (dx > 0f && dx * dx + dy * dy < 160_000f)
                    {
                        // Subtle ground fill strip below visible horizon segment
                        float x0 = pts[i - 1].X, y0 = pts[i - 1].Y;
                        float x1 = pts[i].X, y1 = pts[i].Y;
                        if (_cameraAltitude < 65.0 && ((x0 >= -200 && x0 <= w + 200) || (x1 >= -200 && x1 <= w + 200)))
                        {
                            using var pb = new CanvasPathBuilder(creator);
                            pb.BeginFigure(x0, y0);
                            pb.AddLine(x1, y1);
                            pb.AddLine(x1, Math.Max(h + 40f, y1 + 400f));
                            pb.AddLine(x0, Math.Max(h + 40f, y0 + 400f));
                            pb.EndFigure(CanvasFigureLoop.Closed);
                            using var g = CanvasGeometry.CreatePath(pb);
                            ds.FillGeometry(g, groundFill);
                        }
                        ds.DrawLine(x0, y0, x1, y1, horizonStroke, 1.6f);
                    }
                }
            }

            // 8 Cardinal & Intercardinal Beacons along the Horizon
            (double Az, string Label, bool Primary)[] cardinals =
            {
                (0, "N", true), (45, "NE", false), (90, "E", true), (135, "SE", false),
                (180, "S", true), (225, "SW", false), (270, "W", true), (315, "NW", false)
            };

            foreach (var c in cardinals)
            {
                var p = matrix.ProjectHorizontal(c.Az, 0.0, 32.0);
                if (p == null || !p.Value.IsVisible) continue;

                float bx = (float)p.Value.X;
                float by = (float)p.Value.Y;
                float pillR = c.Primary ? 13f : 10.5f;

                Color pillBg = _isNightVision
                    ? Color.FromArgb(220, 26, 2, 4)
                    : Color.FromArgb(220, 7, 14, 28);
                Color pillBorder = _isNightVision
                    ? Color.FromArgb(220, 255, 24, 36)
                    : (c.Label == "N" ? Color.FromArgb(240, 255, 108, 108) : Color.FromArgb(210, 0, 229, 255));
                Color pillTxt = _isNightVision
                    ? Color.FromArgb(255, 255, 24, 36)
                    : (c.Primary ? Colors.White : Color.FromArgb(215, 200, 224, 255));

                ds.FillCircle(bx, by, pillR, pillBg);
                ds.DrawCircle(bx, by, pillR, pillBorder, c.Primary ? 1.4f : 1.0f);
                ds.DrawText(c.Label, bx, by, pillTxt, _cardinalLabelFormat);
            }
        }

        private void DrawReticles(CanvasDrawingSession ds, SkyProjectionMatrix matrix, float w, float h)
        {
            float cx = w * 0.5f;
            float cy = h * 0.5f;
            Color crossCol = _isNightVision
                ? Color.FromArgb(115, 255, 24, 36)
                : Color.FromArgb(95, 255, 255, 255);

            ds.DrawLine(cx - 14f, cy, cx - 4f, cy, crossCol, 1.1f);
            ds.DrawLine(cx + 4f, cy, cx + 14f, cy, crossCol, 1.1f);
            ds.DrawLine(cx, cy - 14f, cx, cy - 4f, crossCol, 1.1f);
            ds.DrawLine(cx, cy + 4f, cx, cy + 14f, crossCol, 1.1f);

            // Selected Target Lock Bracket
            if (_selectedTarget != null)
            {
                var selPt = ProjectTargetToScreen(_selectedTarget, matrix);
                if (selPt != null && selPt.Value.IsVisible)
                {
                    float tx = (float)selPt.Value.X;
                    float ty = (float)selPt.Value.Y;
                    Color lockCol = _isNightVision
                        ? Color.FromArgb(245, 255, 24, 36)
                        : Color.FromArgb(245, 0, 229, 255);
                    ds.DrawCircle(tx, ty, 16f, lockCol, 1.5f);
                    ds.DrawCircle(new Vector2(tx, ty), 22f, Color.FromArgb(120, lockCol.R, lockCol.G, lockCol.B), 1.0f, _dashedStroke);
                }
            }

            // Desktop Hover Reticle Ring
            if (_hoveredTarget != null)
            {
                Color hovCol = _isNightVision
                    ? Color.FromArgb(190, 255, 45, 58)
                    : Color.FromArgb(190, 255, 214, 102);
                ds.DrawCircle(_hoveredTarget.ScreenX, _hoveredTarget.ScreenY, _hoveredTarget.HitRadius, hovCol, 1.2f);
            }
        }

        private ProjectedSkyPoint? ProjectTargetToScreen(object target, SkyProjectionMatrix matrix)
        {
            if (target is CelestialCoordinates b)
            {
                var live = _bodies.FirstOrDefault(x => x.Body == b.Body) ?? b;
                return matrix.ProjectHorizontal(live.Azimuth, live.Altitude, 60.0);
            }
            if (target is LiveSatellitePosition)
            {
                return _issLivePos != null ? matrix.ProjectHorizontal(_issLivePos.AzimuthDegrees, _issLivePos.AltitudeDegrees, 60.0) : null;
            }
            if (target is CosmosStar s)
            {
                double ra = s.RaHours * 15.0 * (Math.PI / 180.0);
                double dec = s.DecDegrees * (Math.PI / 180.0);
                return matrix.ProjectEQJUnitVector(Math.Cos(dec) * Math.Cos(ra), Math.Cos(dec) * Math.Sin(ra), Math.Sin(dec), 60.0);
            }
            if (target is CosmosDeepSkyObject d)
            {
                var uv = d.UnitVectorJ2000;
                return matrix.ProjectEQJUnitVector(uv.Ux, uv.Uy, uv.Uz, 60.0);
            }
            if (target is CosmosConstellation c)
            {
                double ra = c.CenterRaHours * 15.0 * (Math.PI / 180.0);
                double dec = c.CenterDecDeg * (Math.PI / 180.0);
                return matrix.ProjectEQJUnitVector(Math.Cos(dec) * Math.Cos(ra), Math.Cos(dec) * Math.Sin(ra), Math.Sin(dec), 60.0);
            }
            if (target is MeteorShower m)
            {
                double ra = m.RadiantRaHours * 15.0 * (Math.PI / 180.0);
                double dec = m.RadiantDecDeg * (Math.PI / 180.0);
                return matrix.ProjectEQJUnitVector(Math.Cos(dec) * Math.Cos(ra), Math.Cos(dec) * Math.Sin(ra), Math.Sin(dec), 60.0);
            }
            return null;
        }

        // ── Pointer Pan, Cursor-Centered Wheel Zoom, Hover & Spatial Selection ──

        private void SkyCanvas_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            _isDragging = true;
            _dragMoved = false;
            _dragStartPos = e.GetCurrentPoint(SkyCanvas).Position;
            _lastPointerPos = _dragStartPos;
            SkyCanvas.CapturePointer(e.Pointer);
            this.Focus(FocusState.Programmatic);
        }

        private void SkyCanvas_PointerMoved(object sender, PointerRoutedEventArgs e)
        {
            var pos = e.GetCurrentPoint(SkyCanvas).Position;
            _hoverPointerPos = pos;

            if (_isDragging)
            {
                double dx = pos.X - _lastPointerPos.X;
                double dy = pos.Y - _lastPointerPos.Y;
                if (Math.Abs(pos.X - _dragStartPos.X) > 4.0 || Math.Abs(pos.Y - _dragStartPos.Y) > 4.0)
                    _dragMoved = true;

                _lastPointerPos = pos;
                double degPerPx = Math.Max(0.015, _fieldOfView / Math.Max(320.0, Math.Min(SkyCanvas.ActualWidth, SkyCanvas.ActualHeight)));

                _cameraAzimuth = ((_cameraAzimuth - dx * degPerPx) % 360.0 + 360.0) % 360.0;
                if (!_isZenithPlanisphereLocked)
                {
                    _cameraAltitude = Math.Clamp(_cameraAltitude + dy * degPerPx, -15.0, 90.0);
                }

                UpdateCameraHudOnly();
                SkyCanvas.Invalidate();
                return;
            }

            // Desktop Hover Hit-Test
            var hit = FindHitTarget(pos.X, pos.Y);
            if (hit != _hoveredTarget)
            {
                _hoveredTarget = hit;
                if (hit != null)
                {
                    HoverTitleText.Text = hit.Name;
                    HoverSubtitleText.Text = hit.Subtitle;
                    HoverTooltipBorder.Margin = new Thickness(
                        Math.Clamp(pos.X + 14.0, 12.0, Math.Max(12.0, SkyCanvas.ActualWidth - 220.0)),
                        Math.Clamp(pos.Y - 18.0, 52.0, Math.Max(52.0, SkyCanvas.ActualHeight - 90.0)),
                        0, 0);
                    HoverTooltipBorder.Visibility = Visibility.Visible;
                }
                else
                {
                    HoverTooltipBorder.Visibility = Visibility.Collapsed;
                }
                SkyCanvas.Invalidate();
            }
        }

        private void SkyCanvas_PointerReleased(object sender, PointerRoutedEventArgs e)
        {
            var pos = e.GetCurrentPoint(SkyCanvas).Position;
            if (_isDragging)
            {
                _isDragging = false;
                SkyCanvas.ReleasePointerCapture(e.Pointer);
                if (!_dragMoved)
                {
                    var hit = FindHitTarget(pos.X, pos.Y);
                    if (hit != null)
                    {
                        SelectTarget(hit.Payload, centerCamera: false);
                        SkyCanvas.Invalidate();
                    }
                }
            }
        }

        private void SkyCanvas_PointerExited(object sender, PointerRoutedEventArgs e)
        {
            _hoveredTarget = null;
            HoverTooltipBorder.Visibility = Visibility.Collapsed;
            SkyCanvas.Invalidate();
        }

        private void SkyCanvas_PointerWheelChanged(object sender, PointerRoutedEventArgs e)
        {
            var pt = e.GetCurrentPoint(SkyCanvas);
            int delta = pt.Properties.MouseWheelDelta;
            if (delta == 0) return;

            double w = Math.Max(64.0, SkyCanvas.ActualWidth);
            double h = Math.Max(64.0, SkyCanvas.ActualHeight);
            double renderAlt = _isZenithPlanisphereLocked ? 90.0 : _cameraAltitude;

            // Unproject sky direction under cursor before zoom
            var beforeMatrix = _astronomyService.MakeProjectionMatrix(
                _latitude, _longitude, _elevationMeters, CurrentSimulationUtc,
                _cameraAzimuth, renderAlt, 0.0, _fieldOfView, w, h);
            var anchor = beforeMatrix.UnprojectToHorizontal(pt.Position.X, pt.Position.Y);

            double factor = delta > 0 ? 0.86 : 1.16;
            _fieldOfView = Math.Clamp(_fieldOfView * factor, 0.5, 120.0);

            // Re-anchor cursor sky point smoothly when not locked to Zenith
            if (!_isZenithPlanisphereLocked && anchor.HasValue)
            {
                var afterMatrix = _astronomyService.MakeProjectionMatrix(
                    _latitude, _longitude, _elevationMeters, CurrentSimulationUtc,
                    _cameraAzimuth, _cameraAltitude, 0.0, _fieldOfView, w, h);
                var afterCursor = afterMatrix.UnprojectToHorizontal(pt.Position.X, pt.Position.Y);
                if (afterCursor.HasValue)
                {
                    double dAz = anchor.Value.AzimuthDeg - afterCursor.Value.AzimuthDeg;
                    if (dAz > 180.0) dAz -= 360.0;
                    if (dAz < -180.0) dAz += 360.0;
                    _cameraAzimuth = ((_cameraAzimuth + dAz * 0.65) % 360.0 + 360.0) % 360.0;
                    _cameraAltitude = Math.Clamp(_cameraAltitude + (anchor.Value.AltitudeDeg - afterCursor.Value.AltitudeDeg) * 0.65, -15.0, 90.0);
                }
            }

            UpdateZoomPresetHighlight();
            UpdateCameraHudOnly();
            SkyCanvas.Invalidate();
            e.Handled = true;
        }

        private void SkyCanvas_DoubleTapped(object sender, DoubleTappedRoutedEventArgs e)
        {
            var pos = e.GetPosition(SkyCanvas);
            var hit = FindHitTarget(pos.X, pos.Y);
            if (hit != null)
            {
                SelectTarget(hit.Payload, centerCamera: true);
            }

            _fieldOfView = _fieldOfView > 25.0 ? 8.0 : (_fieldOfView > 3.0 ? 1.5 : 65.0);
            UpdateZoomPresetHighlight();
            UpdateCameraHudOnly();
            SkyCanvas.Invalidate();
        }

        private HitTestableTarget? FindHitTarget(double x, double y)
        {
            HitTestableTarget? best = null;
            double bestScore = double.MaxValue;
            foreach (var t in _hitTargets)
            {
                double dx = x - t.ScreenX;
                double dy = y - t.ScreenY;
                double d = Math.Sqrt(dx * dx + dy * dy);
                if (d <= t.HitRadius)
                {
                    double score = d - t.Priority * 2.2;
                    if (score < bestScore)
                    {
                        bestScore = score;
                        best = t;
                    }
                }
            }
            return best;
        }

        // ── Keyboard Shortcuts (`Space`, `[`/`]`, `L`, `N`, `G`, `C`, `A`, `Z`, `+/-`, `Esc`) ─

        private void CosmosDetailPage_KeyDown(object sender, KeyRoutedEventArgs e)
        {
            if (FocusManager.GetFocusedElement(this.XamlRoot) is TextBox) return;

            switch (e.Key)
            {
                case VirtualKey.Escape:
                    if (_selectedTarget != null)
                    {
                        _selectedTarget = null;
                        SkyCanvas.Invalidate();
                    }
                    else
                    {
                        BackButton_Click(this, new RoutedEventArgs());
                    }
                    e.Handled = true;
                    break;

                case VirtualKey.Space:
                    PlayRateButton_Click(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case (VirtualKey)219: // '['
                    TimeTravel_Minus1h(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case (VirtualKey)221: // ']'
                    TimeTravel_Plus1h(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case VirtualKey.L:
                    TimeTravel_ResetLive(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case VirtualKey.N:
                    NightVisionButton_Click(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case VirtualKey.G:
                    GridToggle_Click(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case VirtualKey.C:
                    ConstellationsToggle_Click(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case VirtualKey.A:
                    AtmosphereToggle_Click(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case VirtualKey.Z:
                    ZenithLockButton_Click(this, new RoutedEventArgs());
                    e.Handled = true;
                    break;

                case VirtualKey.Add:
                case (VirtualKey)187:
                    _fieldOfView = Math.Max(0.5, _fieldOfView * 0.8);
                    UpdateZoomPresetHighlight();
                    UpdateCameraHudOnly();
                    SkyCanvas.Invalidate();
                    e.Handled = true;
                    break;

                case VirtualKey.Subtract:
                case (VirtualKey)189:
                    _fieldOfView = Math.Min(120.0, _fieldOfView * 1.25);
                    UpdateZoomPresetHighlight();
                    UpdateCameraHudOnly();
                    SkyCanvas.Invalidate();
                    e.Handled = true;
                    break;
            }
        }

        // ── HUD, Observatory Deck & Target Inspector Updates ─────────────────────

        private void UpdateCameraHudOnly()
        {
            string dir = SGP4Propagator.CompassDirection(_cameraAzimuth);
            double altDisp = _isZenithPlanisphereLocked ? 90.0 : _cameraAltitude;
            TelemetryAzAlt.Text = $"Az {_cameraAzimuth:F1}° ({dir}) • Alt {altDisp:+0.0;-0.0}°";
            string opticMode = _fieldOfView <= 3.0 ? "Telescope" : (_fieldOfView <= 15.0 ? "Binoculars 7x50" : (_fieldOfView <= 80.0 ? "Naked Eye" : "Wide Dome"));
            TelemetryFov.Text = $"FOV {_fieldOfView:F1}° • {opticMode} • NELM {_stargazing.LimitingMagnitude:F1}";
        }

        private void UpdateHudAndDeck(DateTime simUtc)
        {
            UpdateCameraHudOnly();

            Color scoreColor = _isNightVision
                ? Color.FromArgb(255, 255, 24, 36)
                : (_stargazing.Score >= 70
                    ? Color.FromArgb(255, 52, 211, 153)
                    : (_stargazing.Score >= 45
                        ? Color.FromArgb(255, 251, 191, 36)
                        : Color.FromArgb(255, 251, 146, 60)));

            TelemetryStargazing.Text = $"Sky Score {_stargazing.Score}/100 ({_stargazing.Quality})";
            TelemetryStargazing.Foreground = new SolidColorBrush(scoreColor);
            ProvenanceBadgeText.Text = $"TELEMETRY · {_stargazing.Provenance.BadgeText}";
            LocationSubtitle.Text = $"{_locationLabel} • Bortle {_bortleClass} • Moon {_moonPhase.Description} ({_moonPhase.IlluminationPercent}%)";

            bool isLive = Math.Abs(_timeOffset.TotalSeconds) < 3.0 && _playMultiplier == 1;
            SimulationBadgeText.Text = isLive ? "LIVE" : (_playMultiplier > 1 ? $"{_playMultiplier}x SIM" : "TIME MACHINE");
            SimulatedTimeText.Text = isLive
                ? $"LIVE • {simUtc.ToLocalTime():HH:mm:ss}"
                : $"{simUtc.ToLocalTime():yyyy-MM-dd HH:mm}";

            _suppressTimeControls = true;
            TimeScrubberSlider.Value = Math.Clamp(_timeOffset.TotalMinutes, -720.0, 720.0);
            EpochDatePicker.Date = new DateTimeOffset(simUtc.ToLocalTime());
            _suppressTimeControls = false;

            // Stargazing Deck Card
            DeckSkyProvenanceText.Text = _stargazing.Provenance.BadgeText;
            DeckScoreValueText.Text = _stargazing.Score.ToString(CultureInfo.InvariantCulture);
            DeckScoreValueText.Foreground = new SolidColorBrush(scoreColor);
            DeckScoreQualityText.Text = $"{_stargazing.Quality} Stargazing Conditions";
            DeckBestWindowText.Text = !string.IsNullOrWhiteSpace(_stargazing.BestWindowDescription)
                ? $"Best Dark Window: {_stargazing.BestWindowDescription}"
                : "Best Dark Window: Calculating twilight...";

            string cLow = _stargazing.CloudCoverLowPercent?.ToString() ?? "--";
            string cMid = _stargazing.CloudCoverMidPercent?.ToString() ?? "--";
            string cHigh = _stargazing.CloudCoverHighPercent?.ToString() ?? "--";
            DeckCloudBreakdownText.Text = $"Clouds: Low {cLow}% • Mid {cMid}% • High {cHigh}% • Bortle {_bortleClass} (NELM {_stargazing.LimitingMagnitude:F1})";

            string dewStr = _stargazing.DewPointDepressionCelsius.HasValue
                ? $"{_stargazing.DewPointDepressionCelsius.Value:+0.0;-0.0}°C"
                : "--";
            DeckSeeingDewText.Text = $"Seeing: {_stargazing.Seeing} • Transparency: {_stargazing.Transparency} • Dew Spread: {dewStr}";
            DeckCircadianText.Text = _circadian.Summary;

            if (_liveBundle?.IssOmm != null && _issLivePos != null)
            {
                IssLiveStatusText.Text = $"Live Orbit: Az {_issLivePos.AzimuthDegrees:F1}° • Alt {_issLivePos.AltitudeDegrees:+0.0;-0.0}° • Range {_issLivePos.RangeKm:F0} km • {(_issLivePos.IsSunlit ? "Sunlit" : "In Earth's Umbra")}";
            }

            // Narrator Live Accessibility Summary on SkyCanvas
            int aboveCount = _bodies.Count(b => b.IsAboveHorizon && b.Body != CelestialBody.Sun);
            AutomationProperties.SetName(
                SkyCanvas,
                $"Interactive Night Sky Canvas looking {SGP4Propagator.CompassDirection(_cameraAzimuth)} at altitude {(_isZenithPlanisphereLocked ? 90.0 : _cameraAltitude):F0} degrees, field of view {_fieldOfView:F0} degrees. {aboveCount} solar system bodies above horizon. Sky quality {_stargazing.Score} out of 100.");
        }

        private void UpdatePlanetsCarousel()
        {
            PlanetsStack.Children.Clear();
            foreach (var b in _bodies)
            {
                if (b.Body == CelestialBody.Sun) continue;
                bool up = b.IsAboveHorizon;
                Color fg = _isNightVision
                    ? (up ? Color.FromArgb(255, 255, 24, 36) : Color.FromArgb(130, 180, 18, 28))
                    : (up ? Colors.White : Color.FromArgb(140, 200, 210, 230));
                Color border = _isNightVision
                    ? Color.FromArgb(up ? (byte)150 : (byte)50, 255, 24, 36)
                    : (up ? Color.FromArgb(110, 0, 229, 255) : Color.FromArgb(35, 255, 255, 255));

                var btn = new Button
                {
                    Background = new SolidColorBrush(Color.FromArgb(up ? (byte)32 : (byte)12, border.R, border.G, border.B)),
                    BorderBrush = new SolidColorBrush(border),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(13),
                    Padding = new Thickness(9, 3, 9, 3),
                    Tag = b
                };
                btn.Click += (_, _) =>
                {
                    SelectTarget(b, centerCamera: true);
                    SkyCanvas.Invalidate();
                };
                btn.Content = new TextBlock
                {
                    Text = $"{b.Body.Symbol()} {b.Body.DisplayName()} {b.Altitude:+0;-0}°",
                    FontSize = 10.5,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(fg)
                };
                PlanetsStack.Children.Add(btn);
            }
        }

        private void SelectTarget(object target, bool centerCamera)
        {
            _selectedTarget = target;
            RefreshSelectedTargetInspector();

            if (centerCamera)
            {
                CenterCameraOnTarget(target);
            }
        }

        private void CenterCameraOnTarget(object target)
        {
            DateTime simUtc = CurrentSimulationUtc;
            double? az = null, alt = null;
            if (target is CelestialCoordinates b)
            {
                var live = _bodies.FirstOrDefault(x => x.Body == b.Body) ?? b;
                az = live.Azimuth;
                alt = live.Altitude;
            }
            else if (target is LiveSatellitePosition && _issLivePos != null)
            {
                az = _issLivePos.AzimuthDegrees;
                alt = _issLivePos.AltitudeDegrees;
            }
            else if (target is CosmosStar s)
            {
                (az, alt) = _astronomyService.EquatorialToHorizontal(s.RaHours, s.DecDegrees, simUtc, _latitude, _longitude);
            }
            else if (target is CosmosDeepSkyObject d)
            {
                (az, alt) = _astronomyService.EquatorialToHorizontal(d.RaHours, d.DecDeg, simUtc, _latitude, _longitude);
            }
            else if (target is CosmosConstellation c)
            {
                (az, alt) = _astronomyService.EquatorialToHorizontal(c.CenterRaHours, c.CenterDecDeg, simUtc, _latitude, _longitude);
            }
            else if (target is MeteorShower m)
            {
                (az, alt) = _astronomyService.EquatorialToHorizontal(m.RadiantRaHours, m.RadiantDecDeg, simUtc, _latitude, _longitude);
            }

            if (az.HasValue && alt.HasValue)
            {
                _cameraAzimuth = az.Value;
                if (!_isZenithPlanisphereLocked)
                {
                    _cameraAltitude = Math.Clamp(alt.Value, -10.0, 88.0);
                }
                UpdateCameraHudOnly();
            }
        }

        private void RefreshSelectedTargetInspector()
        {
            if (_selectedTarget == null) return;
            DateTime simUtc = CurrentSimulationUtc;

            string objId = "";
            TargetThumbnailBorder.Visibility = Visibility.Collapsed;

            if (_selectedTarget is CelestialCoordinates bodySnap)
            {
                var b = _bodies.FirstOrDefault(x => x.Body == bodySnap.Body) ?? bodySnap;
                objId = $"BODY-{b.Body}";
                TargetCategoryBadge.Text = b.Body == CelestialBody.Moon ? "EARTH'S NATURAL SATELLITE" : "SOLAR SYSTEM EPHEMERIS";
                TargetNameText.Text = $"{b.Body.Symbol()} {b.Body.DisplayName()}";
                TargetTypeText.Text = b.IsAboveHorizon ? "Currently above horizon" : "Currently below local horizon";
                TargetCoordsText.Text = $"Az {b.Azimuth:F1}° • Alt {b.Altitude:+0.0;-0.0}°";
                TargetEqText.Text = FormatRaDec(b.RightAscension, b.Declination);

                if (b.Body == CelestialBody.Moon)
                {
                    double km = _moonPhase.TopocentricDistanceKm ?? _moonPhase.DistanceKm;
                    TargetMagDistText.Text = $"{_moonPhase.Description} ({_moonPhase.IlluminationPercent}% lit) • {km:N0} km • Age {_moonPhase.AgeDays:F1}d";
                    TargetOpticsText.Text = "Naked-eye centerpiece • Crater relief along the lunar terminator shines in 7x50 binoculars or any small telescope.";
                }
                else
                {
                    TargetMagDistText.Text = $"Visual Mag {b.Magnitude?.ToString("F2", CultureInfo.InvariantCulture) ?? "--"} • Distance {b.DistanceAu:F3} AU • Diam {b.AngularDiameterArcsec ?? 0:F1}\"";
                    TargetOpticsText.Text = b.Body switch
                    {
                        CelestialBody.Jupiter => "Zoom to 1.5° Scope to resolve live Io, Europa, Ganymede & Callisto positions.",
                        CelestialBody.Saturn => $"Rings tilted {_saturnRingTiltDeg:+0.0;-0.0}° to Earth • Clearly resolved at 35x+ magnification.",
                        CelestialBody.Venus => $"Illuminated phase {(b.IlluminatedFraction ?? 0) * 100.0:F0}% • Crescent/gibbous disk visible in small scopes.",
                        CelestialBody.Mars => "Rust-orange planetary disk • Best detail near opposition under steady (<1.2\") seeing.",
                        _ => "High-precision VSOP87 topocentric coordinates."
                    };
                }

                var rts = _astronomyService.GetRiseTransitSet(b.Body, simUtc, _latitude, _longitude, _elevationMeters);
                TargetRiseSetText.Text = FormatRiseTransitSet(rts);
            }
            else if (_selectedTarget is LiveSatellitePosition)
            {
                var pos = _issLivePos;
                objId = "SAT-25544";
                TargetCategoryBadge.Text = "LOW-EARTH ORBIT SATELLITE (SGP4)";
                TargetNameText.Text = "ISS (Zarya) • NORAD 25544";
                TargetTypeText.Text = pos != null
                    ? (pos.IsSunlit ? "Sunlit in orbit" : "In Earth's cylindrical umbra")
                    : "Awaiting orbital elements";
                TargetCoordsText.Text = pos != null ? $"Az {pos.AzimuthDegrees:F1}° • Alt {pos.AltitudeDegrees:+0.0;-0.0}°" : "--";
                TargetEqText.Text = pos != null ? $"Sub-Sat {FormatCoordinateLabel(pos.SubSatelliteLatitude, pos.SubSatelliteLongitude)}" : "--";
                TargetMagDistText.Text = pos != null
                    ? $"Est. Mag {pos.EstimatedMagnitude:F1} • Slant Range {pos.RangeKm:F0} km • Orbit {pos.OrbitalAltitudeKm:F0} km"
                    : "Propagated directly from CelesTrak OMM via native SGP4";
                TargetRiseSetText.Text = _liveBundle?.IssPasses?.FirstOrDefault() is SatellitePass np
                    ? $"Next Visible Pass: {np.StartTimeUtc.ToLocalTime():dd MMM HH:mm} (Max {np.MaxAltitudeDegrees:F0}°)"
                    : "No visible sunlit pass in next 48h window";
                TargetOpticsText.Text = "Bright naked-eye fast mover during sunlit twilight passes; wide-field 7x50 binoculars help track across zenith.";
            }
            else if (_selectedTarget is CosmosStar star)
            {
                objId = $"HIP-{star.Hip}";
                var (az, alt) = _astronomyService.EquatorialToHorizontal(star.RaHours, star.DecDegrees, simUtc, _latitude, _longitude);
                var rts = _astronomyService.GetRiseTransitSetStar(star.RaHours, star.DecDegrees, simUtc, _latitude, _longitude);
                TargetCategoryBadge.Text = $"HIPPARCOS STAR • HIP {star.Hip}";
                TargetNameText.Text = star.Name;
                TargetTypeText.Text = string.IsNullOrWhiteSpace(star.Constellation) ? "Stellar Target" : $"Constellation {star.Constellation}";
                TargetCoordsText.Text = $"Az {az:F1}° • Alt {alt:+0.0;-0.0}°";
                TargetEqText.Text = FormatRaDec(star.RaHours, star.DecDegrees);
                TargetMagDistText.Text = $"Visual Mag {star.Mag:F2} • Color Index B-V {star.ColorIndexBV:+0.00;-0.00;0.00}";
                TargetRiseSetText.Text = FormatRiseTransitSet(rts);
                TargetOpticsText.Text = star.Mag <= _stargazing.LimitingMagnitude
                    ? $"Visible to the naked eye tonight (NELM {_stargazing.LimitingMagnitude:F1})."
                    : $"Requires binoculars or telescope under Bortle {_bortleClass} skies.";
            }
            else if (_selectedTarget is CosmosDeepSkyObject dso)
            {
                objId = dso.Id;
                var (az, alt) = _astronomyService.EquatorialToHorizontal(dso.RaHours, dso.DecDeg, simUtc, _latitude, _longitude);
                var rts = _astronomyService.GetRiseTransitSetStar(dso.RaHours, dso.DecDeg, simUtc, _latitude, _longitude);
                TargetCategoryBadge.Text = $"{dso.Catalog.ToUpperInvariant()} DEEP-SKY OBJECT";
                TargetNameText.Text = $"{dso.Id} · {dso.Name}";
                TargetTypeText.Text = $"{dso.Type} • {dso.Constellation}{(string.IsNullOrWhiteSpace(dso.NgcIc) ? "" : $" • {dso.NgcIc}")}";
                TargetCoordsText.Text = $"Az {az:F1}° • Alt {alt:+0.0;-0.0}°";
                TargetEqText.Text = FormatRaDec(dso.RaHours, dso.DecDeg);
                TargetMagDistText.Text = $"Visual Mag {dso.VisualMag:F1} • Size {dso.MajorAxisArcmin:F1}' × {dso.MinorAxisArcmin:F1}'";
                TargetRiseSetText.Text = FormatRiseTransitSet(rts);
                TargetOpticsText.Text = $"{dso.RecommendedOptics} — {dso.Description}";

                string? thumbPath = _catalogRepo.ResolveThumbnailFilePath(dso.Thumbnail);
                if (!string.IsNullOrEmpty(thumbPath) && File.Exists(thumbPath))
                {
                    try
                    {
                        TargetThumbnailImage.Source = new BitmapImage(new Uri(thumbPath));
                        TargetThumbnailBorder.Visibility = Visibility.Visible;
                    }
                    catch { }
                }
            }
            else if (_selectedTarget is CosmosConstellation c)
            {
                objId = $"CONST-{c.Id}";
                var (az, alt) = _astronomyService.EquatorialToHorizontal(c.CenterRaHours, c.CenterDecDeg, simUtc, _latitude, _longitude);
                TargetCategoryBadge.Text = "OFFICIAL IAU CONSTELLATION";
                TargetNameText.Text = $"{c.NameLa} ({c.NameEn})";
                TargetTypeText.Text = $"IAU Code {c.Code} • Genitive {c.Genitive}";
                TargetCoordsText.Text = $"Center Az {az:F1}° • Alt {alt:+0.0;-0.0}°";
                TargetEqText.Text = FormatRaDec(c.CenterRaHours, c.CenterDecDeg);
                TargetMagDistText.Text = $"{c.Segments.Count} stick-figure segments";
                TargetRiseSetText.Text = FormatRiseTransitSet(_astronomyService.GetRiseTransitSetStar(c.CenterRaHours, c.CenterDecDeg, simUtc, _latitude, _longitude));
                TargetOpticsText.Text = c.Lore;
            }
            else if (_selectedTarget is MeteorShower m)
            {
                objId = $"SHOWER-{m.Id}";
                var (az, alt) = _astronomyService.EquatorialToHorizontal(m.RadiantRaHours, m.RadiantDecDeg, simUtc, _latitude, _longitude);
                TargetCategoryBadge.Text = "IAU METEOR SHOWER RADIANT";
                TargetNameText.Text = $"{m.Name} Meteor Shower";
                TargetTypeText.Text = $"Peak {m.PeakDateLabel} • Parent {m.ParentBody}";
                TargetCoordsText.Text = $"Radiant Az {az:F1}° • Alt {alt:+0.0;-0.0}°";
                TargetEqText.Text = FormatRaDec(m.RadiantRaHours, m.RadiantDecDeg);
                TargetMagDistText.Text = $"ZHR {m.Zhr} meteors/hr • Entry {m.VelocityKmS:F0} km/s";
                TargetRiseSetText.Text = FormatRiseTransitSet(_astronomyService.GetRiseTransitSetStar(m.RadiantRaHours, m.RadiantDecDeg, simUtc, _latitude, _longitude));
                TargetOpticsText.Text = m.Description;
            }

            bool isBookmarked = !string.IsNullOrEmpty(objId) && _bookmarks.Any(b => b.ObjectId == objId);
            BookmarkTargetIcon.Glyph = isBookmarked ? "\uE735" : "\uE734";
        }

        private static string FormatRaDec(double raHours, double decDeg)
        {
            double normRa = ((raHours % 24.0) + 24.0) % 24.0;
            int h = (int)Math.Floor(normRa);
            int m = (int)Math.Floor((normRa - h) * 60.0);
            return $"RA {h:D2}h {m:D2}m • Dec {decDeg:+00.0;-00.0}°";
        }

        private static string FormatRiseTransitSet(RiseTransitSetTimes rts)
        {
            string r = rts.RiseTimeUtc.HasValue ? rts.RiseTimeUtc.Value.ToLocalTime().ToString("HH:mm") : "Circumpolar/None";
            string t = rts.TransitTimeUtc.HasValue ? rts.TransitTimeUtc.Value.ToLocalTime().ToString("HH:mm") : "--:--";
            string s = rts.SetTimeUtc.HasValue ? rts.SetTimeUtc.Value.ToLocalTime().ToString("HH:mm") : "--:--";
            return $"Rise {r} • Transit {t} • Set {s}";
        }

        // ── Live Deck Cards (ISS Passes, NOAA Space Weather, Bookmarks, APOD) ────

        private void RenderIssDeck()
        {
            IssPassesStack.Children.Clear();
            if (_liveBundle == null) return;

            IssProvenanceText.Text = _liveBundle.IssProvenance.BadgeText;
            if (_liveBundle.IssOmm == null)
            {
                IssLiveStatusText.Text = _liveBundle.IssProvenance.SourceName;
                return;
            }

            if (_liveBundle.IssPasses.Count == 0)
            {
                IssPassesStack.Children.Add(new TextBlock
                {
                    Text = "No sunlit ISS passes above 10° elevation in the next 48 hours for this latitude.",
                    FontSize = 11,
                    Foreground = new SolidColorBrush( _isNightVision ? Color.FromArgb(190, 255, 24, 36) : Color.FromArgb(170, 255, 255, 255) ),
                    TextWrapping = TextWrapping.Wrap
                });
                return;
            }

            foreach (var pass in _liveBundle.IssPasses.Take(4))
            {
                var row = new Grid { ColumnSpacing = 8 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var info = new StackPanel { Spacing = 1 };
                info.Children.Add(new TextBlock
                {
                    Text = $"{pass.StartTimeUtc.ToLocalTime():ddd dd MMM, HH:mm} • Max {pass.MaxAltitudeDegrees:F0}° ({pass.DurationMinutes} min)",
                    FontSize = 11.5,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    Foreground = new SolidColorBrush(_isNightVision ? Color.FromArgb(255, 255, 24, 36) : Colors.White)
                });
                info.Children.Add(new TextBlock
                {
                    Text = $"{pass.StartCompass} → {pass.EndCompass} • Peak mag {pass.PeakMagnitude:F1}",
                    FontSize = 10.5,
                    Foreground = new SolidColorBrush(_isNightVision ? Color.FromArgb(185, 255, 24, 36) : Color.FromArgb(175, 255, 255, 255))
                });
                Grid.SetColumn(info, 0);
                row.Children.Add(info);

                var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
                var previewBtn = new Button
                {
                    Content = "Preview",
                    FontSize = 10.5,
                    Padding = new Thickness(8, 3, 8, 3),
                    CornerRadius = new CornerRadius(10)
                };
                previewBtn.Click += (_, _) =>
                {
                    _timeOffset = pass.MaxAltitudeTimeUtc - DateTime.UtcNow;
                    RefreshEphemerisSnapshot();
                    if (_issLivePos != null) SelectTarget(_issLivePos, centerCamera: true);
                    SkyCanvas.Invalidate();
                };
                actions.Children.Add(previewBtn);

                var calBtn = new Button
                {
                    Content = "+Cal",
                    FontSize = 10.5,
                    Padding = new Thickness(8, 3, 8, 3),
                    CornerRadius = new CornerRadius(10)
                };
                calBtn.Click += async (_, _) =>
                {
                    await ScheduleCalendarEventInternalAsync(
                        $"ISS Visible Pass (Max {pass.MaxAltitudeDegrees:F0}°)",
                        $"Bright sunlit International Space Station pass from {pass.StartCompass} to {pass.EndCompass} (peak mag {pass.PeakMagnitude:F1}).",
                        pass.StartTimeUtc.ToLocalTime(),
                        pass.EndTimeUtc.ToLocalTime());
                };
                actions.Children.Add(calBtn);

                Grid.SetColumn(actions, 1);
                row.Children.Add(actions);

                IssPassesStack.Children.Add(row);
            }
        }

        private void RenderSpaceWeatherDeck()
        {
            if (_liveBundle == null) return;
            var sw = _liveBundle.SpaceWeather;
            SpaceWeatherProvenanceText.Text = sw.Provenance.BadgeText;
            string kp = sw.KpIndex.HasValue ? sw.KpIndex.Value.ToString("F1", CultureInfo.InvariantCulture) : "--";
            string bz = sw.BzMagneticFieldNt.HasValue ? sw.BzMagneticFieldNt.Value.ToString("+0.0;-0.0;0.0", CultureInfo.InvariantCulture) : "--";
            string wind = sw.SolarWindSpeedKmS.HasValue ? sw.SolarWindSpeedKmS.Value.ToString("F0", CultureInfo.InvariantCulture) : "--";
            SpaceWeatherMetricsText.Text = $"Planetary Kp {kp} • IMF Bz {bz} nT • Solar Wind {wind} km/s";
            SpaceWeatherStatusText.Text = sw.StatusMessage;
        }

        private void RenderBookmarksDeck()
        {
            BookmarksStack.Children.Clear();
            if (_bookmarks.Count == 0)
            {
                BookmarksStack.Children.Add(new TextBlock
                {
                    Text = "Star any celestial target in the Inspector above to save & sync across devices.",
                    FontSize = 11,
                    Foreground = new SolidColorBrush(_isNightVision ? Color.FromArgb(180, 255, 24, 36) : Color.FromArgb(165, 255, 255, 255)),
                    TextWrapping = TextWrapping.Wrap
                });
                return;
            }

            foreach (var bm in _bookmarks.Take(8))
            {
                var btn = new Button
                {
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Left,
                    Background = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255)),
                    BorderThickness = new Thickness(0),
                    CornerRadius = new CornerRadius(10),
                    Padding = new Thickness(10, 6, 10, 6)
                };
                btn.Content = new TextBlock
                {
                    Text = $"★ {bm.ObjectName} ({bm.Category})",
                    FontSize = 11.5,
                    Foreground = new SolidColorBrush(_isNightVision ? Color.FromArgb(255, 255, 24, 36) : Colors.White)
                };
                btn.Click += (_, _) =>
                {
                    if (bm.RaHours.HasValue && bm.DecDeg.HasValue)
                    {
                        var (az, alt) = _astronomyService.EquatorialToHorizontal(bm.RaHours.Value, bm.DecDeg.Value, CurrentSimulationUtc, _latitude, _longitude);
                        _cameraAzimuth = az;
                        if (!_isZenithPlanisphereLocked) _cameraAltitude = Math.Clamp(alt, -10.0, 88.0);
                        UpdateCameraHudOnly();
                        SkyCanvas.Invalidate();
                    }
                };
                BookmarksStack.Children.Add(btn);
            }
        }

        private void RenderApodDeck()
        {
            var apod = _liveBundle?.Apod;
            if (apod == null || string.IsNullOrWhiteSpace(apod.Title))
            {
                ApodDeckCard.Visibility = Visibility.Collapsed;
                return;
            }

            ApodProvenanceText.Text = _liveBundle!.ApodProvenance.BadgeText;
            ApodTitleText.Text = apod.Title;
            ApodExplanationText.Text = apod.Explanation;
            if (apod.MediaType == "image" && Uri.TryCreate(apod.Url, UriKind.Absolute, out var imgUri))
            {
                try { ApodImage.Source = new BitmapImage(imgUri); } catch { }
            }
            ApodDeckCard.Visibility = _isNightVision ? Visibility.Collapsed : Visibility.Visible;
        }

        // ── Controls, Search, Ecosystem Actions & Strict #FF1824 Night-Vision ────

        private void CatalogSearchBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
        {
            if (args.Reason == AutoSuggestionBoxTextChangeReason.UserInput)
            {
                sender.ItemsSource = _catalogRepo.Search(sender.Text);
            }
        }

        private void CatalogSearchBox_SuggestionChosen(AutoSuggestBox sender, AutoSuggestBoxSuggestionChosenEventArgs args)
        {
            if (args.SelectedItem is CosmosSearchResult res)
            {
                NavigateToSearchResult(res);
            }
        }

        private void CatalogSearchBox_QuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
        {
            if (args.ChosenSuggestion is CosmosSearchResult chosen)
            {
                NavigateToSearchResult(chosen);
            }
            else
            {
                var first = _catalogRepo.Search(sender.Text).FirstOrDefault();
                if (first != null) NavigateToSearchResult(first);
            }
        }

        private void NavigateToSearchResult(CosmosSearchResult res)
        {
            if (res.ObjectId == "SAT-25544" && _issLivePos != null)
            {
                SelectTarget(_issLivePos, centerCamera: true);
            }
            else if (res.Body.HasValue)
            {
                var b = _bodies.FirstOrDefault(x => x.Body == res.Body.Value);
                if (b != null) SelectTarget(b, centerCamera: true);
            }
            else if (res.Dso != null)
            {
                SelectTarget(res.Dso, centerCamera: true);
            }
            else if (res.Hip.HasValue)
            {
                var star = _catalogRepo.Stars.FirstOrDefault(s => s.Hip == res.Hip.Value)
                           ?? new CosmosStar { Hip = res.Hip.Value, Name = res.Title, RaHours = res.RaHours, DecDegrees = res.DecDegrees, Mag = res.Magnitude ?? 4.0 };
                SelectTarget(star, centerCamera: true);
            }
            else
            {
                var (az, alt) = _astronomyService.EquatorialToHorizontal(res.RaHours, res.DecDegrees, CurrentSimulationUtc, _latitude, _longitude);
                _cameraAzimuth = az;
                if (!_isZenithPlanisphereLocked) _cameraAltitude = Math.Clamp(alt, -10.0, 88.0);
                UpdateCameraHudOnly();
            }
            SkyCanvas.Invalidate();
        }

        private void CenterTargetBtn_Click(object sender, RoutedEventArgs e)
        {
            if (_selectedTarget != null)
            {
                CenterCameraOnTarget(_selectedTarget);
                SkyCanvas.Invalidate();
            }
        }

        private async void BookmarkTargetBtn_Click(object sender, RoutedEventArgs e)
        {
            var meta = ExtractSelectedTargetMeta();
            if (meta == null) return;
            _bookmarks = await _liveService.ToggleBookmarkAsync(meta.Value.Id, meta.Value.Name, meta.Value.Category, meta.Value.Ra, meta.Value.Dec, meta.Value.Mag);
            RefreshSelectedTargetInspector();
            RenderBookmarksDeck();
            bool saved = _bookmarks.Any(x => x.ObjectId == meta.Value.Id);
            ShowToast(saved ? $"Saved {meta.Value.Name} to Sky Bookmarks" : $"Removed {meta.Value.Name} from Bookmarks");
        }

        private async void LogSightingBtn_Click(object sender, RoutedEventArgs e)
        {
            var meta = ExtractSelectedTargetMeta();
            if (meta == null) return;
            string optics = _fieldOfView <= 3.0 ? "Telescope" : (_fieldOfView <= 15.0 ? "Binoculars 7x50" : "Naked Eye");
            await _liveService.LogSightingAndMirrorToTagdosAsync(
                meta.Value.Id,
                meta.Value.Name,
                meta.Value.Category,
                _latitude,
                _longitude,
                _locationLabel,
                meta.Value.Az,
                meta.Value.Alt,
                _bortleClass,
                _stargazing.Score,
                optics);
            ShowToast($"Logged {meta.Value.Name} sighting & created #sky TagDoS Quick Note");
        }

        private async void ScheduleObsBtn_Click(object sender, RoutedEventArgs e)
        {
            var meta = ExtractSelectedTargetMeta();
            if (meta == null) return;

            DateTime startLocal = DateTime.Now.Date.AddHours(21.5);
            if (startLocal < DateTime.Now.AddMinutes(15))
                startLocal = DateTime.Now.Date.AddDays(1).AddHours(21.5);

            var sun = _astronomyService.GetSunTimes(DateTime.UtcNow, _latitude, _longitude, _elevationMeters);
            if (sun.DuskAstronomicalUtc.HasValue && sun.DuskAstronomicalUtc.Value.ToLocalTime() > DateTime.Now)
            {
                startLocal = sun.DuskAstronomicalUtc.Value.ToLocalTime();
            }

            await ScheduleCalendarEventInternalAsync(
                $"Observe {meta.Value.Name}",
                $"Cosmos Observatory session for {meta.Value.Name} ({meta.Value.Category}) at {_locationLabel}. Bortle {_bortleClass} • Sky Score {_stargazing.Score}/100.",
                startLocal,
                startLocal.AddMinutes(45));
        }

        private async Task ScheduleCalendarEventInternalAsync(string title, string description, DateTime startLocal, DateTime endLocal)
        {
            try
            {
                var cal = App.Current?.Services?.GetService<ICalendarService>();
                if (cal != null)
                {
                    await cal.ScheduleObservationEventAsync(title, description, startLocal, endLocal, _locationLabel);
                    ShowToast($"Scheduled \"{title}\" in Daily Calendar ({startLocal:dd MMM HH:mm})");
                }
            }
            catch (Exception ex)
            {
                ShowToast($"Calendar schedule failed: {ex.Message}");
            }
        }

        private (string Id, string Name, string Category, double? Ra, double? Dec, double? Mag, double? Az, double? Alt)? ExtractSelectedTargetMeta()
        {
            DateTime simUtc = CurrentSimulationUtc;
            if (_selectedTarget is CelestialCoordinates b)
            {
                var live = _bodies.FirstOrDefault(x => x.Body == b.Body) ?? b;
                return ($"BODY-{live.Body}", live.Body.DisplayName(), "planet", live.RightAscension, live.Declination, live.Magnitude, live.Azimuth, live.Altitude);
            }
            if (_selectedTarget is LiveSatellitePosition && _issLivePos != null)
            {
                return ("SAT-25544", "ISS (Zarya)", "satellite", null, null, _issLivePos.EstimatedMagnitude, _issLivePos.AzimuthDegrees, _issLivePos.AltitudeDegrees);
            }
            if (_selectedTarget is CosmosStar s)
            {
                var (az, alt) = _astronomyService.EquatorialToHorizontal(s.RaHours, s.DecDegrees, simUtc, _latitude, _longitude);
                return ($"HIP-{s.Hip}", s.Name, "star", s.RaHours, s.DecDegrees, s.Mag, az, alt);
            }
            if (_selectedTarget is CosmosDeepSkyObject d)
            {
                var (az, alt) = _astronomyService.EquatorialToHorizontal(d.RaHours, d.DecDeg, simUtc, _latitude, _longitude);
                return (d.Id, $"{d.Id} {d.Name}", "dso", d.RaHours, d.DecDeg, d.VisualMag, az, alt);
            }
            if (_selectedTarget is CosmosConstellation c)
            {
                var (az, alt) = _astronomyService.EquatorialToHorizontal(c.CenterRaHours, c.CenterDecDeg, simUtc, _latitude, _longitude);
                return ($"CONST-{c.Id}", c.NameLa, "constellation", c.CenterRaHours, c.CenterDecDeg, null, az, alt);
            }
            if (_selectedTarget is MeteorShower m)
            {
                var (az, alt) = _astronomyService.EquatorialToHorizontal(m.RadiantRaHours, m.RadiantDecDeg, simUtc, _latitude, _longitude);
                return ($"SHOWER-{m.Id}", m.Name, "meteor_shower", m.RadiantRaHours, m.RadiantDecDeg, null, az, alt);
            }
            return null;
        }

        private void ShowToast(string message)
        {
            ToastBannerText.Text = message;
            ToastBanner.Visibility = Visibility.Visible;
            _toastTimer?.Stop();
            _toastTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3.2) };
            _toastTimer.Tick += (_, _) =>
            {
                ToastBanner.Visibility = Visibility.Collapsed;
                _toastTimer?.Stop();
            };
            _toastTimer.Start();
        }

        // ── Layer, Zoom, Time Machine & Window Handlers ──────────────────────────

        private void ConstellationsToggle_Click(object sender, RoutedEventArgs e)
        {
            _showConstellations = !_showConstellations;
            ApplyPaletteToChrome();
            SkyCanvas.Invalidate();
        }

        private void DsoToggle_Click(object sender, RoutedEventArgs e)
        {
            _showDsos = !_showDsos;
            ApplyPaletteToChrome();
            SkyCanvas.Invalidate();
        }

        private void GridToggle_Click(object sender, RoutedEventArgs e)
        {
            _gridMode = _gridMode switch
            {
                SkyGridMode.Off => SkyGridMode.HorizontalAltAz,
                SkyGridMode.HorizontalAltAz => SkyGridMode.EquatorialRaDec,
                _ => SkyGridMode.Off
            };
            GridToggleText.Text = _gridMode switch
            {
                SkyGridMode.HorizontalAltAz => "Grid: Alt-Az",
                SkyGridMode.EquatorialRaDec => "Grid: RA-Dec",
                _ => "Grid: Off"
            };
            ApplyPaletteToChrome();
            SkyCanvas.Invalidate();
        }

        private void AtmosphereToggle_Click(object sender, RoutedEventArgs e)
        {
            _showAtmosphere = !_showAtmosphere;
            ApplyPaletteToChrome();
            SkyCanvas.Invalidate();
        }

        private void ZenithLockButton_Click(object sender, RoutedEventArgs e)
        {
            _isZenithPlanisphereLocked = !_isZenithPlanisphereLocked;
            if (_isZenithPlanisphereLocked && _fieldOfView < 90.0)
            {
                _fieldOfView = 110.0;
            }
            ZenithLockText.Text = _isZenithPlanisphereLocked ? "Zenith Ring" : "Horizon Dome";
            UpdateZoomPresetHighlight();
            ApplyPaletteToChrome();
            UpdateCameraHudOnly();
            SkyCanvas.Invalidate();
        }

        private void DeckToggleButton_Click(object sender, RoutedEventArgs e)
        {
            _isDeckExpanded = !_isDeckExpanded;
            UpdateResponsiveDeckLayout(RootLayout.ActualWidth);
            ApplyPaletteToChrome();
        }

        private void RootLayout_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            UpdateResponsiveDeckLayout(e.NewSize.Width);
        }

        private void UpdateResponsiveDeckLayout(double width)
        {
            bool showSplit = _isDeckExpanded && width >= 980.0;
            if (showSplit)
            {
                SkyColumn.Width = new GridLength(58, GridUnitType.Star);
                DeckColumn.Width = new GridLength(42, GridUnitType.Star);
                ObservatoryDeckPane.Visibility = Visibility.Visible;
                DeckToggleText.Text = "Full-Bleed Sky";
            }
            else
            {
                SkyColumn.Width = new GridLength(1, GridUnitType.Star);
                DeckColumn.Width = new GridLength(0);
                ObservatoryDeckPane.Visibility = Visibility.Collapsed;
                DeckToggleText.Text = "Observatory Deck";
            }
        }

        private void ZoomWide_Click(object sender, RoutedEventArgs e) => SetZoomPreset(110.0);
        private void ZoomEye_Click(object sender, RoutedEventArgs e) => SetZoomPreset(65.0);
        private void ZoomBino_Click(object sender, RoutedEventArgs e) => SetZoomPreset(8.0);
        private void ZoomScope_Click(object sender, RoutedEventArgs e) => SetZoomPreset(1.5);

        private void SetZoomPreset(double fov)
        {
            _fieldOfView = fov;
            UpdateZoomPresetHighlight();
            UpdateCameraHudOnly();
            SkyCanvas.Invalidate();
        }

        private void UpdateZoomPresetHighlight()
        {
            Color accent = _isNightVision ? Color.FromArgb(255, 255, 24, 36) : Color.FromArgb(255, 0, 229, 255);
            Color muted = _isNightVision ? Color.FromArgb(180, 220, 20, 32) : Color.FromArgb(200, 255, 255, 255);

            void StylePreset(Button btn, TextBlock txt, bool active)
            {
                btn.Background = new SolidColorBrush(active ? Color.FromArgb(44, accent.R, accent.G, accent.B) : Colors.Transparent);
                txt.Foreground = new SolidColorBrush(active ? accent : muted);
            }

            StylePreset(ZoomWideBtn, ZoomWideText, _fieldOfView >= 95.0);
            StylePreset(ZoomEyeBtn, ZoomEyeText, _fieldOfView >= 35.0 && _fieldOfView < 95.0);
            StylePreset(ZoomBinoBtn, ZoomBinoText, _fieldOfView >= 4.0 && _fieldOfView < 35.0);
            StylePreset(ZoomScopeBtn, ZoomScopeText, _fieldOfView < 4.0);
        }

        private void PlayRateButton_Click(object sender, RoutedEventArgs e)
        {
            _playMultiplier = _playMultiplier switch
            {
                1 => 60,
                60 => 600,
                600 => 0,
                _ => 1
            };
            PlayRateText.Text = _playMultiplier == 0 ? "Paused" : $"{_playMultiplier}x";
            PlayRateIcon.Glyph = _playMultiplier == 0 ? "\uE769" : "\uE768";
            _lastPlayTickUtc = DateTime.UtcNow;
            if (_playMultiplier > 1) _playTimer?.Start();
            else _playTimer?.Stop();
            RefreshEphemerisSnapshot();
            SkyCanvas.Invalidate();
        }

        private void TimeScrubberSlider_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
        {
            if (_suppressTimeControls) return;
            double dayMinutes = Math.Round(_timeOffset.TotalDays) * 1440.0;
            _timeOffset = TimeSpan.FromMinutes(dayMinutes + e.NewValue);
            RefreshEphemerisSnapshot();
            SkyCanvas.Invalidate();
        }

        private void EpochDatePicker_DateChanged(CalendarDatePicker sender, CalendarDatePickerDateChangedEventArgs args)
        {
            if (_suppressTimeControls || !args.NewDate.HasValue) return;
            var curLocal = CurrentSimulationUtc.ToLocalTime();
            var picked = args.NewDate.Value.DateTime.Date
                .AddHours(curLocal.Hour)
                .AddMinutes(curLocal.Minute)
                .AddSeconds(curLocal.Second);
            DateTime targetUtc = DateTime.SpecifyKind(picked, DateTimeKind.Local).ToUniversalTime();
            _timeOffset = targetUtc - DateTime.UtcNow;
            RefreshEphemerisSnapshot();
            SkyCanvas.Invalidate();
        }

        private void TimeTravel_Minus1h(object sender, RoutedEventArgs e) { _timeOffset -= TimeSpan.FromHours(1); RefreshEphemerisSnapshot(); SkyCanvas.Invalidate(); }
        private void TimeTravel_Plus1h(object sender, RoutedEventArgs e) { _timeOffset += TimeSpan.FromHours(1); RefreshEphemerisSnapshot(); SkyCanvas.Invalidate(); }
        private void TimeTravel_Minus24h(object sender, RoutedEventArgs e) { _timeOffset -= TimeSpan.FromDays(1); RefreshEphemerisSnapshot(); SkyCanvas.Invalidate(); }
        private void TimeTravel_Plus24h(object sender, RoutedEventArgs e) { _timeOffset += TimeSpan.FromDays(1); RefreshEphemerisSnapshot(); SkyCanvas.Invalidate(); }
        private void TimeTravel_TonightDark(object sender, RoutedEventArgs e)
        {
            var local22 = DateTime.Now.Date.AddHours(22);
            _timeOffset = local22.ToUniversalTime() - DateTime.UtcNow;
            RefreshEphemerisSnapshot();
            SkyCanvas.Invalidate();
        }

        private void TimeTravel_ResetLive(object sender, RoutedEventArgs e)
        {
            _timeOffset = TimeSpan.Zero;
            _playMultiplier = 1;
            PlayRateText.Text = "1x";
            PlayRateIcon.Glyph = "\uE768";
            _playTimer?.Stop();
            RefreshEphemerisSnapshot();
            SkyCanvas.Invalidate();
        }

        private void NightVisionButton_Click(object sender, RoutedEventArgs e)
        {
            _isNightVision = !_isNightVision;
            ApplyPaletteToChrome();
            RenderIssDeck();
            RenderBookmarksDeck();
            RenderApodDeck();
            UpdatePlanetsCarousel();
            SkyCanvas.Invalidate();
        }

        private void ApplyPaletteToChrome()
        {
            Color red = Color.FromArgb(255, 255, 24, 36);
            Color redMuted = Color.FromArgb(190, 220, 20, 32);
            Color cyan = Color.FromArgb(255, 0, 229, 255);
            Color emerald = Color.FromArgb(255, 56, 232, 176);

            var primaryText = new SolidColorBrush(_isNightVision ? red : Colors.White);
            var secondaryText = new SolidColorBrush(_isNightVision ? redMuted : Color.FromArgb(195, 255, 255, 255));
            var accentBrush = new SolidColorBrush(_isNightVision ? red : cyan);
            var panelBg = new SolidColorBrush(_isNightVision ? Color.FromArgb(242, 10, 0, 1) : Color.FromArgb(236, 6, 11, 22));
            var panelBorder = new SolidColorBrush(_isNightVision ? Color.FromArgb(110, 255, 24, 36) : Color.FromArgb(55, 255, 255, 255));

            RootLayout.Background = new SolidColorBrush(_isNightVision ? Color.FromArgb(255, 4, 0, 0) : Color.FromArgb(255, 5, 8, 17));
            HeaderBar.Background = new SolidColorBrush(_isNightVision ? Color.FromArgb(235, 10, 0, 1) : Color.FromArgb(215, 6, 10, 20));
            HeaderBar.BorderBrush = panelBorder;
            ObservatoryDeckPane.Background = new SolidColorBrush(_isNightVision ? Color.FromArgb(248, 8, 0, 1) : Color.FromArgb(242, 7, 12, 24));
            ObservatoryDeckPane.BorderBrush = panelBorder;

            TitleText.Foreground = primaryText;
            LocationSubtitle.Foreground = secondaryText;
            HeaderIcon.Foreground = accentBrush;
            HeaderEmblemBorder.BorderBrush = accentBrush;
            HeaderEmblemBorder.Background = new SolidColorBrush(Color.FromArgb(36, _isNightVision ? red.R : cyan.R, _isNightVision ? red.G : cyan.G, _isNightVision ? red.B : cyan.B));

            SimulationBadgeText.Foreground = accentBrush;
            ProvenanceBadgeText.Foreground = secondaryText;
            BackIcon.Foreground = primaryText;
            ResetCameraIcon.Foreground = primaryText;
            PopOutIcon.Foreground = primaryText;

            ZenithLockIcon.Foreground = accentBrush;
            ZenithLockText.Foreground = primaryText;
            NightVisionText.Foreground = _isNightVision ? accentBrush : primaryText;
            DeckToggleIcon.Foreground = accentBrush;
            DeckToggleText.Foreground = primaryText;

            TelemetryCard.Background = panelBg;
            TelemetryCard.BorderBrush = panelBorder;
            TelemetryAzAlt.Foreground = accentBrush;
            TelemetryFov.Foreground = secondaryText;
            TelemetryStargazing.Foreground = _isNightVision ? accentBrush : new SolidColorBrush(emerald);

            PlanetsDeckBorder.Background = panelBg;
            PlanetsDeckBorder.BorderBrush = panelBorder;
            ZoomPresetsBorder.Background = panelBg;
            ZoomPresetsBorder.BorderBrush = panelBorder;
            TimeScrubberBorder.Background = panelBg;
            TimeScrubberBorder.BorderBrush = panelBorder;

            PlayRateIcon.Foreground = accentBrush;
            PlayRateText.Foreground = primaryText;
            Minus1hText.Foreground = secondaryText;
            Plus1hText.Foreground = secondaryText;
            EpochClockIcon.Foreground = accentBrush;
            SimulatedTimeText.Foreground = primaryText;
            LiveResetText.Foreground = accentBrush;

            TargetInspectorCard.BorderBrush = accentBrush;
            TargetCategoryBadge.Foreground = accentBrush;
            TargetNameText.Foreground = primaryText;
            TargetTypeText.Foreground = secondaryText;
            TargetCoordsText.Foreground = primaryText;
            TargetEqText.Foreground = primaryText;
            TargetMagDistText.Foreground = secondaryText;
            TargetRiseSetText.Foreground = secondaryText;
            TargetOpticsText.Foreground = secondaryText;
            LogSightingBtnText.Foreground = primaryText;
            ScheduleObsBtnText.Foreground = primaryText;
            BookmarkTargetIcon.Foreground = _isNightVision ? accentBrush : new SolidColorBrush(Color.FromArgb(255, 255, 209, 102));

            DeckSkyProvenanceText.Foreground = accentBrush;
            DeckScoreValueText.Foreground = _isNightVision ? accentBrush : new SolidColorBrush(emerald);
            DeckScoreQualityText.Foreground = primaryText;
            DeckBestWindowText.Foreground = secondaryText;
            DeckCloudBreakdownText.Foreground = secondaryText;
            DeckSeeingDewText.Foreground = secondaryText;
            DeckCircadianText.Foreground = secondaryText;

            IssProvenanceText.Foreground = accentBrush;
            IssLiveStatusText.Foreground = primaryText;
            SpaceWeatherProvenanceText.Foreground = accentBrush;
            SpaceWeatherMetricsText.Foreground = primaryText;
            SpaceWeatherStatusText.Foreground = secondaryText;

            void StyleLayerPill(Button btn, TextBlock txt, bool active)
            {
                Color c = _isNightVision ? red : cyan;
                btn.Background = new SolidColorBrush(active ? Color.FromArgb(44, c.R, c.G, c.B) : Color.FromArgb(18, 255, 255, 255));
                btn.BorderBrush = new SolidColorBrush(active ? Color.FromArgb(130, c.R, c.G, c.B) : panelBorder.Color);
                txt.Foreground = active ? primaryText : secondaryText;
            }

            StyleLayerPill(ConstellationsToggleBtn, ConstellationsToggleText, _showConstellations);
            StyleLayerPill(DsoToggleBtn, DsoToggleText, _showDsos);
            StyleLayerPill(GridToggleBtn, GridToggleText, _gridMode != SkyGridMode.Off);
            StyleLayerPill(AtmosphereToggleBtn, AtmosphereToggleText, _showAtmosphere);

            UpdateZoomPresetHighlight();
        }

        private void ResetCameraButton_Click(object sender, RoutedEventArgs e)
        {
            _isZenithPlanisphereLocked = false;
            ZenithLockText.Text = "Horizon Dome";
            _cameraAzimuth = 180.0;
            _cameraAltitude = 35.0;
            _fieldOfView = 75.0;
            UpdateZoomPresetHighlight();
            UpdateCameraHudOnly();
            SkyCanvas.Invalidate();
        }

        private void BackButton_Click(object sender, RoutedEventArgs e)
        {
            if (Frame.CanGoBack)
            {
                Frame.GoBack();
            }
            else if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.NavigateToTab(1);
            }
        }

        private void PopOutButton_Click(object sender, RoutedEventArgs e)
        {
            if (App.Current?.MainWindow is MainWindow mw)
            {
                mw.OpenDetailWindow(typeof(CosmosDetailPage));
                mw.NavigateToTab(1);
            }
        }
    }
}
