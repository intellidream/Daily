using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI;
using Daily.Models;
using Daily_WinUI.Services;
using Daily_WinUI.Services.Cosmos;

namespace Daily_WinUI.Views
{
    public sealed partial class CosmosDetailPage : Page
    {
        private readonly AstronomyService _astronomyService = AstronomyService.Shared;
        private readonly CosmosCatalogRepository _catalogRepo = CosmosCatalogRepository.Shared;
        private readonly LocationService _locationService = new();

        private double _latitude = 44.4323;
        private double _longitude = 26.1063;
        private string _locationName = "București, RO";

        // Camera viewport state
        private double _cameraAzimuth = 180.0; // Looking South
        private double _cameraAltitude = 60.0; // Angled sky view
        private double _fieldOfView = 90.0;    // 90° FOV

        // Time simulation
        private TimeSpan _timeOffset = TimeSpan.Zero;
        private DispatcherTimer? _liveTimer;

        // Interactive dragging
        private bool _isDragging;
        private Point _lastPointerPos;

        // Night-Vision Mode
        private bool _isNightVision;

        // Selected celestial target
        private object? _selectedTarget;

        public CosmosDetailPage()
        {
            InitializeComponent();
            Loaded += CosmosDetailPage_Loaded;
            Unloaded += CosmosDetailPage_Unloaded;
        }

        private async void CosmosDetailPage_Loaded(object sender, RoutedEventArgs e)
        {
            await _catalogRepo.EnsureLoadedAsync();

            try
            {
                var coords = await _locationService.GetCurrentCoordinatesAsync();
                if (coords.HasValue)
                {
                    _latitude = coords.Value.Latitude;
                    _longitude = coords.Value.Longitude;
                    LocationSubtitle.Text = $"Observator Cerul Nopții • {_latitude:F2}°N, {_longitude:F2}°E";
                }
            }
            catch { }

            _liveTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(15) };
            _liveTimer.Tick += (s, args) =>
            {
                if (_timeOffset == TimeSpan.Zero)
                {
                    RenderSky();
                }
            };
            _liveTimer.Start();

            RenderSky();
        }

        private void CosmosDetailPage_Unloaded(object sender, RoutedEventArgs e)
        {
            _liveTimer?.Stop();
            _liveTimer = null;
        }

        public async Task RefreshFromTitleBarAsync()
        {
            await _catalogRepo.EnsureLoadedAsync();
            RenderSky();
        }

        private DateTime CurrentSimulationTime => DateTime.UtcNow + _timeOffset;

        // ── Sky Dome Rendering ───────────────────────────────────────────────────

        private void SkyCanvas_SizeChanged(object sender, SizeChangedEventArgs e)
        {
            RenderSky();
        }

