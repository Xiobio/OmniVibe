using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace CodeManager;

/// <summary>One window-switch signature, with selection and imports kept in a settings draft.</summary>
public sealed class AudioSettingsPanel : StackPanel
{
    private sealed record OverrideDraft(Skin Skin, string? Source);
    private readonly List<OverrideDraft> _overrides = new();
    private readonly CheckBox _enabled;
    private readonly Slider _volume;
    private readonly ComboBox _theme = new();
    private readonly Func<Skin> _previewSkin;
    private readonly TextBlock _description = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 4), FontSize = 12 };
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 9, 0, 0), FontSize = 12 };
    private readonly TextBlock _auditionStatus = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0), FontSize = 11 };

    public AudioSettingsPanel(Preferences source, Func<Skin> previewSkin)
    {
        _previewSkin = previewSkin;
        var controls = Section("窗口切换音", "切换到终端时播放一声游戏标志音；其他操作保持安静。");
        _enabled = new CheckBox { Content = "启用窗口切换音", IsChecked = source.SoundEffects, Margin = new Thickness(0, 3, 0, 12) };
        controls.Children.Add(_enabled);
        _enabled.Click += (_, _) => { if (_enabled.IsChecked != true) GameAudio.Stop(); };
        Caption(controls, "声音主题");
        _theme.MinHeight = 36;
        _theme.Items.Add(new ComboBoxItem { Content = "跟随界面主题" });
        foreach (var skin in SkinCatalog.All) _theme.Items.Add(new ComboBoxItem { Content = skin.Name, Tag = skin.Id });
        _theme.SelectedItem = source.SoundTheme is Skin selected
            ? _theme.Items.OfType<ComboBoxItem>().FirstOrDefault(x => x.Tag is Skin id && id == selected) ?? _theme.Items[0]
            : _theme.Items[0];
        controls.Children.Add(_theme);
        _description.Foreground = WuxiaTheme.Brush(SkinCatalog.Current.Muted); controls.Children.Add(_description);
        var volumeLabel = Caption(controls, "音量");
        _volume = new Slider { Minimum = 0, Maximum = 100, Value = double.IsFinite(source.SoundVolume) ? Math.Clamp(source.SoundVolume * 100, 0, 100) : 45, TickFrequency = 5, IsSnapToTickEnabled = true, Margin = new Thickness(0, 7, 0, 12) };
        void UpdateVolume() => volumeLabel.Text = "音量  " + Math.Round(_volume.Value) + "%";
        _volume.ValueChanged += (_, _) => UpdateVolume(); UpdateVolume(); controls.Children.Add(_volume);
        var playback = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) }; controls.Children.Add(playback);
        var preview = Action("试听切换音"); preview.Click += (_, _) => Audition(); playback.Children.Add(preview);
        var stop = Action("停止试听"); stop.Click += (_, _) => GameAudio.Stop(); playback.Children.Add(stop);
        _auditionStatus.Foreground = WuxiaTheme.Brush(SkinCatalog.Current.Muted); controls.Children.Add(_auditionStatus);

        var custom = Section("自定义标志音", "为所选声音主题导入一段 WAV；按「保存并应用」后生效。关闭或取消设置会保留原声音。");
        var customCard = Children[Children.Count - 1]; Children.Remove(customCard);
        Children.Add(new Expander { Header = "自定义声音文件", Content = customCard, Margin = new Thickness(0, 4, 0, 12) });
        var actions = new WrapPanel(); custom.Children.Add(actions);
        var import = Action("导入 WAV…"); var reset = Action("恢复默认声音"); actions.Children.Add(import); actions.Children.Add(reset);
        _status.Foreground = WuxiaTheme.Brush(SkinCatalog.Current.Muted); custom.Children.Add(_status);
        import.Click += (_, _) =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog { Title = "选择窗口切换标志音", Filter = "WAV 音频|*.wav", CheckFileExists = true };
            if (dialog.ShowDialog(Window.GetWindow(this)) != true) return;
            if (!GameAudio.ValidateWave(dialog.FileName, out string error)) { _status.Text = "请选择不超过 3 秒的 PCM16 WAV（单声道或立体声，16–96 kHz）。\n" + error; return; }
            QueueOverride(dialog.FileName); UpdateDescription();
        };
        reset.Click += (_, _) => { QueueOverride(null); UpdateDescription(); };
        _theme.SelectionChanged += (_, _) => { GameAudio.Stop(); UpdateDescription(); };
        // Reopening a page refreshes the follow-theme description, never the user's
        // explicit draft selection. The source preference is only read on creation.
        IsVisibleChanged += (_, _) => { if (IsVisible) UpdateDescription(); else GameAudio.Stop(); };
        Unloaded += (_, _) => GameAudio.Stop();
        UpdateDescription();
    }

    private Skin? ThemeOverride => _theme.SelectedItem is ComboBoxItem { Tag: Skin skin } ? skin : null;
    private Skin SelectedSkin => ThemeOverride ?? _previewSkin();
    private void UpdateDescription()
    {
        Skin skin = SelectedSkin;
        _description.Text = (ThemeOverride == null ? "当前跟随：" + SkinCatalog.Get(skin).Name + "\n" : "") + SignatureAudio.Description(skin);
        var draft = _overrides.LastOrDefault(x => x.Skin == skin);
        string path = draft == null ? SignatureAudio.GetPath(skin) : draft.Source ?? SignatureAudio.DefaultPath(skin);
        if (!File.Exists(path)) _description.Text += "\n尚未安装 · 当前静音，可导入自己的 WAV。";
        _status.Text = draft != null
            ? draft.Source == null ? "待保存：恢复默认声音" : "待保存：" + Path.GetFileName(draft.Source)
            : File.Exists(path) ? "已就绪 · " + Path.GetFileName(path) : "尚未安装此主题的标志音，可导入自己的 WAV。";
        if (draft?.Source == null && !File.Exists(path) && draft != null) _status.Text += " · 默认声音未安装，恢复后将保持静音。";
    }
    private void QueueOverride(string? source)
    {
        Skin skin = SelectedSkin;
        _overrides.RemoveAll(x => x.Skin == skin);
        _overrides.Add(new(skin, source));
    }
    private void Audition()
    {
        Skin skin = SelectedSkin;
        var draft = _overrides.LastOrDefault(x => x.Skin == skin);
        string path = draft == null ? SignatureAudio.GetPath(skin) : draft.Source ?? SignatureAudio.DefaultPath(skin);
        if (!File.Exists(path)) { GameAudio.Stop(); _auditionStatus.Text = "此主题的标志音尚未安装，当前保持静音。"; return; }
        GameAudio.PreviewFile(skin, AudioCue.Switch, path, _volume.Value / 100);
        _auditionStatus.Text = SkinCatalog.Get(skin).Name + " · " + (draft == null ? "窗口切换音" : "试听待保存声音") + " · " + Math.Round(_volume.Value) + "%";
    }
    public bool TryCommit(Preferences result, out string error)
    {
        if (!AudioOverrideTransaction.TryApply(_overrides.Select(x => new AudioOverrideChange(x.Skin, AudioCue.Switch, null, x.Source)).ToArray(), out error)) return false;
        result.SoundEffects = _enabled.IsChecked == true;
        result.SoundVolume = _volume.Value / 100;
        result.SoundTheme = ThemeOverride;
        GameAudio.Stop(); return true;
    }
    private StackPanel Section(string title, string description)
    {
        var skin = SkinCatalog.Current; var body = new StackPanel();
        body.Children.Add(new TextBlock { Text = title, FontSize = 17, FontWeight = FontWeights.SemiBold });
        body.Children.Add(new TextBlock { Text = description, FontSize = 12, Foreground = WuxiaTheme.Brush(skin.Muted), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 7, 0, 12) });
        Children.Add(new Border { Background = WuxiaTheme.Brush(skin.Surface), BorderBrush = WuxiaTheme.Brush(skin.Border), BorderThickness = new Thickness(.5), CornerRadius = new CornerRadius(10), Padding = new Thickness(19), Margin = new Thickness(0, 0, 0, 17), Child = body });
        return body;
    }
    private static TextBlock Caption(Panel parent, string text)
    {
        var label = new TextBlock { Text = text, FontSize = 12, Margin = new Thickness(0, 9, 0, 6), Foreground = WuxiaTheme.Brush(SkinCatalog.Current.Muted) }; parent.Children.Add(label); return label;
    }
    private static Button Action(string text) => new() { Content = text, Padding = new Thickness(12, 8, 12, 8), MinHeight = 34, Margin = new Thickness(0, 0, 8, 8) };
}
