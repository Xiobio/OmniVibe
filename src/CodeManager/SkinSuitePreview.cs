using System;
using System.Globalization;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace CodeManager;

/// <summary>A local sample scene. It never changes the active skin or reads real tasks.</summary>
public sealed class SkinSuitePreview : FrameworkElement
{
    private static readonly IReadOnlyList<Slot> DemoLoadout = new AppState().Slots;
    private SkinDefinition _skin = SkinCatalog.All[0];
    private BitmapSource? _art, _terminal;
    private System.Drawing.Image? _gif;
    private MemoryStream? _gifStream;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(100) };
    private int _frame, _frames;
    private bool _effects = true, _decorations = true;
    private Brush? _cardMaterial;
    private readonly Dictionary<string, Brush> _brushes = new();
    private readonly Dictionary<(string Value, double Size, string Color, double Width, bool Bold, double Dpi), FormattedText> _texts = new();
    private string _mode = "suite";
    public string Mode { get => _mode; set { if (_mode == value) return; _mode = value; if (_mode is "suite" or "terminal") LoadAnimation(); else DisposeAnimation(); UpdatePlayback(); InvalidateVisual(); } }
    public string AssetStatus { get; private set; } = "";
    public int OpenAnimationCount => _gif == null ? 0 : 1;
    public bool IsPlaying => _timer.IsEnabled;
    public Skin PreviewSkin => _skin.Id;
    public event Action? AssetStatusChanged;
    public SkinSuitePreview()
    {
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        ClipToBounds = true; MinHeight = 200;
        _timer.Tick += (_, _) =>
        {
            if (_gif != null && _mode is "suite" or "terminal")
            {
                try { _frame = (_frame + 1) % _frames; _gif.SelectActiveFrame(System.Drawing.Imaging.FrameDimension.Time, _frame); _terminal = DecodeFrame(_gif); }
                catch (Exception ex) when (ex is ArgumentException or ExternalException) { DisposeAnimation(); UpdatePlayback(); AssetStatus = "动效暂不可用，已显示静态预览"; AssetStatusChanged?.Invoke(); }
            }
            InvalidateVisual();
        };
        IsVisibleChanged += (_, _) => UpdatePlayback();
        Loaded += (_, _) => { LoadAnimation(); UpdatePlayback(); };
        Unloaded += (_, _) => { _timer.Stop(); DisposeAnimation(); };
    }
    public void SetSkin(Skin skin, bool effects, bool decorations)
    {
        _skin = SkinCatalog.Get(skin); _effects = effects; _decorations = decorations;
        NativeSkinArt.Warm(_skin);
        _brushes.Clear(); _texts.Clear(); _cardMaterial = decorations ? SkinMaterials.Create(_skin, true) : null;
        DisposeAnimation();
        _art = decorations ? Bitmap(_skin.Artwork) : null;
        if (skin == Skin.InkJade && decorations) _art ??= Bitmap("themes/windows-terminal/assets/ink-jade-ornate-v2.png");
        string suffix = decorations ? "c-v1" : "frame-only-v1";
        _terminal = Bitmap($"themes/windows-terminal/assets/refined-v1/{_skin.Slug}-{suffix}.png");
        if (skin == Skin.InkJade && decorations) _terminal ??= Bitmap("themes/windows-terminal/assets/ink-jade-ornate-v2.png");
        AssetStatus = skin == Skin.InkJade ? "墨玉使用已有插画资源 · 场景文字为示例" : (int)skin < (int)Skin.Hextech ? "经典主题暂未提供独立 Terminal 套装" : _terminal == null ? "Terminal 资源未找到，显示配色回退" : "Terminal 使用实际背景资源 · 原生组件为布局示意";
        if (IsLoaded) LoadAnimation();
        UpdatePlayback(); InvalidateVisual(); AssetStatusChanged?.Invoke();
    }
    private void UpdatePlayback()
    {
        if (IsLoaded && IsVisible && _effects && _gif != null && _frames > 1 && (_mode is "suite" or "terminal")) _timer.Start(); else _timer.Stop();
    }
    private void LoadAnimation()
    {
        if (!IsLoaded || _mode is not ("suite" or "terminal") || _gif != null || !_effects || ((int)_skin.Id < (int)Skin.Hextech && _skin.Id != Skin.InkJade) || (_skin.Id == Skin.InkJade && !_decorations)) return;
        string suffix = _decorations ? "c-v1" : "frame-only-v1";
        string path = Path.Combine(AppContext.BaseDirectory, $"themes/windows-terminal/assets/refined-v1/{_skin.Slug}-{suffix}.gif");
        if (_skin.Id == Skin.InkJade) path = Path.Combine(AppContext.BaseDirectory, "themes/windows-terminal/assets/ink-jade-background-v5.gif");
        if (!File.Exists(path)) return;
        try
        {
            _gifStream = new MemoryStream(File.ReadAllBytes(path));
            _gif = System.Drawing.Image.FromStream(_gifStream);
            _frames = _gif.GetFrameCount(System.Drawing.Imaging.FrameDimension.Time); _frame = 0;
            _terminal = DecodeFrame(_gif);
        }
        catch (Exception ex) when (ex is IOException or ArgumentException or ExternalException) { DisposeAnimation(); AssetStatus = "动效暂不可用，已显示静态预览"; }
    }
    private void DisposeAnimation() { _gif?.Dispose(); _gif = null; _gifStream?.Dispose(); _gifStream = null; _frames = 0; }
    private static BitmapSource DecodeFrame(System.Drawing.Image image)
    {
        using var bitmap = new System.Drawing.Bitmap(640, 377, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        using (var g = System.Drawing.Graphics.FromImage(bitmap)) g.DrawImage(image, 0, 0, 640, 377);
        var data = bitmap.LockBits(new System.Drawing.Rectangle(0, 0, 640, 377), System.Drawing.Imaging.ImageLockMode.ReadOnly, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        try
        {
            var pixels = new byte[640 * 377 * 4]; Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
            var result = BitmapSource.Create(640, 377, 96, 96, PixelFormats.Pbgra32, null, pixels, data.Stride); result.Freeze(); return result;
        }
        finally { bitmap.UnlockBits(data); }
    }
    private static BitmapSource? Bitmap(string relative)
    {
        string path = Path.Combine(AppContext.BaseDirectory, relative.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(path)) return null;
        try { var b = new BitmapImage(); b.BeginInit(); b.CacheOption = BitmapCacheOption.OnLoad; b.DecodePixelWidth = 1280; b.UriSource = new Uri(path); b.EndInit(); b.Freeze(); return b; }
        catch (Exception ex) when (ex is IOException or NotSupportedException or FileFormatException) { return null; }
    }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc); if (ActualWidth < 1 || ActualHeight < 1) return;
        dc.DrawRectangle(B(_skin.Background), null, new Rect(0, 0, ActualWidth, ActualHeight));
        double scale = Math.Min(ActualWidth / 960, ActualHeight / 490);
        dc.PushTransform(new TranslateTransform((ActualWidth - 960 * scale) / 2, (ActualHeight - 490 * scale) / 2));
        dc.PushTransform(new ScaleTransform(scale, scale));
        dc.DrawRectangle(B(_skin.Background), null, new Rect(0, 0, 960, 490));
        if (_decorations && _art != null) { dc.PushOpacity(_skin.IsLight ? .13 : .16); dc.DrawImage(_art, new Rect(0, 0, 960, 490)); dc.Pop(); }
        // A faint grid anchors the miniature windows without competing with text.
        dc.PushOpacity(.08);
        for (int x = 0; x < 960; x += 32) dc.DrawLine(new Pen(B(_skin.Muted), .5), new Point(x, 0), new Point(x, 490));
        dc.Pop();
        Text(dc, _skin.Name, 24, 18, 22, _skin.Text, 740, true);
        Text(dc, "示例工作台 / 预览不修改当前任务", 24, 49, 12, _skin.Muted, 700);
        switch (_mode)
        {
            case "terminal": Terminal(dc, new Rect(24, 85, 912, 375)); break;
            case "dock":
                Ring(dc, new Point(310, 275), 160);
                Text(dc, "固定槽位，快速唤出", 575, 130, 24, _skin.Text, 320, true);
                Text(dc, "01  网站重构\n02  接口检查\n03  测试补齐\n\n运行、等待与已回复分别标记。\n这里只演示外观，不操作窗口。", 575, 181, 16, _skin.Muted, 315); break;
            case "overview": Overview(dc, new Rect(24, 85, 912, 375), true); break;
            case "states": Menu(dc, new Rect(40, 95, 340, 342)); States(dc, 435, 112); break;
            default:
                Terminal(dc, new Rect(24, 92, 514, 312));
                Overview(dc, new Rect(558, 92, 378, 207), false);
                Ring(dc, new Point(751, 388), 74);
                Text(dc, "TERMINAL", 25, 73, 10, _skin.Muted, 300, true);
                Text(dc, "任务总览", 559, 73, 11, _skin.Muted, 300, true);
                Text(dc, "圆环与槽位", 558, 326, 12, _skin.Muted, 120);
                Text(dc, "同一套材质、状态与配色", 24, 426, 15, _skin.Text, 500);
                Swatches(dc, 24, 455); break;
        }
        dc.Pop(); dc.Pop();
    }
    private Brush B(string color)
    {
        if (!_brushes.TryGetValue(color, out var brush)) _brushes[color] = brush = WuxiaTheme.Brush(color);
        return brush;
    }
    private void Text(DrawingContext dc, string value, double x, double y, double size, string color, double width, bool bold = false)
    {
        var key = (value, size, color, width, bold, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        if (!_texts.TryGetValue(key, out var text)) _texts[key] = text = new FormattedText(value, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface(new FontFamily("Microsoft YaHei UI, Segoe UI"), FontStyles.Normal, bold ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal), size, B(color), key.Item6) { MaxTextWidth = Math.Max(1, width), Trimming = TextTrimming.CharacterEllipsis };
        dc.DrawText(text, new Point(x, y));
    }
    private void Plate(DrawingContext dc, Rect r, string fill, string? edge = null, double radius = 9)
        => dc.DrawRoundedRectangle(B(fill), new Pen(B(edge ?? _skin.Border), 1), r, radius, radius);
    private void Terminal(DrawingContext dc, Rect r)
    {
        dc.PushClip(new RectangleGeometry(r, 8, 8));
        dc.DrawRectangle(B(_skin.Background), null, r);
        var body = new Rect(r.X, r.Y + 27, r.Width, r.Height - 27);
        // The selected static asset already represents the artwork/frame-only choice.
        // Motion being off must not hide the frame-only PNG that the applier installs.
        if (_terminal != null) dc.DrawImage(_terminal, body);
        dc.DrawRectangle(B(_skin.Surface), null, new Rect(r.X, r.Y, r.Width, 27));
        Text(dc, "●  OmniVibe / 示例 Terminal", r.X + 12, r.Y + 6, 11, _skin.Text, r.Width - 70);
        Text(dc, "−  □  ×", r.Right - 57, r.Y + 6, 11, _skin.Muted, 55);
        if ((int)_skin.Id < (int)Skin.Hextech && _skin.Id != Skin.InkJade)
        {
            Text(dc, "此经典主题暂无独立 Terminal 套装", body.X + 28, body.Y + 45, 18, _skin.Text, body.Width - 56, true);
            Text(dc, "原生圆环、任务总览与菜单仍可在其他页预览。", body.X + 28, body.Y + 83, 13, _skin.Muted, body.Width - 56);
        }
        else
        {
            double font = r.Width > 700 ? 19 : 13, step = font * 1.85;
            double x = body.X + body.Width * .045, y = body.Y + 25;
            foreach (var (line, color) in new[] { ("$ codex resume --last", _skin.Text), ("正在检查任务恢复与窗口切换…", _skin.Muted), ("", _skin.Text), ("✓ 任务与窗口绑定保持不变", _skin.Running), ("✓ 外框与正文区域分离", _skin.Running), ("! 等待你的下一条指令", _skin.Waiting) }) { Text(dc, line, x, y, font, color, body.Width * .75); y += step; }
        }
        dc.Pop(); dc.DrawRoundedRectangle(null, new Pen(B(_skin.Border), 1), r, 8, 8);
    }
    private void Overview(DrawingContext dc, Rect r, bool large)
    {
        Plate(dc, r, _skin.Surface);
        Text(dc, _skin.OverviewTitle, r.X + 14, r.Y + 10, large ? 21 : 14, _skin.Text, r.Width - 30, true);
        double top = large ? 54 : 37, gap = large ? 12 : 7;
        double w = (r.Width - gap * 4) / 3, h = (r.Height - top - gap * 4) / 3;
        string[] names = { "网站重构", "接口检查", "测试补齐", "文档更新", "状态未知", "窗口断开", "空槽位", "空槽位", "空槽位" };
        string[] colors = { _skin.Running, _skin.Waiting, _skin.Ready, _skin.Error, _skin.Unknown, _skin.Unknown };
        for (int i = 0; i < 9; i++)
        {
            var c = new Rect(r.X + gap + i % 3 * (w + gap), r.Y + top + i / 3 * (h + gap), w, h);
            dc.PushClip(new RectangleGeometry(c, Math.Min(8, _skin.CornerRadius), Math.Min(8, _skin.CornerRadius)));
            dc.DrawRectangle(_cardMaterial ?? B(_skin.CardBackground), new Pen(B(i == 0 ? _skin.Accent : _skin.Border), i == 0 ? 2 : .7), c);
            if (_decorations) NativeSkinArt.Frame(dc, _skin, c, large ? 21 : 12);
            double fs = large ? 15 : 10;
            double portrait = large ? 78 : 34;
            if (i < 6) EquipmentCatalog.Draw(dc, DemoLoadout[i], new Rect(c.Right-portrait-8, c.Y+3, portrait, c.Height-6), skin: _skin.Id);
            Text(dc, (i + 1).ToString("00") + "  " + (i < 6 ? EquipmentCatalog.Name(DemoLoadout[i], _skin.Id) : "+ 空槽位"), c.X + 9, c.Y + 9, fs, _skin.CardText, w - (i < 6 ? portrait + 18 : 18), true);
            if (large && i < 6) Text(dc, names[i], c.X+9, c.Y+32, 11, _skin.CardText, w-portrait-18);
            if (i < 6) { dc.DrawEllipse(B(colors[i]), null, new Point(c.X + 12, c.Bottom - (large ? 17 : 10)), 2.5, 2.5); Text(dc, new[] { "运行中", "等待处理", "本轮已回复", "错误示例", "未知", "已断开" }[i], c.X + 21, c.Bottom - (large ? 25 : 17), large ? 12 : 9, _skin.CardText, w - portrait - 28); }
            dc.Pop();
        }
    }
    private void Ring(DrawingContext dc, Point c, double radius)
    {
        WeaponRing(dc, c, radius);
    }
    private void WeaponRing(DrawingContext dc, Point c, double radius)
    {
        var slots = DemoLoadout;
        EquipmentCatalog.Draw(dc, slots[0], new Rect(c.X - radius * .37, c.Y - radius * .37, radius * .74, radius * .74), skin: _skin.Id);
        for (int i = 0; i < 9; i++) {
            double a = (i * 40 - 90) * Math.PI / 180;
            var p = new Point(c.X + Math.Cos(a) * radius * .85, c.Y + Math.Sin(a) * radius * .85);
            var r = new Rect(p.X - radius * .25, p.Y - radius * .22, radius * .5, radius * .44);
            if (i >= 6) {
                dc.PushOpacity(.35); dc.DrawRoundedRectangle(B(_skin.Surface), new Pen(B(_skin.Muted), .6), new Rect(p.X-radius*.1,p.Y-radius*.1,radius*.2,radius*.2),4,4); dc.Pop();
                Text(dc,"+",p.X-radius*.04,p.Y-radius*.08,Math.Max(9,radius*.13),_skin.Muted,20);
                continue;
            }
            if (_decorations && _skin.Id != Skin.Arsenal) { dc.PushOpacity(.35); EquipmentPedestal.Draw(dc,_skin,new Rect(r.X+r.Width*.1,r.Bottom-3,r.Width*.8,6)); dc.Pop(); }
            EquipmentCatalog.Draw(dc, slots[i], r, skin: _skin.Id);
            Text(dc, (i + 1).ToString(), r.X, r.Bottom - 10, Math.Max(8, radius * .065), _skin.Accent, 20, true);
        }
    }
    private void Menu(DrawingContext dc, Rect r)
    {
        Plate(dc, r, _skin.Surface);
        Text(dc, "右键菜单", r.X + 22, r.Y + 16, 12, _skin.Muted, r.Width - 44);
        int i = 0;
        foreach (string item in new[] { "打开任务总览", "唤出窗口", "编辑任务与项目…", "连接自动任务状态", "移出列表，保留窗口" })
        {
            double y = r.Y + 60 + i * 51;
            if (i == 1) dc.DrawRoundedRectangle(B(_skin.Elevated), null, new Rect(r.X + 10, y - 9, r.Width - 20, 43), 5, 5);
            Text(dc, item, r.X + 23, y, 16, _skin.Text, r.Width - 40); i++;
        }
    }
    private void States(DrawingContext dc, double x, double y)
    {
        Text(dc, "每种状态，都能一眼识别", x, y, 23, _skin.Text, 460, true);
        int i = 0;
        foreach (var (label, color) in new[] { ("运行中 · 正在执行", _skin.Running), ("等待处理 · 需要你决策", _skin.Waiting), ("本轮已回复 · 可继续跟进", _skin.Ready), ("错误 · 示例警示状态", _skin.Error), ("未知 · 尚未接入状态事件", _skin.Unknown) })
        {
            double top = y + 61 + i * 47; dc.DrawEllipse(B(color), null, new Point(x + 5, top + 10), 5, 5);
            Text(dc, label, x + 24, top, 17, color, 435); i++;
        }
    }
    private void Swatches(DrawingContext dc, double x, double y)
    {
        int i = 0; foreach (string color in new[] { _skin.Accent, _skin.Secondary, _skin.Running, _skin.Waiting, _skin.Ready, _skin.Error }) { dc.DrawRoundedRectangle(B(color), null, new Rect(x + i * 32, y, 23, 6), 3, 3); i++; }
    }
}