        private void RenderSky()
        {
            double w = SkyCanvas.ActualWidth;
            double h = SkyCanvas.ActualHeight;
            if (w <= 50 || h <= 50) return;

            SkyCanvas.Children.Clear();

            double cx = w / 2.0;
            double cy = h / 2.0;
            double radius = Math.Min(cx, cy) * 0.86;

            var time = CurrentSimulationTime;
            UpdateHUDTelemetry(time);

            // 1. Theme Brushes
            var horizonBrush = _isNightVision
                ? new SolidColorBrush(Color.FromArgb(200, 255, 24, 36))
                : new SolidColorBrush(Color.FromArgb(120, 0, 229, 255));

            var guideBrush = _isNightVision
                ? new SolidColorBrush(Color.FromArgb(60, 255, 24, 36))
                : new SolidColorBrush(Color.FromArgb(50, 255, 255, 255));

            var cardinalBrush = _isNightVision
                ? new SolidColorBrush(Color.FromArgb(255, 255, 24, 36))
                : new SolidColorBrush(Color.FromArgb(220, 0, 229, 255));

            // 2. Horizon Circle
            var horizonCircle = new Ellipse
            {
                Width = radius * 2,
                Height = radius * 2,
                Stroke = horizonBrush,
                StrokeThickness = 2,
                StrokeDashArray = new DoubleCollection { 4, 4 },
                Fill = _isNightVision
                    ? new SolidColorBrush(Color.FromArgb(25, 255, 24, 36))
                    : new SolidColorBrush(Color.FromArgb(20, 0, 229, 255))
            };
            Canvas.SetLeft(horizonCircle, cx - radius);
            Canvas.SetTop(horizonCircle, cy - radius);
            SkyCanvas.Children.Add(horizonCircle);

            // 3. Altitude Circles: 30° and 60°
            double r30 = radius * (60.0 / 90.0);
            var circle30 = new Ellipse
            {
                Width = r30 * 2,
                Height = r30 * 2,
                Stroke = guideBrush,
                StrokeThickness = 1
            };
            Canvas.SetLeft(circle30, cx - r30);
            Canvas.SetTop(circle30, cy - r30);
            SkyCanvas.Children.Add(circle30);

            double r60 = radius * (30.0 / 90.0);
            var circle60 = new Ellipse
            {
                Width = r60 * 2,
                Height = r60 * 2,
                Stroke = guideBrush,
                StrokeThickness = 1
            };
            Canvas.SetLeft(circle60, cx - r60);
            Canvas.SetTop(circle60, cy - r60);
            SkyCanvas.Children.Add(circle60);

            // 4. Zenith Cross
            var zLineH = new Line { X1 = cx - 6, Y1 = cy, X2 = cx + 6, Y2 = cy, Stroke = guideBrush, StrokeThickness = 1 };
            var zLineV = new Line { X1 = cx, Y1 = cy - 6, X2 = cx, Y2 = cy + 6, Stroke = guideBrush, StrokeThickness = 1 };
            SkyCanvas.Children.Add(zLineH);
            SkyCanvas.Children.Add(zLineV);

            // 5. Cardinal Markers (N, E, S, V)
            DrawCardinal(cx, cy, radius, 0.0, "N", cardinalBrush);
            DrawCardinal(cx, cy, radius, 90.0, "E", cardinalBrush);
            DrawCardinal(cx, cy, radius, 180.0, "S", cardinalBrush);
            DrawCardinal(cx, cy, radius, 270.0, "V", cardinalBrush);

            // 6. Draw Constellations (IAU Lines)
            var starPositions = new Dictionary<string, (double x, double y)>();

            foreach (var star in _catalogRepo.Stars)
            {
                var (az, alt) = _astronomyService.EquatorialToHorizontal(star.RaHours, star.DecDegrees, time, _latitude, _longitude);
                if (alt > 0)
                {
                    var proj = ProjectToViewport(az, alt, cx, cy, radius);
                    if (proj.HasValue)
                    {
                        starPositions[star.Name] = proj.Value;
                    }
                }
            }

            var constLineBrush = _isNightVision
                ? new SolidColorBrush(Color.FromArgb(90, 255, 24, 36))
                : new SolidColorBrush(Color.FromArgb(70, 0, 229, 255));

            foreach (var constellation in _catalogRepo.Constellations)
            {
                for (int i = 0; i < constellation.Stars.Count - 1; i++)
                {
                    string s1 = constellation.Stars[i];
                    string s2 = constellation.Stars[i + 1];

                    if (starPositions.TryGetValue(s1, out var p1) && starPositions.TryGetValue(s2, out var p2))
                    {
                        var line = new Line
                        {
                            X1 = p1.x,
                            Y1 = p1.y,
                            X2 = p2.x,
                            Y2 = p2.y,
                            Stroke = constLineBrush,
                            StrokeThickness = 1.2
                        };
                        SkyCanvas.Children.Add(line);
                    }
                }
            }

            // 7. Draw Stars
            foreach (var star in _catalogRepo.Stars)
            {
                if (starPositions.TryGetValue(star.Name, out var pos))
                {
                    double starSize = Math.Clamp((5.5 - star.Mag) * 1.8, 2.5, 9.0);
                    Color starColor;

                    if (_isNightVision)
                    {
                        starColor = Color.FromArgb(255, 255, 24, 36);
                    }
                    else
                    {
                        try
                        {
                            string hex = star.ColorHex.TrimStart('#');
                            byte r = byte.Parse(hex.Substring(0, 2), NumberStyles.HexNumber);
                            byte g = byte.Parse(hex.Substring(2, 2), NumberStyles.HexNumber);
                            byte b = byte.Parse(hex.Substring(4, 2), NumberStyles.HexNumber);
                            starColor = Color.FromArgb(255, r, g, b);
                        }
                        catch
                        {
                            starColor = Colors.White;
                        }
                    }

                    var starDisc = new Ellipse
                    {
                        Width = starSize,
                        Height = starSize,
                        Fill = new SolidColorBrush(starColor),
                        Tag = star
                    };
                    starDisc.PointerPressed += StarDisc_PointerPressed;
                    Canvas.SetLeft(starDisc, pos.x - starSize / 2.0);
                    Canvas.SetTop(starDisc, pos.y - starSize / 2.0);
                    SkyCanvas.Children.Add(starDisc);

                    // Name labels for brightest stars (mag < 1.0)
                    if (star.Mag < 1.0)
                    {
                        var starLabel = new TextBlock
                        {
                            Text = star.Name,
                            FontSize = 10,
                            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                            Foreground = new SolidColorBrush(starColor),
                            Opacity = 0.85
                        };
                        Canvas.SetLeft(starLabel, pos.x + starSize / 2.0 + 3);
                        Canvas.SetTop(starLabel, pos.y - 7);
                        SkyCanvas.Children.Add(starLabel);
                    }
                }
            }

            // 8. Draw Deep-Sky Objects (Messier)
            var dsoBrush = _isNightVision
                ? new SolidColorBrush(Color.FromArgb(160, 255, 24, 36))
                : new SolidColorBrush(Color.FromArgb(180, 255, 143, 163));

            foreach (var dso in _catalogRepo.DeepSkyObjects)
            {
                var (az, alt) = _astronomyService.EquatorialToHorizontal(dso.RaHours, dso.DecDegrees, time, _latitude, _longitude);
                if (alt > 0)
                {
                    var proj = ProjectToViewport(az, alt, cx, cy, radius);
                    if (proj.HasValue)
                    {
                        var dsoMarker = new Ellipse
                        {
                            Width = 12,
                            Height = 12,
                            Stroke = dsoBrush,
                            StrokeThickness = 1.2,
                            StrokeDashArray = new DoubleCollection { 2, 2 },
                            Tag = dso
                        };
                        dsoMarker.PointerPressed += DsoMarker_PointerPressed;
                        Canvas.SetLeft(dsoMarker, proj.Value.x - 6);
                        Canvas.SetTop(dsoMarker, proj.Value.y - 6);
                        SkyCanvas.Children.Add(dsoMarker);

                        var dsoText = new TextBlock
                        {
                            Text = dso.Id,
                            FontSize = 9,
                            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                            Foreground = dsoBrush
                        };
                        Canvas.SetLeft(dsoText, proj.Value.x + 8);
                        Canvas.SetTop(dsoText, proj.Value.y - 6);
                        SkyCanvas.Children.Add(dsoText);
                    }
                }
            }

            // 9. Draw Planets & Sun / Moon
            var bodies = _astronomyService.GetAllVisibleBodies(time, _latitude, _longitude);
            UpdatePlanetsCarousel(bodies);

            foreach (var b in bodies)
            {
                if (b.IsAboveHorizon)
                {
                    var proj = ProjectToViewport(b.Azimuth, b.Altitude, cx, cy, radius);
                    if (proj.HasValue)
                    {
                        DrawPlanetMarker(b, proj.Value.x, proj.Value.y);
                    }
                }
            }

            // 10. Center Crosshair Reticle
            DrawReticle(cx, cy, guideBrush);
        }

