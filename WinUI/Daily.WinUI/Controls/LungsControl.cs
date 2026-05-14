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
    /// Draws a stylised pair of lungs.
    /// FillFraction (0–1) controls how much of the lungs is filled with a tar colour —
    /// 0 = healthy pink, 1 = fully blackened.
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

        private Canvas?      _canvas;
        private XamlPath?        _leftOutline;
        private XamlPath?        _rightOutline;
        private XamlPath?        _leftFill;
        private XamlPath?        _rightFill;
        private XamlPath?        _trachea;

        public LungsControl()
        {
            DefaultStyleKey = typeof(LungsControl);
        }

        protected override void OnApplyTemplate()
        {
            base.OnApplyTemplate();
            _canvas       = GetTemplateChild("PART_Canvas")       as Canvas;
            _leftOutline  = GetTemplateChild("PART_LeftOutline")  as XamlPath;
            _rightOutline = GetTemplateChild("PART_RightOutline") as XamlPath;
            _leftFill     = GetTemplateChild("PART_LeftFill")     as XamlPath;
            _rightFill    = GetTemplateChild("PART_RightFill")    as XamlPath;
            _trachea      = GetTemplateChild("PART_Trachea")      as XamlPath;
            Rebuild();
        }

        protected override Size MeasureOverride(Size availableSize)
        {
            double w = double.IsInfinity(availableSize.Width)  ? 260 : availableSize.Width;
            double h = double.IsInfinity(availableSize.Height) ? 280 : availableSize.Height;
            Rebuild(w, h);
            return new Size(w, h);
        }

        // ── Drawing ──────────────────────────────────────────────────────────────

        private void Rebuild() => Rebuild(ActualWidth > 0 ? ActualWidth : 260,
                                          ActualHeight > 0 ? ActualHeight : 280);

        // Build one left-lobe PathGeometry (a fresh instance every call)
        private PathGeometry BuildLeftLobe(double w, double h)
        {
            double cx  = w * 0.50;
            double thy = h * 0.22;
            double lx0 = cx - w * 0.04;
            double lx1 = cx - w * 0.48;
            double ly1 = h  * 0.50;
            double lxb = cx - w * 0.35;
            double lyb = h  * 0.92;
            double lxi = cx - w * 0.06;

            var lobe = new PathGeometry();
            var fig  = new PathFigure { StartPoint = new Point(lx0, thy), IsClosed = true };
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(lx0 - w * 0.30, thy + h * 0.05),
                Point2 = new Point(lx1 - w * 0.04, ly1 - h * 0.15),
                Point3 = new Point(lx1,             ly1)
            });
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(lx1,             ly1 + h * 0.18),
                Point2 = new Point(lxb + w * 0.06,  lyb - h * 0.04),
                Point3 = new Point(lxb,             lyb)
            });
            fig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(lxb + w * 0.10, lyb + h * 0.02),
                Point2 = new Point(lxi,             thy + h * 0.55),
                Point3 = new Point(lxi,             thy + h * 0.08)
            });
            fig.Segments.Add(new LineSegment { Point = new Point(lx0, thy) });
            lobe.Figures.Add(fig);
            return lobe;
        }

        private void Rebuild(double w, double h)
        {
            if (_leftOutline is null) return;

            double fraction = Math.Clamp(FillFraction, 0.0, 1.0);

            double cx  = w * 0.50;
            double ty  = h * 0.08;
            double thy = h * 0.22;

            // Each Path.Data must receive its own geometry instance — WinUI does not
            // allow the same Geometry object to be set on more than one element.
            var leftLobeOutline  = BuildLeftLobe(w, h);
            var rightLobeOutline = Mirror(leftLobeOutline, w);
            var leftLobeFill     = BuildLeftLobe(w, h);
            var rightLobeFill    = Mirror(leftLobeFill, w);

            _leftOutline.Data  = leftLobeOutline;
            _rightOutline.Data = rightLobeOutline;

            // ── Trachea ──────────────────────────────────────────────────────────
            double tw = w * 0.055;
            var tracheaGeom = new PathGeometry();
            var trFig = new PathFigure
            {
                StartPoint = new Point(cx - tw / 2, ty),
                IsClosed   = true
            };
            trFig.Segments.Add(new LineSegment { Point = new Point(cx + tw / 2, ty) });
            trFig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(cx + tw / 2,  ty  + h * 0.08),
                Point2 = new Point(cx + w * 0.06, thy - h * 0.02),
                Point3 = new Point(cx + w * 0.04, thy)
            });
            trFig.Segments.Add(new LineSegment { Point = new Point(cx - w * 0.04, thy) });
            trFig.Segments.Add(new BezierSegment
            {
                Point1 = new Point(cx - w * 0.06, thy - h * 0.02),
                Point2 = new Point(cx - tw / 2,   ty  + h * 0.08),
                Point3 = new Point(cx - tw / 2,   ty)
            });
            tracheaGeom.Figures.Add(trFig);
            _trachea!.Data = tracheaGeom;

            // ── Fill clipping ────────────────────────────────────────────────────
            double clipTop    = h * (1.0 - fraction);
            var    leftClip   = new RectangleGeometry { Rect = new Rect(0, clipTop, w, h - clipTop) };
            var    rightClip  = new RectangleGeometry { Rect = new Rect(0, clipTop, w, h - clipTop) };

            _leftFill!.Data  = leftLobeFill;
            _rightFill!.Data = rightLobeFill;
            _leftFill.Clip   = leftClip;
            _rightFill.Clip  = rightClip;

            // ── Colours ──────────────────────────────────────────────────────────
            // Outline: always slightly pink/rose in dark theme
            var outlineBrush = new SolidColorBrush(Color.FromArgb(200, 240, 180, 180));
            _leftOutline.Stroke   = outlineBrush;
            _rightOutline.Stroke  = outlineBrush;
            _trachea.Stroke       = outlineBrush;
            _trachea.Fill         = new SolidColorBrush(Color.FromArgb(60, 240, 180, 180));

            // Fill: interpolate from healthy pink → tar black
            byte fillA = 210;
            byte fillR = Lerp(220, 30,  fraction);
            byte fillG = Lerp(140, 25,  fraction);
            byte fillB = Lerp(140, 25,  fraction);
            var fillBrush = new SolidColorBrush(Color.FromArgb(fillA, fillR, fillG, fillB));
            _leftFill.Fill  = fillBrush;
            _rightFill.Fill = fillBrush;
        }

        // Mirror all points in a PathGeometry around x = w/2
        private static PathGeometry Mirror(PathGeometry source, double w)
        {
            var result = new PathGeometry();
            foreach (var fig in source.Figures)
            {
                var newFig = new PathFigure
                {
                    StartPoint = MirrorPt(fig.StartPoint, w),
                    IsClosed   = fig.IsClosed
                };
                foreach (var seg in fig.Segments)
                {
                    switch (seg)
                    {
                        case LineSegment ls:
                            newFig.Segments.Add(new LineSegment { Point = MirrorPt(ls.Point, w) });
                            break;
                        case BezierSegment bs:
                            newFig.Segments.Add(new BezierSegment
                            {
                                Point1 = MirrorPt(bs.Point1, w),
                                Point2 = MirrorPt(bs.Point2, w),
                                Point3 = MirrorPt(bs.Point3, w)
                            });
                            break;
                    }
                }
                result.Figures.Add(newFig);
            }
            return result;
        }

        private static Point  MirrorPt(Point p, double w) => new Point(w - p.X, p.Y);
        private static byte   Lerp(int from, int to, double t) =>
            (byte)Math.Clamp((int)(from + (to - from) * t), 0, 255);
    }
}
