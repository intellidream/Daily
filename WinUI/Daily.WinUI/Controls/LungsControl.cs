using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using Windows.UI;
using XamlPath = Microsoft.UI.Xaml.Shapes.Path;

namespace Daily_WinUI.Controls
{
    /// <summary>
    /// Draws a realistic pair of lungs.
    /// FillFraction (0–1): 0 = healthy pink, 1 = fully tar-blackened.
    /// Natural size: 300 × 420.
    /// </summary>
    public class LungsControl : Control
    {
        // ── Dependency Properties ────────────────────────────────────────────────

        public static readonly DependencyProperty FillFractionProperty =
            DependencyProperty.Register(nameof(FillFraction), typeof(double), typeof(LungsControl),
                new PropertyMetadata(0.0, (d, _) => ((LungsControl)d).Rebuild()));

        public double FillFraction
        {
            get => (double)GetValue(FillFractionProperty);
            set => SetValue(FillFractionProperty, Math.Clamp(value, 0.0, 1.0));
        }

        // ── Template parts ───────────────────────────────────────────────────────

        private Canvas?   _canvas;
        private XamlPath? _leftOutline;
        private XamlPath? _rightOutline;
        private XamlPath? _leftFill;
        private XamlPath? _rightFill;
        private XamlPath? _trachea;
        private XamlPath? _leftDivision;
        private XamlPath? _rightDivision;

        public LungsControl()
        {
            DefaultStyleKey = typeof(LungsControl);
        }

        protected override void OnApplyTemplate()
        {
            base.OnApplyTemplate();
            _canvas        = GetTemplateChild("PART_Canvas")        as Canvas;
            _leftOutline   = GetTemplateChild("PART_LeftOutline")   as XamlPath;
            _rightOutline  = GetTemplateChild("PART_RightOutline")  as XamlPath;
            _leftFill      = GetTemplateChild("PART_LeftFill")      as XamlPath;
            _rightFill     = GetTemplateChild("PART_RightFill")     as XamlPath;
            _trachea       = GetTemplateChild("PART_Trachea")       as XamlPath;
            _leftDivision  = GetTemplateChild("PART_LeftDivision")  as XamlPath;
            _rightDivision = GetTemplateChild("PART_RightDivision") as XamlPath;
            Rebuild();
        }

        protected override Size MeasureOverride(Size availableSize)
        {
            double w = double.IsInfinity(availableSize.Width)  ? 300 : availableSize.Width;
            double h = double.IsInfinity(availableSize.Height) ? 420 : availableSize.Height;
            Rebuild(w, h);
            return new Size(w, h);
        }

        // ── Drawing ──────────────────────────────────────────────────────────────

        private void Rebuild() => Rebuild(
            ActualWidth  > 0 ? ActualWidth  : 300,
            ActualHeight > 0 ? ActualHeight : 420);

        /// <summary>
        /// Builds the left lung lobe silhouette with anatomical proportions.
        /// All coordinates are fractions of (w, h) so the shape scales freely.
        /// </summary>
        private PathGeometry BuildLeftLobe(double w, double h)
        {
            double cx = w * 0.50;

            // Vertical landmarks
            double apexY  = h * 0.06;   // apex (top of lung)
            double lobeTy = h * 0.20;   // bronchial junction (inner top)
            double midY   = h * 0.52;   // maximum lateral width
            double concY  = h * 0.88;   // costodiaphragmatic angle
            double baseY  = h * 0.94;   // diaphragm lowest point

            // Horizontal landmarks (left lobe)
            double innerX = cx - w * 0.055;  // mediastinal wall (close to centre)
            double apexX  = cx - w * 0.14;   // apex — slightly lateral
            double latX   = cx - w * 0.46;   // widest lateral point
            double baseX  = cx - w * 0.31;   // base at diaphragm
            double concX  = cx - w * 0.08;   // costodiaphragmatic inner angle

            var lobe = new PathGeometry();
            var fig  = new PathFigure
            {
                StartPoint = new Point(innerX, lobeTy),
                IsClosed   = true
            };

            // 1. Inner junction → apex  (mediastinal surface)
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(innerX - w * 0.02,  lobeTy - h * 0.06),
                Point2 = new Point(apexX  + w * 0.03,  apexY  + h * 0.02),
                Point3 = new Point(apexX,               apexY)
            });

