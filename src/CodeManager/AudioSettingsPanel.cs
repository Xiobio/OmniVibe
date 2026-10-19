using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace CodeManager;

/// <summary>Audio audition and overrides stay in a local draft until settings are saved.</summary>
public sealed class AudioSettingsPanel : StackPanel
{
    private sealed record OverrideDraft(Skin Skin, AudioCue Cue, string? Identity, string? Source);
    private readonly List<OverrideDraft> _overrides = new();
    private readonly CheckBox _enabled, _notifications;
    private readonly Slider _volume;
    private readonly ComboBox _mode, _theme = new(), _cue = new(), _identity = new();
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 9, 0, 0) };
    private readonly TextBlock _auditionStatus = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0), FontSize = 11 };
    private static readonly IReadOnlyDictionary<AudioCue, string> Labels = new Dictionary<AudioCue, string>
    {
        [AudioCue.Switch] = "切换窗口", [AudioCue.Capture] = "收容窗口", [AudioCue.Remove] = "移出槽位",
        [AudioCue.Expand] = "展开装备", [AudioCue.Collapse] = "收起装备", [AudioCue.InventoryOpen] = "打开背包",
        [AudioCue.InventoryClose] = "关闭背包", [AudioCue.Arrange] = "全部排列", [AudioCue.Restore] = "恢复布局",
        [AudioCue.Reorder] = "调整顺序", [AudioCue.Waiting] = "等待处理", [AudioCue.Ready] = "本轮回复",
        [AudioCue.Error] = "发生错误", [AudioCue.Detent] = "划过槽位"
    };
    public AudioSettingsPanel(Preferences source, Func<Skin> previewSkin)
    {
        var controls = Section("声音偏好", "声音跟随正在使用的主题；窗口操作立即执行，声音不会阻塞切换。");
        _enabled = Check("启用皮肤交互音效", source.SoundEffects); controls.Children.Add(_enabled);
        _notifications = Check("任务等待、回复与错误时提示", source.SoundNotifications); controls.Children.Add(_notifications);
        Caption(controls, "交互强度");
        _mode = new ComboBox { MinHeight = 34, Margin = new Thickness(0, 0, 0, 8) };
        _mode.Items.Add("轻声工作 · 保留关键操作与状态提醒");
        _mode.Items.Add("游戏沉浸 · 完整操作声与细节层次");
        _mode.SelectedIndex = source.ImmersiveAudio ? 1 : 0; controls.Children.Add(_mode);
        var volumeLabel = Caption(controls, "音量");
        _volume = new Slider { Minimum = 0, Maximum = 100, Value = Math.Clamp(source.SoundVolume * 100, 0, 100), TickFrequency = 5, IsSnapToTickEnabled = true, Margin = new Thickness(0, 7, 0, 12) };
        void UpdateVolume() => volumeLabel.Text = "音量  " + Math.Round(_volume.Value) + "%";
        _volume.ValueChanged += (_, _) => UpdateVolume(); UpdateVolume(); controls.Children.Add(_volume);
        _enabled.Click += (_, _) => { if (_enabled.IsChecked != true) GameAudio.Stop(); };

        var audition = Section("套装试听", "选择主题和操作试听，不会切换主题或操作终端。轻声模式的实际操作会省略槽位划过、背包开合等细节声；点试听仍可了解完整声音。");
        foreach (var skin in SkinCatalog.All) _theme.Items.Add(new ComboBoxItem { Content = skin.Name, Tag = skin.Id });
        _theme.MinHeight = 34; audition.Children.Add(_theme); SelectTheme(previewSkin());
        _theme.SelectionChanged += (_, _) => RefreshIdentities();
        var buttons = new WrapPanel { Margin = new Thickness(0, 12, 0, 0) }; audition.Children.Add(buttons);
        foreach (var pair in Labels)
        {
            var cue = pair.Key; var button = Action(pair.Value);
            button.Click += (_, _) => Audition(cue);
            buttons.Children.Add(button);
        }
        var stop = Action("停止试听"); stop.Click += (_, _) => GameAudio.Stop(); buttons.Children.Add(stop);
        _auditionStatus.Foreground = WuxiaTheme.Brush(SkinCatalog.Current.Muted); audition.Children.Add(_auditionStatus);

        var custom = Section("自定义角色语音与操作声", "可为整套主题，或某一位角色／装备导入 WAV。文件会复制到本机素材库；选择后按「保存并应用」才写入。恢复默认会移除所选层的覆盖。");
        Caption(custom, "应用范围"); _identity.MinHeight = 34; custom.Children.Add(_identity);
        Caption(custom, "对应操作");
        foreach (var pair in Labels) _cue.Items.Add(new ComboBoxItem { Content = pair.Value, Tag = pair.Key });
        _cue.SelectedIndex = 0; _cue.MinHeight = 34; custom.Children.Add(_cue);
        var actions = new WrapPanel { Margin = new Thickness(0, 8, 0, 0) };
        var import = Action("导入 WAV…"); var reset = Action("恢复默认声音"); var selectedPreview = Action("试听所选声音"); actions.Children.Add(import); actions.Children.Add(reset); actions.Children.Add(selectedPreview); custom.Children.Add(actions);
        selectedPreview.Click += (_, _) => { Audition(SelectedCue); _status.Text = _auditionStatus.Text; };
        _status.Foreground = WuxiaTheme.Brush(SkinCatalog.Current.Muted); custom.Children.Add(_status);
        import.Click += (_, _) =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog { Title = "选择角色语音或操作声", Filter = "WAV 音频|*.wav", CheckFileExists = true };
            if (dialog.ShowDialog(Window.GetWindow(this)) != true) return;
            if (!GameAudio.ValidateWave(dialog.FileName, out string error)) { _status.Text = "请选择不超过 3 秒的 PCM16 WAV（单声道或立体声，16–96 kHz）。\n" + error; return; }
            QueueOverride(dialog.FileName); _status.Text = "待保存：" + Path.GetFileName(dialog.FileName) + " · " + Labels[SelectedCue];
        };
        reset.Click += (_, _) => { QueueOverride(null); _status.Text = "待保存：恢复「" + Labels[SelectedCue] + "」的默认声音"; };
        IsVisibleChanged += (_, _) => { if (IsVisible) { SelectTheme(previewSkin()); RefreshIdentities(); } else GameAudio.Stop(); };
        Unloaded += (_, _) => GameAudio.Stop();
        RefreshIdentities();
    }
    private Skin SelectedSkin => _theme.SelectedItem is ComboBoxItem { Tag: Skin skin } ? skin : SkinCatalog.Current.Id;
    private AudioCue SelectedCue => _cue.SelectedItem is ComboBoxItem { Tag: AudioCue cue } ? cue : AudioCue.Switch;
    private string? SelectedIdentity => (_identity.SelectedItem as ComboBoxItem)?.Tag as string;
    private void SelectTheme(Skin skin) => _theme.SelectedItem = _theme.Items.OfType<ComboBoxItem>().First(x => x.Tag is Skin id && id == skin);
    private void RefreshIdentities()
    {
        string? previous = SelectedIdentity; _identity.Items.Clear();
        _identity.Items.Add(new ComboBoxItem { Content = "整套主题 · 默认操作声" });
        foreach (var item in EquipmentCatalog.ForSkin(SelectedSkin)) _identity.Items.Add(new ComboBoxItem { Content = item.Name + " · " + item.Kind, Tag = item.Id });
        _identity.SelectedItem = _identity.Items.OfType<ComboBoxItem>().FirstOrDefault(x => previous != null && x.Tag as string == previous) ?? _identity.Items[0];
    }
    private void QueueOverride(string? source)
    {
        _overrides.RemoveAll(x => x.Skin == SelectedSkin && x.Cue == SelectedCue && x.Identity == SelectedIdentity);
        _overrides.Add(new(SelectedSkin, SelectedCue, SelectedIdentity, source));
    }
    private void Audition(AudioCue cue)
    {
        Skin skin = SelectedSkin; string? identity = SelectedIdentity;
        OverrideDraft? Draft(string? scope) => _overrides.LastOrDefault(x => x.Skin == skin && x.Cue == cue && x.Identity == scope);
        var itemDraft = identity == null ? null : Draft(identity);
        bool existingItem = identity != null && File.Exists(Path.Combine(GameAudio.OverrideDirectory(skin, identity), cue.ToString().ToLowerInvariant() + ".wav"));
        var themeDraft = Draft(null);
        string mode;
        if (itemDraft?.Source is string itemFile)
        { GameAudio.PreviewFile(skin, cue, itemFile, _volume.Value / 100, _mode.SelectedIndex == 1); mode = "待保存的角色声音"; }
        else if (itemDraft == null && existingItem)
        { GameAudio.Preview(skin, cue, _volume.Value / 100, _mode.SelectedIndex == 1, identity); mode = "已保存的角色声音"; }
        else if (themeDraft?.Source is string themeFile)
        { GameAudio.PreviewFile(skin, cue, themeFile, _volume.Value / 100, _mode.SelectedIndex == 1); mode = "待保存的主题声音"; }
        else if (themeDraft != null)
        { GameAudio.PreviewBuiltIn(skin, cue, _volume.Value / 100, _mode.SelectedIndex == 1); mode = "内置主题声音"; }
        else
        { GameAudio.Preview(skin, cue, _volume.Value / 100, _mode.SelectedIndex == 1); mode = "主题声音"; }
        _auditionStatus.Text = SkinCatalog.Get(skin).Name + " · " + Labels[cue] + " · " + mode + " · " + Math.Round(_volume.Value) + "%";
    }
    public bool TryCommit(Preferences result, out string error)
    {
        error = "";
        if (!AudioOverrideTransaction.TryApply(_overrides.Select(x => new AudioOverrideChange(x.Skin, x.Cue, x.Identity, x.Source)).ToArray(), out error)) return false;
        result.SoundEffects = _enabled.IsChecked == true; result.SoundVolume = _volume.Value / 100;
        result.ImmersiveAudio = _mode.SelectedIndex == 1; result.SoundNotifications = _notifications.IsChecked == true;
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
    private static CheckBox Check(string text, bool value) => new() { Content = text, IsChecked = value, Margin = new Thickness(0, 5, 0, 9) };
    private static TextBlock Caption(Panel parent, string text)
    {
        var label = new TextBlock { Text = text, FontSize = 12, Margin = new Thickness(0, 9, 0, 6), Foreground = WuxiaTheme.Brush(SkinCatalog.Current.Muted) }; parent.Children.Add(label); return label;
    }
    private static Button Action(string text) => new() { Content = text, Padding = new Thickness(12, 8, 12, 8), MinHeight = 34, Margin = new Thickness(0, 0, 8, 8) };
}
