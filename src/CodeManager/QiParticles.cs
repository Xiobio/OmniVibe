using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
namespace CodeManager;
public sealed class QiParticles : FrameworkElement
{
    public QiParticles() : this(false) { }
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(40) };
    private readonly Stopwatch _clock = new();
    private bool _enabled;
    public void SetEnabled(bool enabled) { _enabled = enabled; if (enabled && IsVisible) { _clock.Start(); _timer.Start(); } else { _timer.Stop(); _clock.Stop(); } }
    public QiParticles(bool animate)
    {
        IsHitTestVisible = false;
        _timer.Tick += (_, _) => InvalidateVisual();
        _enabled = animate;
        Loaded += (_, _) => SetEnabled(_enabled);
        IsVisibleChanged += (_, _) => SetEnabled(_enabled);
        Unloaded += (_, _) => { _timer.Stop(); _clock.Stop(); };
    }
    protected override void OnRender(DrawingContext dc)
    {
        double t = _clock.Elapsed.TotalSeconds; var random = new Random(81);
        for (int i = 0; i < 36; i++)
        {
            double x = random.NextDouble() * ActualWidth, phase = random.NextDouble();
            double y = ActualHeight * (1 - ((phase + t * (.025 + i % 3 * .008)) % 1)); x += Math.Sin(t * .6 + i) * 22;
            double radius = 1 + i % 3; double alpha = .2 + .55 * Math.Pow(Math.Sin(t * .9 + i), 2);
            dc.PushOpacity(alpha * .28); dc.DrawEllipse(i % 3 == 0 ? WuxiaTheme.Gold : WuxiaTheme.Jade, null, new Point(x, y), radius * 4, radius * 4); dc.Pop();
            dc.PushOpacity(alpha); dc.DrawLine(new Pen(i % 3 == 0 ? WuxiaTheme.Gold : WuxiaTheme.Jade, 1), new Point(x - 5, y + 9), new Point(x + 2, y - 3)); dc.Pop();
        }
    }
}