        private void DrawCardinal(double cx, double cy, double radius, double azimuthDeg, string label, Brush brush)
        {
            double angleRad = (azimuthDeg - _cameraAzimuth) * (Math.PI / 180.0);
            double x = cx + radius * Math.Sin(angleRad);
            double y = cy - radius * Math.Cos(angleRad);

            var text = new TextBlock
            {
                Text = label,
                FontSize = 13,
                FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                Foreground = brush,
                HorizontalTextAlignment = TextAlignment.Center
            };
            Canvas.SetLeft(text, x - 7);
            Canvas.SetTop(text, y - 9);
            SkyCanvas.Children.Add(text);
        }

        private void DrawPlanetMarker(CelestialCoordinates body, double x, double y)
        {
            Color color = _isNightVision
                ? Color.FromArgb(255, 255, 24, 36)
                : body.Body switch
                {
                    CelestialBody.Sun => Color.FromArgb(255, 255, 209, 102),
                    CelestialBody.Moon => Color.FromArgb(255, 240, 240, 240),
                    CelestialBody.Mars => Color.FromArgb(255, 255, 107, 107),
                    CelestialBody.Jupiter => Color.FromArgb(255, 255, 184, 108),
                    CelestialBody.Venus => Color.FromArgb(255, 0, 229, 255),
                    CelestialBody.Saturn => Color.FromArgb(255, 255, 224, 138),
                    _ => Color.FromArgb(255, 105, 182, 255)
                };

            double markerSize = body.Body == CelestialBody.Sun || body.Body == CelestialBody.Moon ? 16 : 10;

            var planetDisc = new Ellipse
            {
                Width = markerSize,
                Height = markerSize,
                Fill = new SolidColorBrush(color),
                Stroke = new SolidColorBrush(Colors.White),
                StrokeThickness = 1,
                Tag = body
            };
            planetDisc.PointerPressed += PlanetDisc_PointerPressed;
            Canvas.SetLeft(planetDisc, x - markerSize / 2.0);
            Canvas.SetTop(planetDisc, y - markerSize / 2.0);
            SkyCanvas.Children.Add(planetDisc);

            var nameText = new TextBlock
            {
                Text = GetBodyRomanianName(body.Body),
                FontSize = 10,
                FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                Foreground = new SolidColorBrush(color)
            };
            Canvas.SetLeft(nameText, x + markerSize / 2.0 + 4);
            Canvas.SetTop(nameText, y - 7);
            SkyCanvas.Children.Add(nameText);
        }

