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

                    PathFigure fig = new PathFigure { StartPoint = topLeft, IsClosed = true };
                    fig.Segments.Add(new LineSegment { Point = topRight });
                    fig.Segments.Add(new LineSegment { Point = botRight });
                    fig.Segments.Add(new LineSegment { Point = botLeft });

                    var geom = new PathGeometry();
                    geom.Figures.Add(fig);
                    this.path.Data = geom;
                }
                else
                {
                    // Outline: stroke visible, transparent fill
                    const double st = 2.0;
                    this.path.StrokeThickness = st;
                    double s = st / 2.0;

                    double topInset = width * 0.05 + s;
                    double botInset = width * 0.22 + s;

                    var topLeft  = new Point(topInset,          s);
                    var topRight = new Point(width - topInset,  s);
                    var botRight = new Point(width - botInset,  height - s);
                    var botLeft  = new Point(botInset,          height - s);

                    PathFigure fig = new PathFigure { StartPoint = topLeft, IsClosed = true };
                    fig.Segments.Add(new LineSegment { Point = topRight });
                    fig.Segments.Add(new LineSegment { Point = botRight });
                    fig.Segments.Add(new LineSegment { Point = botLeft });

                    var geom = new PathGeometry();
                    geom.Figures.Add(fig);
                    this.path.Data = geom;
                }
            }

            return new Size(width, height);
        }
    }
}
