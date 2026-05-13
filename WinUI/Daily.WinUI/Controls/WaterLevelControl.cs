using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;

namespace Daily_WinUI.Controls
{
    public class WaterLevelControl : Control
    {
        // FILL mode when FullHeight > 0: walls match the glass, no stroke.
        // OUTLINE mode when FullHeight == 0: full trapezoid with stroke.
        public static readonly DependencyProperty FullHeightProperty =
            DependencyProperty.Register(nameof(FullHeight), typeof(double), typeof(WaterLevelControl),
                new PropertyMetadata(0.0, (d, _) => ((WaterLevelControl)d).InvalidateMeasure()));

        public double FullHeight
        {
            get => (double)GetValue(FullHeightProperty);
            set => SetValue(FullHeightProperty, value);
        }

        private Microsoft.UI.Xaml.Shapes.Path? path;

        public WaterLevelControl()
        {
            this.DefaultStyleKey = typeof(WaterLevelControl);
        }

        protected override void OnApplyTemplate()
        {
            this.path = this.GetTemplateChild("PART_Path") as Microsoft.UI.Xaml.Shapes.Path;
            base.OnApplyTemplate();
            InvalidateMeasure();
        }

        private static PathGeometry CreateRoundedTrapezoidGeometry(Point topLeft, Point topRight, Point botRight, Point botLeft, double cornerRadius)
        {
            var corners = new[] { topLeft, topRight, botRight, botLeft };
            var entryPoints = new Point[corners.Length];
            var exitPoints = new Point[corners.Length];

            for (int i = 0; i < corners.Length; i++)
            {
                var prev = corners[(i - 1 + corners.Length) % corners.Length];
                var current = corners[i];
                var next = corners[(i + 1) % corners.Length];

                var toPrev = Normalize(new Point(prev.X - current.X, prev.Y - current.Y));
                var toNext = Normalize(new Point(next.X - current.X, next.Y - current.Y));

                var maxRadius = Math.Min(Distance(current, prev), Distance(current, next)) * 0.45;
                var radius = Math.Min(cornerRadius, maxRadius);

                entryPoints[i] = new Point(current.X + (toPrev.X * radius), current.Y + (toPrev.Y * radius));
                exitPoints[i] = new Point(current.X + (toNext.X * radius), current.Y + (toNext.Y * radius));
            }

            var figure = new PathFigure { StartPoint = exitPoints[0], IsClosed = true };

            for (int i = 1; i < corners.Length; i++)
            {
                figure.Segments.Add(new LineSegment { Point = entryPoints[i] });
                AddRoundedCorner(figure, corners[i], entryPoints[i], exitPoints[i]);
            }

            figure.Segments.Add(new LineSegment { Point = entryPoints[0] });
            AddRoundedCorner(figure, corners[0], entryPoints[0], exitPoints[0]);

            var geometry = new PathGeometry();
            geometry.Figures.Add(figure);
            return geometry;
        }

        private static void AddRoundedCorner(PathFigure figure, Point corner, Point start, Point end)
        {
            // Quadratic-to-cubic conversion for smooth corner rounding.
            var c1 = new Point(start.X + ((2.0 / 3.0) * (corner.X - start.X)), start.Y + ((2.0 / 3.0) * (corner.Y - start.Y)));
            var c2 = new Point(end.X + ((2.0 / 3.0) * (corner.X - end.X)), end.Y + ((2.0 / 3.0) * (corner.Y - end.Y)));
            figure.Segments.Add(new BezierSegment { Point1 = c1, Point2 = c2, Point3 = end });
        }

        private static Point Normalize(Point vector)
        {
            var length = Math.Sqrt((vector.X * vector.X) + (vector.Y * vector.Y));
            return length <= 0.00001 ? new Point(0, 0) : new Point(vector.X / length, vector.Y / length);
        }

        private static double Distance(Point a, Point b)
        {
            var dx = a.X - b.X;
            var dy = a.Y - b.Y;
            return Math.Sqrt((dx * dx) + (dy * dy));
        }

        protected override Size MeasureOverride(Size availableSize)
        {
            double width  = double.IsInfinity(availableSize.Width)  ? 280.0 : availableSize.Width;
            double height = double.IsInfinity(availableSize.Height) ? 280.0 : availableSize.Height;

            if (width > 0 && height > 0 && this.path != null)
            {
                double fullH = FullHeight > 0 ? FullHeight : height;
                bool isFill = FullHeight > 0;

                if (isFill)
                {
                    // Fill: no stroke; walls follow the glass taper at the current fill level
                    this.path.StrokeThickness = 0;

                    // At full height: left inset = 5% (top of glass)
                    // At zero height: left inset = 22% (bottom of glass)
                    // Interpolate by how much of the glass remains from the top to the water surface
                    double fillFraction = height / fullH;
                    double topInset = width * (0.22 - 0.17 * fillFraction);
                    double botInset = width * 0.22;

                    var topLeft  = new Point(topInset,          0);
                    var topRight = new Point(width - topInset,  0);
                    var botRight = new Point(width - botInset,  height);
                    var botLeft  = new Point(botInset,          height);

                    this.path.Data = CreateRoundedTrapezoidGeometry(topLeft, topRight, botRight, botLeft, Math.Max(4.0, width * 0.03));
                }
                else
                {
                    // Outline: stroke visible, transparent fill
                    const double st = 2.0;
                    this.path.StrokeThickness = st;
                    this.path.StrokeLineJoin = PenLineJoin.Round;
                    double s = st / 2.0;

                    double topInset = width * 0.05 + s;
                    double botInset = width * 0.22 + s;

                    var topLeft  = new Point(topInset,          s);
                    var topRight = new Point(width - topInset,  s);
                    var botRight = new Point(width - botInset,  height - s);
                    var botLeft  = new Point(botInset,          height - s);

                    this.path.Data = CreateRoundedTrapezoidGeometry(topLeft, topRight, botRight, botLeft, Math.Max(5.0, width * 0.035));
                }
            }

            return new Size(width, height);
        }
    }
}