        private void DrawReticle(double cx, double cy, Brush brush)
        {
            var r1 = new Line { X1 = cx - 18, Y1 = cy, X2 = cx - 4, Y2 = cy, Stroke = brush, StrokeThickness = 1.2 };
            var r2 = new Line { X1 = cx + 4, Y1 = cy, X2 = cx + 18, Y2 = cy, Stroke = brush, StrokeThickness = 1.2 };
            var r3 = new Line { X1 = cx, Y1 = cy - 18, X2 = cx, Y2 = cy - 4, Stroke = brush, StrokeThickness = 1.2 };
            var r4 = new Line { X1 = cx, Y1 = cy + 4, X2 = cx, Y2 = cy + 18, Stroke = brush, StrokeThickness = 1.2 };
            var dot = new Ellipse { Width = 3, Height = 3, Fill = brush };
            Canvas.SetLeft(dot, cx - 1.5);
            Canvas.SetTop(dot, cy - 1.5);

            SkyCanvas.Children.Add(r1);
            SkyCanvas.Children.Add(r2);
            SkyCanvas.Children.Add(r3);
            SkyCanvas.Children.Add(r4);
            SkyCanvas.Children.Add(dot);
        }

        private (double x, double y)? ProjectToViewport(double azimuthDeg, double altitudeDeg, double cx, double cy, double radius)
        {
            if (altitudeDeg < -5.0) return null;

            // Stereographic radius: r = (90 - alt) / 90
            double altFraction = Math.Clamp((90.0 - altitudeDeg) / 90.0, 0.0, 1.0);
            double r = radius * altFraction * (90.0 / _fieldOfView);

            // Relative azimuth to camera orientation
            double relAzRad = (azimuthDeg - _cameraAzimuth) * (Math.PI / 180.0);
            double x = cx + r * Math.Sin(relAzRad);
            double y = cy - r * Math.Cos(relAzRad);

            return (x, y);
        }

        private void UpdateHUDTelemetry(DateTime time)
        {
            TelemetryAzAlt.Text = $"Az: {_cameraAzimuth:F1}° • Alt: {_cameraAltitude:F1}°";
            TelemetryFov.Text = $"Câmp vizual (FOV): {_fieldOfView:F0}°";

            var moon = _astronomyService.GetMoonPhase(time);
            var stargazing = _astronomyService.EvaluateStargazingQuality(15.0, moon.IlluminatedFraction, 4);
            TelemetryStargazing.Text = $"Calitate cer: {stargazing.Quality} ({stargazing.Score})";

            if (_timeOffset == TimeSpan.Zero)
            {
                SimulationBadgeText.Text = "LIVE";
                SimulationBadge.Background = new SolidColorBrush(Color.FromArgb(40, 0, 229, 255));
                SimulatedTimeText.Text = $"LIVE: {time.ToLocalTime():dd MMM, HH:mm}";
            }
            else
            {
                SimulationBadgeText.Text = "SIMULARE";
                SimulationBadge.Background = new SolidColorBrush(Color.FromArgb(40, 255, 209, 102));
                SimulatedTimeText.Text = $"Timp: {time.ToLocalTime():dd MMM, HH:mm}";
            }
        }