            // 2. Apex → maximum lateral (superior costal surface)
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(apexX  - w * 0.20,  apexY  + h * 0.05),
                Point2 = new Point(latX   + w * 0.02,  midY   - h * 0.16),
                Point3 = new Point(latX,                midY)
            });

            // 3. Lateral widest → costodiaphragmatic angle (lower costal)
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(latX,                midY   + h * 0.18),
                Point2 = new Point(baseX  - w * 0.03,  concY  - h * 0.03),
                Point3 = new Point(baseX,               concY)
            });

            // 4. Costodiaphragmatic angle → diaphragmatic base (concave upward curve)
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(baseX  + w * 0.07,  baseY  + h * 0.01),
                Point2 = new Point(concX  - w * 0.02,  baseY  + h * 0.01),
                Point3 = new Point(concX,               baseY  - h * 0.01)
            });

            // 5. Diaphragmatic inner corner → mediastinal wall bottom
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(concX  + w * 0.01,  baseY),
                Point2 = new Point(innerX - w * 0.01,  baseY  - h * 0.07),
                Point3 = new Point(innerX,              baseY  - h * 0.11)
            });

            // 6. Mediastinal wall back up to bronchial junction
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(innerX + w * 0.01,  midY   + h * 0.10),
                Point2 = new Point(innerX - w * 0.01,  lobeTy + h * 0.10),
                Point3 = new Point(innerX,              lobeTy)
            });

            lobe.Figures.Add(fig);
            return lobe;
        }

        /// <summary>
        /// Builds the oblique fissure line — a faint diagonal arc dividing
        /// upper and lower lobes on the left lung.
        /// </summary>
        private PathGeometry BuildLeftFissure(double w, double h)
        {
            double cx     = w * 0.50;
            double innerX = cx - w * 0.055;
            double latX   = cx - w * 0.44;
            double fissY  = h * 0.56;  // roughly the oblique fissure centre height

            var geom = new PathGeometry();
            var fig  = new PathFigure
            {
                StartPoint = new Point(innerX, fissY - h * 0.10),
                IsClosed   = false
            };
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(innerX - w * 0.08, fissY - h * 0.06),
                Point2 = new Point(latX   + w * 0.10, fissY + h * 0.01),
                Point3 = new Point(latX,               fissY)
            });
            geom.Figures.Add(fig);
            return geom;
        }

        private void Rebuild(double w, double h)
        {
            if (_leftOutline is null) return;

            double fraction = Math.Clamp(FillFraction, 0.0, 1.0);

            double cx     = w * 0.50;
            double ty     = h * 0.02;   // top of trachea
            double carY   = h * 0.15;   // carina (bronchial split)
            double lobeTy = h * 0.20;   // lobe bronchial junction

            // Each Path.Data must be its own unique geometry instance.
            var leftOutlineGeom  = BuildLeftLobe(w, h);
            var rightOutlineGeom = Mirror(leftOutlineGeom, w);
            var leftFillGeom     = BuildLeftLobe(w, h);
            var rightFillGeom    = Mirror(leftFillGeom, w);

            _leftOutline.Data  = leftOutlineGeom;
            _rightOutline.Data = rightOutlineGeom;

            // ── Trachea + main bronchi ────────────────────────────────────────────
            double tw     = w * 0.042;   // trachea half-width
            double bw     = w * 0.026;   // bronchus half-width
            double innerL = cx - w * 0.055;
            double innerR = cx + w * 0.055;

            var trGeom = new PathGeometry();

            // Left trachea wall → left main bronchus (outer wall of tube)
            var leftTr = new PathFigure { StartPoint = new Point(cx - tw, ty), IsClosed = false };
            leftTr.Segments.Add(new LineSegment { Point = new Point(cx - tw, carY) });
            leftTr.Segments.Add(new BezierSegment
            {
                Point1 = new Point(cx - tw,       carY  + h * 0.025),
                Point2 = new Point(innerL - bw,   lobeTy - h * 0.008),
                Point3 = new Point(innerL - bw,   lobeTy)
            });
            trGeom.Figures.Add(leftTr);

            // Right trachea wall → right main bronchus
            var rightTr = new PathFigure { StartPoint = new Point(cx + tw, ty), IsClosed = false };
            rightTr.Segments.Add(new LineSegment { Point = new Point(cx + tw, carY) });
            rightTr.Segments.Add(new BezierSegment
            {
                Point1 = new Point(cx + tw,       carY  + h * 0.025),
                Point2 = new Point(innerR + bw,   lobeTy - h * 0.008),
                Point3 = new Point(innerR + bw,   lobeTy)
            });
            trGeom.Figures.Add(rightTr);

            // Inner walls of both bronchi (slightly offset inward)
            var leftBrInner = new PathFigure { StartPoint = new Point(cx - tw + bw, carY), IsClosed = false };
            leftBrInner.Segments.Add(new BezierSegment
            {
                Point1 = new Point(cx - tw + bw,  carY  + h * 0.025),
                Point2 = new Point(innerL,         lobeTy - h * 0.008),
                Point3 = new Point(innerL,         lobeTy)
            });
            trGeom.Figures.Add(leftBrInner);

            var rightBrInner = new PathFigure { StartPoint = new Point(cx + tw - bw, carY), IsClosed = false };
            rightBrInner.Segments.Add(new BezierSegment
            {
                Point1 = new Point(cx + tw - bw,  carY  + h * 0.025),
                Point2 = new Point(innerR,         lobeTy - h * 0.008),
                Point3 = new Point(innerR,         lobeTy)
            });
            trGeom.Figures.Add(rightBrInner);

            // Top of trachea (horizontal cap)
            var trachTop = new PathFigure { StartPoint = new Point(cx - tw, ty), IsClosed = false };
            trachTop.Segments.Add(new LineSegment { Point = new Point(cx + tw, ty) });
            trGeom.Figures.Add(trachTop);

            _trachea!.Data = trGeom;

            // ── Fissure lines ─────────────────────────────────────────────────────
            if (_leftDivision != null)
                _leftDivision.Data = BuildLeftFissure(w, h);
            if (_rightDivision != null)
                _rightDivision.Data = Mirror(BuildLeftFissure(w, h), w);

            // ── Fill clipping (tar fills from bottom upward) ──────────────────────
            double clipTop = h * (1.0 - fraction);
            _leftFill!.Data  = leftFillGeom;
            _rightFill!.Data = rightFillGeom;
            _leftFill.Clip   = new RectangleGeometry { Rect = new Rect(0, clipTop, w, h) };
            _rightFill.Clip  = new RectangleGeometry { Rect = new Rect(0, clipTop, w, h) };

            // ── Colours ───────────────────────────────────────────────────────────
            var outlineBrush = new SolidColorBrush(Color.FromArgb(210, 230, 155, 155));
            var tracheaBrush = new SolidColorBrush(Color.FromArgb(190, 215, 155, 155));
            var fissureBrush = new SolidColorBrush(Color.FromArgb(90,  255, 180, 180));

            _leftOutline.Stroke            = outlineBrush;
            _leftOutline.StrokeThickness   = 1.5;
            _leftOutline.Fill              = new SolidColorBrush(Color.FromArgb(20, 240, 160, 160));
            _rightOutline.Stroke           = outlineBrush;
            _rightOutline.StrokeThickness  = 1.5;
            _rightOutline.Fill             = new SolidColorBrush(Color.FromArgb(20, 240, 160, 160));

            _trachea.Stroke                = tracheaBrush;
            _trachea.StrokeThickness       = 1.5;
            _trachea.Fill                  = new SolidColorBrush(Color.FromArgb(25, 240, 180, 180));

            if (_leftDivision  != null) { _leftDivision.Stroke  = fissureBrush; _leftDivision.StrokeThickness  = 1.0; _leftDivision.Fill  = null; }
            if (_rightDivision != null) { _rightDivision.Stroke = fissureBrush; _rightDivision.StrokeThickness = 1.0; _rightDivision.Fill = null; }

            // Fill: bottom-to-top gradient — dark tar/charcoal at the bottom rises into healthy pink at the top.
            // The RectangleGeometry clip already reveals only the bottom portion based on FillFraction.
            var fillBrush = new LinearGradientBrush
            {
                StartPoint = new Point(0.5, 1.0),   // bottom
                EndPoint   = new Point(0.5, 0.0),   // top
                GradientStops = new GradientStopCollection
                {
                    new GradientStop { Color = Color.FromArgb(200, 225, 145, 145), Offset = 0.0 },  // healthy pink at bottom
                    new GradientStop { Color = Color.FromArgb(215, 200,  90,  90), Offset = 0.5 },  // mid — smoky rose
                    new GradientStop { Color = Color.FromArgb(230,  32,  22,  22), Offset = 1.0 }   // tar / charcoal at top
                }
            };
            _leftFill.Fill  = fillBrush;
            // Each path needs its own brush instance
            var fillBrushR = new LinearGradientBrush
            {
                StartPoint = new Point(0.5, 1.0),
                EndPoint   = new Point(0.5, 0.0),
                GradientStops = new GradientStopCollection
                {
                    new GradientStop { Color = Color.FromArgb(200, 225, 145, 145), Offset = 0.0 },
                    new GradientStop { Color = Color.FromArgb(215, 200,  90,  90), Offset = 0.5 },
                    new GradientStop { Color = Color.FromArgb(230,  32,  22,  22), Offset = 1.0 }
                }
            };
            _rightFill.Fill = fillBrushR;
        }

        // ── Helpers ──────────────────────────────────────────────────────────────

        private static PathGeometry Mirror(PathGeometry source, double w)
        {
            var result = new PathGeometry();
            foreach (var fig in source.Figures)
            {
                var newFig = new PathFigure
                {
                    StartPoint = Mx(fig.StartPoint, w),
                    IsClosed   = fig.IsClosed
                };
                foreach (var seg in fig.Segments)
                {
                    switch (seg)
                    {
                        case LineSegment ls:
                            newFig.Segments.Add(new LineSegment { Point = Mx(ls.Point, w) });
                            break;
                        case BezierSegment bs:
                            newFig.Segments.Add(new BezierSegment
                            {
                                Point1 = Mx(bs.Point1, w),
                                Point2 = Mx(bs.Point2, w),
                                Point3 = Mx(bs.Point3, w)
                            });
                            break;
                    }
                }
                result.Figures.Add(newFig);
            }
            return result;
        }

        private static Point Mx(Point p, double w) => new Point(w - p.X, p.Y);
        private static byte  Lerp(int from, int to, double t) =>
            (byte)Math.Clamp((int)(from + (to - from) * t), 0, 255);
    }
}
