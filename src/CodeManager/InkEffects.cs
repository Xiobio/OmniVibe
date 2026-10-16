using System;
using System.IO;
using System.Media;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Shapes;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace CodeManager;

public static class InkEffects
{
    private static DateTime _lastSound;
    public static void Sound(bool enabled, bool capture = false)
    {
        if (!enabled || DateTime.UtcNow - _lastSound < TimeSpan.FromMilliseconds(130)) return;
        _lastSound = DateTime.UtcNow;
        _ = Task.Run(() =>
        {
            try
            {
                const int rate = 22050; int count = (int)(rate * (capture ? .19 : .09)); var random = new Random(8);
                using var stream = new MemoryStream(); using (var w = new BinaryWriter(stream, System.Text.Encoding.ASCII, true))
                {
                    w.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + count * 2); w.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt ")); w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(rate); w.Write(rate * 2); w.Write((short)2); w.Write((short)16); w.Write(System.Text.Encoding.ASCII.GetBytes("data")); w.Write(count * 2);
                    double previous = 0;
                    for (int i = 0; i < count; i++) { double t = i / (double)rate, envelope = Math.Sin(Math.PI * i / count) * Math.Exp(-t * (capture ? 20 : 30)); double noise = random.NextDouble() * 2 - 1; double wave = (noise - previous) * .35 + Math.Sin(t * 2 * Math.PI * (capture ? 680 : 2200)) * .3; previous = noise; w.Write((short)(wave * envelope * 3100)); }
                }
                stream.Position = 0; using var player = new SoundPlayer(stream); player.PlaySync();
            }
            catch (Exception) { /* Audio is optional feedback. */ }
        });
    }
    public static void Sweep(Native.Rect area, double scale, bool enabled, bool capture = false)
    {
        if (!enabled) return;
        var window = new Window { WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, AllowsTransparency = true, Background = Brushes.Transparent, ShowActivated = false, ShowInTaskbar = false, Topmost = true, IsHitTestVisible = false, Left = area.Left / scale, Top = area.Top / scale, Width = (area.Right - area.Left) / scale, Height = (area.Bottom - area.Top) / scale };
        var canvas = new Canvas { ClipToBounds = true, IsHitTestVisible = false };
        var ink = new Border { Width = window.Width * .45, Height = window.Height, Opacity = .34, Background = new LinearGradientBrush(new GradientStopCollection { new GradientStop(Colors.Transparent, 0), new GradientStop(Color.FromRgb(13, 28, 21), .4), new GradientStop(Color.FromRgb(160, 208, 159), .53), new GradientStop(Colors.Transparent, 1) }, 0) };
        var move = new TranslateTransform(-ink.Width, 0); ink.RenderTransform = move; canvas.Children.Add(ink); window.Content = canvas;
        window.SourceInitialized += (_, _) => Native.Decorate(window, clickThrough: true);
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(capture ? 230 : 160) };
        timer.Tick += (_, _) => { timer.Stop(); window.Close(); };
        window.Show(); move.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-ink.Width, window.Width, TimeSpan.FromMilliseconds(capture ? 220 : 150)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } });
        ink.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(.34, 0, timer.Interval)); timer.Start();
    }
    public static void Ripple(FrameworkElement target)
    {
        if (!target.IsVisible || target.ActualWidth < 1 || target.ActualHeight < 1) return;
        var scale = PresentationSource.FromVisual(target)?.CompositionTarget?.TransformToDevice.M11 ?? 1;
        var center = target.PointToScreen(new Point(target.ActualWidth / 2, target.ActualHeight / 2));
        var window = new Window { WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, AllowsTransparency = true, Background = Brushes.Transparent, ShowActivated = false, ShowInTaskbar = false, Topmost = true, IsHitTestVisible = false, Width = 150, Height = 150, Left = center.X / scale - 75, Top = center.Y / scale - 75 };
        var ring = new Ellipse { Width = 105, Height = 105, Stroke = WuxiaTheme.Jade, StrokeThickness = 1.5, Opacity = .6, RenderTransformOrigin = new Point(.5, .5) };
        var zoom = new ScaleTransform(.4, .4); ring.RenderTransform = zoom; window.Content = ring;
        window.SourceInitialized += (_, _) => Native.Decorate(window, clickThrough: true);
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(330) }; timer.Tick += (_, _) => { timer.Stop(); window.Close(); };
        window.Show();
        var pulse = new DoubleAnimation(.4, 1.4, TimeSpan.FromMilliseconds(320)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
        zoom.BeginAnimation(ScaleTransform.ScaleXProperty, pulse); zoom.BeginAnimation(ScaleTransform.ScaleYProperty, pulse);
        ring.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(.6, 0, TimeSpan.FromMilliseconds(320))); timer.Start();
    }
}