        private void UpdatePlanetsCarousel(List<CelestialCoordinates> bodies)
        {
            PlanetsStack.Children.Clear();

            foreach (var b in bodies)
            {
                if (b.Body == CelestialBody.Sun) continue;

                var btn = new Button
                {
                    Background = b.IsAboveHorizon
                        ? new SolidColorBrush(Color.FromArgb(40, 0, 229, 255))
                        : new SolidColorBrush(Color.FromArgb(15, 255, 255, 255)),
                    BorderBrush = b.IsAboveHorizon
                        ? new SolidColorBrush(Color.FromArgb(90, 0, 229, 255))
                        : new SolidColorBrush(Color.FromArgb(20, 255, 255, 255)),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(14),
                    Padding = new Thickness(10, 4, 10, 4),
                    Tag = b
                };
                btn.Click += PlanetCarouselButton_Click;

                var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                panel.Children.Add(new FontIcon
                {
                    Glyph = b.Body == CelestialBody.Moon ? "\uE708" : "\uE787",
                    FontFamily = new FontFamily("Segoe Fluent Icons"),
                    FontSize = 11,
                    Foreground = b.IsAboveHorizon ? new SolidColorBrush(Color.FromArgb(255, 0, 229, 255)) : new SolidColorBrush(Colors.Gray)
                });
                panel.Children.Add(new TextBlock
                {
                    Text = $"{GetBodyRomanianName(b.Body)} ({b.Altitude:+0;-0}°)",
                    FontSize = 11,
                    FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
                    Foreground = b.IsAboveHorizon ? new SolidColorBrush(Colors.White) : new SolidColorBrush(Colors.Gray)
                });

                btn.Content = panel;
                PlanetsStack.Children.Add(btn);
            }
        }

        private static string GetBodyRomanianName(CelestialBody body) => body switch
        {
            CelestialBody.Sun => "Soare",
            CelestialBody.Moon => "Lună",
            CelestialBody.Mercury => "Mercur",
            CelestialBody.Venus => "Venus",
            CelestialBody.Mars => "Marte",
            CelestialBody.Jupiter => "Jupiter",
            CelestialBody.Saturn => "Saturn",
            CelestialBody.Uranus => "Uranus",
            CelestialBody.Neptune => "Neptun",
            CelestialBody.Pluto => "Pluto",
            _ => body.ToString()
        };

        // ── Interactive Panning & Zoom ───────────────────────────────────────────

        private void SkyCanvas_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            _isDragging = true;
            _lastPointerPos = e.GetCurrentPoint(SkyCanvas).Position;
            SkyCanvas.CapturePointer(e.Pointer);
        }

        private void SkyCanvas_PointerMoved(object sender, PointerRoutedEventArgs e)
        {
            if (!_isDragging) return;

            var pos = e.GetCurrentPoint(SkyCanvas).Position;
            double dx = pos.X - _lastPointerPos.X;
            double dy = pos.Y - _lastPointerPos.Y;
            _lastPointerPos = pos;

            _cameraAzimuth = (_cameraAzimuth - dx * 0.25) % 360.0;
            if (_cameraAzimuth < 0) _cameraAzimuth += 360.0;

            _cameraAltitude = Math.Clamp(_cameraAltitude + dy * 0.25, 10.0, 90.0);

            RenderSky();
        }

        private void SkyCanvas_PointerReleased(object sender, PointerRoutedEventArgs e)
        {
            _isDragging = false;
            SkyCanvas.ReleasePointerCapture(e.Pointer);
        }

        private void SkyCanvas_PointerWheelChanged(object sender, PointerRoutedEventArgs e)
        {
            int delta = e.GetCurrentPoint(SkyCanvas).Properties.MouseWheelDelta;
            if (delta > 0)
            {
                _fieldOfView = Math.Max(30.0, _fieldOfView - 5.0); // Zoom in
            }
            else if (delta < 0)
            {
                _fieldOfView = Math.Min(120.0, _fieldOfView + 5.0); // Zoom out
            }
            RenderSky();
        }

        // ── Target Selection & Inspection ────────────────────────────────────────

        private void PlanetDisc_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            if (sender is FrameworkElement fe && fe.Tag is CelestialCoordinates body)
            {
                SelectTarget(body);
            }
        }

        private void StarDisc_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            if (sender is FrameworkElement fe && fe.Tag is CosmosStar star)
            {
                SelectTarget(star);
            }
        }

        private void DsoMarker_PointerPressed(object sender, PointerRoutedEventArgs e)
        {
            if (sender is FrameworkElement fe && fe.Tag is CosmosDeepSkyObject dso)
            {
                SelectTarget(dso);
            }
        }

        private void PlanetCarouselButton_Click(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is CelestialCoordinates body)
            {
                _cameraAzimuth = body.Azimuth;
                _cameraAltitude = Math.Max(15.0, body.Altitude);
                SelectTarget(body);
                RenderSky();
            }
        }

        private void SelectTarget(object target)
        {
            _selectedTarget = target;
            TargetInspectorCard.Visibility = Visibility.Visible;

            if (target is CelestialCoordinates body)
            {
                TargetNameText.Text = GetBodyRomanianName(body.Body);
                TargetTypeText.Text = $"Planetă • Sistemul Solar {(body.IsAboveHorizon ? "• Vizibil acum" : "• Sub orizont")}";
                TargetCoordsText.Text = $"Az: {body.Azimuth:F1}° • Alt: {body.Altitude:F1}°";
                TargetMagDistText.Text = $"Mag: {body.Magnitude?.ToString("F1") ?? "--"} • Dist: {body.DistanceAu:F2} AU";
                TargetOpticsText.Text = body.Body switch
                {
                    CelestialBody.Moon => "Observabil cu ochiul liber • Cratere spectaculoase prin binoclu sau telescop",
                    CelestialBody.Jupiter => "4 sateliți galileeni vizibili prin binoclu 10x50 • Benzi noroase prin telescop",
                    CelestialBody.Saturn => "Inelele magnifice vizibile prin telescop cu apertură minimă de 60mm",
                    CelestialBody.Venus => "Faze vizibile clar la mărire 20x+",
                    CelestialBody.Mars => "Disc roșiatic • Calote glaciare polare vizibile în opoziție",
                    _ => "Urmăriți cu telescop motorizat"
                };
            }
            else if (target is CosmosStar star)
            {
                TargetNameText.Text = star.Name;
                TargetTypeText.Text = $"Stea • {star.Bayer ?? ""} în {star.Constellation}";
                var (az, alt) = _astronomyService.EquatorialToHorizontal(star.RaHours, star.DecDegrees, CurrentSimulationTime, _latitude, _longitude);
                TargetCoordsText.Text = $"Az: {az:F1}° • Alt: {alt:F1}°";
                TargetMagDistText.Text = $"Mag: {star.Mag:F1} • Indice B-V: {star.ColorIndexBV:F2}";
                TargetOpticsText.Text = $"Clasă spectrală corespunzătoare culorii {star.ColorHex} • Vizibilă cu ochiul liber pe cer senin.";
            }
            else if (target is CosmosDeepSkyObject dso)
            {
                TargetNameText.Text = $"{dso.Id} - {dso.Name}";
                TargetTypeText.Text = $"{dso.Type} • Constelația {dso.Constellation}";
                var (az, alt) = _astronomyService.EquatorialToHorizontal(dso.RaHours, dso.DecDegrees, CurrentSimulationTime, _latitude, _longitude);
                TargetCoordsText.Text = $"Az: {az:F1}° • Alt: {alt:F1}°";
                TargetMagDistText.Text = $"Mag: {dso.VisualMag:F1} • {dso.Optics}";
                TargetOpticsText.Text = $"{dso.DescRo}";
            }
        }

        private void CloseTargetCard_Click(object sender, RoutedEventArgs e)
        {
            TargetInspectorCard.Visibility = Visibility.Collapsed;
            _selectedTarget = null;
        }

        // ── Catalog Search & Center ──────────────────────────────────────────────

        private void CatalogSearchBox_TextChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
        {
            if (args.Reason == AutoSuggestionReason.UserInput)
            {
                var results = _catalogRepo.Search(sender.Text);
                sender.ItemsSource = results;
            }
        }

        private void CatalogSearchBox_SuggestionChosen(AutoSuggestBox sender, AutoSuggestBoxSuggestionChosenEventArgs args)
        {
            if (args.SelectedItem is CosmosSearchResult result)
            {
                CenterOnCoordinates(result.RaHours, result.DecDegrees);
            }
        }

        private void CatalogSearchBox_QuerySubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
        {
            if (args.ChosenSuggestion is CosmosSearchResult result)
            {
                CenterOnCoordinates(result.RaHours, result.DecDegrees);
            }
            else
            {
                var first = _catalogRepo.Search(sender.Text).FirstOrDefault();
                if (first != null)
                {
                    CenterOnCoordinates(first.RaHours, first.DecDegrees);
                }
            }
        }

        private void CenterOnCoordinates(double raHours, double decDeg)
        {
            var (az, alt) = _astronomyService.EquatorialToHorizontal(raHours, decDeg, CurrentSimulationTime, _latitude, _longitude);
            _cameraAzimuth = az;
            _cameraAltitude = Math.Max(15.0, alt);
            RenderSky();
        }

        // ── Time Machine Controls ────────────────────────────────────────────────

        private void TimeTravel_Minus1h(object sender, RoutedEventArgs e)
        {
            _timeOffset -= TimeSpan.FromHours(1);
            RenderSky();
        }

        private void TimeTravel_Minus15m(object sender, RoutedEventArgs e)
        {
            _timeOffset -= TimeSpan.FromMinutes(15);
            RenderSky();
        }

        private void TimeTravel_Plus15m(object sender, RoutedEventArgs e)
        {
            _timeOffset += TimeSpan.FromMinutes(15);
            RenderSky();
        }

        private void TimeTravel_Plus1h(object sender, RoutedEventArgs e)
        {
            _timeOffset += TimeSpan.FromHours(1);
            RenderSky();
        }

        private void TimeTravel_Plus24h(object sender, RoutedEventArgs e)
        {
            _timeOffset += TimeSpan.FromHours(24);
            RenderSky();
        }

        private void TimeTravel_ResetLive(object sender, RoutedEventArgs e)
        {
            _timeOffset = TimeSpan.Zero;
            RenderSky();
        }

        // ── Red Night-Vision & Actions ───────────────────────────────────────────

        private void NightVisionButton_Click(object sender, RoutedEventArgs e)
        {
            _isNightVision = !_isNightVision;

            if (_isNightVision)
            {
                RootLayout.Background = new SolidColorBrush(Color.FromArgb(255, 5, 0, 0));
                NightVisionButton.BorderBrush = new SolidColorBrush(Color.FromArgb(255, 255, 24, 36));
                NightVisionButton.Background = new SolidColorBrush(Color.FromArgb(80, 255, 24, 36));
                NightVisionText.Foreground = new SolidColorBrush(Color.FromArgb(255, 255, 24, 36));
                HeaderIcon.Foreground = new SolidColorBrush(Color.FromArgb(255, 255, 24, 36));
                TitleText.Foreground = new SolidColorBrush(Color.FromArgb(255, 255, 24, 36));
            }
            else
            {
                RootLayout.Background = new SolidColorBrush(Color.FromArgb(255, 5, 8, 17));
                NightVisionButton.BorderBrush = (Brush)Application.Current.Resources["AppGlassBorderColorBrush"];
                NightVisionButton.Background = (Brush)Application.Current.Resources["AppGlassColorBrush"];
                NightVisionText.Foreground = (Brush)Application.Current.Resources["AppFgColorBrush"];
                HeaderIcon.Foreground = new SolidColorBrush(Color.FromArgb(255, 0, 229, 255));
                TitleText.Foreground = (Brush)Application.Current.Resources["AppFgColorBrush"];
            }

            RenderSky();
        }

        private void ResetCameraButton_Click(object sender, RoutedEventArgs e)
        {
            _cameraAzimuth = 180.0;
            _cameraAltitude = 60.0;
            _fieldOfView = 90.0;
            RenderSky();
        }

        private void BackButton_Click(object sender, RoutedEventArgs e)
        {
            if (Frame.CanGoBack)
            {
                Frame.GoBack();
            }
            else if (App.CurrentWindow is MainWindow mw)
            {
                mw.NavigateToTab(1);
            }
        }

        private void PopOutButton_Click(object sender, RoutedEventArgs e)
        {
            DetailWindow.OpenDetailWindow(typeof(CosmosDetailPage));
        }
    }
}
