using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace CodeManager;

/// <summary>A local draft: only an accepted dialog commits equipment, never task bindings.</summary>
public sealed class LoadoutWindow : Window
{
    private readonly List<Slot> _draft;
    private readonly StackPanel _slotList = new();
    private readonly UniformGrid _weapons = new() { Columns = 3 };
    private readonly List<Image> _choiceImages = new();
    private readonly Image _portrait = new() { Width = 125, Height = 154, Stretch = Stretch.Uniform };
    private readonly TextBlock _title = new() { FontSize = 24, FontWeight = FontWeights.SemiBold };
    private readonly TextBlock _subtitle = new() { FontSize = 12, TextWrapping = TextWrapping.Wrap };
    private readonly TextBlock _error = new() { TextWrapping = TextWrapping.Wrap, FontSize = 11 };
    private readonly TextBox _customName = new() { MinHeight = 34, MaxLength = 32 };
    private readonly SkinDefinition _skin;
    private int _index;
    private bool _refreshing;
    public IReadOnlyDictionary<string, EquipmentAssignment> Result => _draft.ToDictionary(x => x.Id, EquipmentAssignment.From);
    public static List<Slot> CreateDraft(IReadOnlyList<Slot> slots, IReadOnlyDictionary<string, EquipmentAssignment>? pending = null)
    {
        return slots.OrderBy(s => s.Number).Select(s => {
            var copy = new Slot { Number = s.Number, Id = s.Id, Name = s.Name, Window = s.Window, ProjectDirectory = s.ProjectDirectory, Connected = s.Connected };
            (pending != null && pending.TryGetValue(s.Id, out var assignment) ? assignment : EquipmentAssignment.From(s)).Apply(copy);
            return copy;
        }).ToList();
    }
    public LoadoutWindow(IReadOnlyList<Slot> slots, Native.Rect area, Slot? focus = null, Skin? previewSkin = null, bool settingsDraft = false)
    {
        _skin = SkinCatalog.Get(previewSkin ?? SkinCatalog.Current.Id);
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        _draft = CreateDraft(slots);
        EquipmentCatalog.EnsureDefaults(_draft);
        _index = Math.Max(0, _draft.FindIndex(x => x.Id == focus?.Id));
        var pack = EquipmentCatalog.Pack(_skin.Id);
        Title = "OmniVibe · " + pack.Title; Width = 1040; Height = 840; MinWidth = 690; MinHeight = 460;
        double scale = Native.ScreenAtCursor().Scale;
        double availableWidth = Math.Max(360, (area.Right - area.Left) / scale - 40), availableHeight = Math.Max(340, (area.Bottom - area.Top) / scale - 40);
        MinWidth = Math.Min(690, availableWidth); MinHeight = Math.Min(460, availableHeight);
        Width = Math.Min(Width, availableWidth); Height = Math.Min(Height, availableHeight);
        Left = (area.Left + area.Right) / (2 * scale) - Width / 2; Top = (area.Top + area.Bottom) / (2 * scale) - Height / 2;
        Background = WuxiaTheme.Brush(_skin.Background); Foreground = WuxiaTheme.Brush(_skin.Text);
        Topmost = true; ShowInTaskbar = false;
        Resources[typeof(Button)] = SettingsWindow.SettingsButtonStyle(_skin);
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: false);
        var root = new DockPanel(); Content = root;
        var heading = new StackPanel { Margin = new Thickness(24, 14, 24, 12) };
        heading.Children.Add(Label(_skin.Name + " / LOADOUT", 10, _skin.Accent));
        heading.Children.Add(Label(pack.Title, 22, _skin.Text));
        heading.Children.Add(Label(pack.Subtitle + " · 为当前主题独立保存选择，任务与窗口绑定保持不变。", 12, _skin.Muted));
        DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);
        var footer = new DockPanel { Margin = new Thickness(24, 12, 24, 18), LastChildFill = true };
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var cancel = Button("取消"); cancel.IsCancel = true;
        var save = Button(settingsDraft ? "使用这些形象" : "保存配装"); save.IsDefault = true; save.FontWeight = FontWeights.SemiBold;
        save.Click += (_, _) => { DialogResult = true; };
        actions.Children.Add(cancel); actions.Children.Add(save); DockPanel.SetDock(actions, Dock.Right); footer.Children.Add(actions);
        footer.Children.Add(Label(settingsDraft ? "返回设置后，点「保存并应用」才会生效" : "配装跟随任务移动 · 取消不改变当前配置", 11, _skin.Muted));
        DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        var left = new ScrollViewer { Width = 236, Margin = new Thickness(16, 0, 0, 8), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _slotList };
        DockPanel.SetDock(left, Dock.Left); root.Children.Add(left);
        var body = new StackPanel { Margin = new Thickness(24, 0, 24, 18) };
        root.Children.Add(new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        var hero = new Grid { Height = 48, Margin = new Thickness(0, 0, 0, 8), Background = new LinearGradientBrush((Color)ColorConverter.ConvertFromString(_skin.Elevated), (Color)ColorConverter.ConvertFromString(_skin.Background), 0) };
        _portrait.Visibility = Visibility.Collapsed; _title.FontSize = 17; _title.TextTrimming = TextTrimming.CharacterEllipsis;
        _subtitle.TextWrapping = TextWrapping.NoWrap; _subtitle.TextTrimming = TextTrimming.CharacterEllipsis; _subtitle.FontSize = 11;
        hero.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(0) }); hero.ColumnDefinitions.Add(new ColumnDefinition());
        hero.Children.Add(_portrait);
        var info = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 18, 0) };
        info.Children.Add(_title); info.Children.Add(_subtitle);
        Grid.SetColumn(info, 1); hero.Children.Add(info); body.Children.Add(hero);
        _weapons.SizeChanged += (_, _) => _weapons.Columns = _weapons.ActualWidth < 480 ? 2 : 3;
        SizeChanged += (_, _) => {
            left.Width = Math.Clamp(ActualWidth * .23, 150, 236);
            foreach (var image in _choiceImages) image.Height = ChoiceHeight;
        };
        body.Children.Add(Label("点击图片选择形象 · 选中项高亮 · 悬停查看名称与来源", 11, _skin.Muted));
        body.Children.Add(_weapons);
        var customization = new StackPanel();
        body.Children.Add(new Expander { Header = "使用自己的图片", Content = customization, Margin = new Thickness(0, 16, 0, 0) });
        customization.Children.Add(Label("导入透明 PNG，可替换当前槽位的角色或武器。", 11, _skin.Muted));
        var custom = new WrapPanel(); var import = Button("导入图片…"); var reset = Button("恢复主题藏品"); custom.Children.Add(import); custom.Children.Add(reset); customization.Children.Add(custom);
        customization.Children.Add(Label("藏品名称", 11, _skin.Muted)); customization.Children.Add(_customName);
        _customName.TextChanged += (_, _) => { if (!_refreshing && _draft[_index].EquipmentImage != "") { _draft[_index].EquipmentName = _customName.Text.Trim(); UpdateHero(); } };
        _error.Foreground = WuxiaTheme.Brush(_skin.Waiting); _error.Margin = new Thickness(0, 8, 0, 0); body.Children.Add(_error);
        import.Click += (_, _) => {
            var dialog = new Microsoft.Win32.OpenFileDialog { Title = "导入配装图片", Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp", CheckFileExists = true };
            if (dialog.ShowDialog(this) != true) return;
            try { SetCustomImage(EquipmentCatalog.Import(dialog.FileName), System.IO.Path.GetFileNameWithoutExtension(dialog.FileName)); }
            catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException or ArgumentException) { _error.Text = ex.Message; }
        };
        reset.Click += (_, _) => SelectWeapon(EquipmentCatalog.Item(_draft[_index], _skin.Id).Id);
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { DialogResult = false; e.Handled = true; } };
        Refresh();
    }
    private TextBlock Label(string text, double size, string color) => new() { Text = text, FontSize = size, Foreground = WuxiaTheme.Brush(color), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 6), VerticalAlignment = VerticalAlignment.Center };
    private Button Button(string text) => new() { Content = text, Padding = new Thickness(14, 8, 14, 8), MinHeight = 36, Margin = new Thickness(0, 4, 8, 4) };
    private double ChoiceHeight => Math.Clamp(((ActualHeight > 0 ? ActualHeight : Height) - 330) / 3 - 47, 52, 112);
    public void SelectSlot(int number) { _index = _draft.FindIndex(x => x.Number == number); if (_index < 0) _index = 0; Refresh(); }
    public void SelectWeapon(string id)
    {
        var pack = EquipmentCatalog.Pack(_skin.Id);
        var item = pack.Items.FirstOrDefault(x => x.Id == id);
        if (item == null && Enumerable.Range(1, 9).FirstOrDefault(n => EquipmentCatalog.Default(n).Id == id) is int legacy && legacy > 0) item = pack.Items[legacy - 1];
        if (item == null) return;
        // EquipmentId remains the legacy cross-theme baseline. Only this theme's explicit choice changes.
        var selected = _draft[_index];
        selected.EquipmentSelections[_skin.Id.ToString()] = item.Id;
        selected.EquipmentImage = ""; selected.EquipmentName = ""; selected.Refresh(); Refresh();
    }
    public void SetCustomImage(string managedFile, string name)
    {
        new EquipmentAssignment(_draft[_index].EquipmentId, managedFile, name.Length > 32 ? name[..32] : name).Apply(_draft[_index]); Refresh();
    }
    private void UpdateHero()
    {
        var slot = _draft[_index]; _portrait.Source = EquipmentCatalog.Image(slot, _skin.Id); _title.Text = EquipmentCatalog.Name(slot, _skin.Id);
        var item = EquipmentCatalog.Item(slot, _skin.Id);
        _subtitle.Text = "槽位 " + slot.Number + "  /  " + (slot.Occupied ? slot.DisplayName : "等待收纳窗口");
    }
    private void Refresh()
    {
        _refreshing = true; var selected = _draft[_index]; _slotList.Children.Clear(); _weapons.Children.Clear(); _choiceImages.Clear(); UpdateHero();
        foreach (var slot in _draft) {
            var row = new Grid { Height = 36 }; row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(25) }); row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) }); row.ColumnDefinitions.Add(new ColumnDefinition());
            row.Children.Add(Label(slot.Number.ToString("D2"), 11, _skin.Accent));
            var image = new Image { Source = EquipmentCatalog.Image(slot, _skin.Id), Height = 34, Width = 30, Stretch = Stretch.Uniform }; Grid.SetColumn(image, 1); row.Children.Add(image);
            var name = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) };
            name.Children.Add(new TextBlock { Text = EquipmentCatalog.Name(slot, _skin.Id), FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, Foreground = WuxiaTheme.Brush(_skin.Text) });
            name.Children.Add(new TextBlock { Text = slot.Occupied ? slot.DisplayName : "空槽位", FontSize = 9, Foreground = WuxiaTheme.Brush(_skin.Muted), TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 2, 0, 0) });
            Grid.SetColumn(name, 2); row.Children.Add(name);
            var b = new Button { Content = row, Padding = new Thickness(8, 2, 8, 2), Margin = new Thickness(0, 0, 0, 4), HorizontalContentAlignment = HorizontalAlignment.Stretch, Background = WuxiaTheme.Brush(slot == selected ? _skin.Elevated : _skin.Surface), BorderBrush = WuxiaTheme.Brush(slot == selected ? _skin.Accent : _skin.Border), ToolTip = slot.DisplayName };
            b.Click += (_, _) => SelectSlot(slot.Number); _slotList.Children.Add(b);
        }
        foreach (var item in EquipmentCatalog.Pack(_skin.Id).Items) {
            var sample = new Slot { Number = 1, EquipmentId = item.Id };
            var stack = new StackPanel { Margin = new Thickness(0, 5, 0, 4) };
            var portrait = new Image { Source = EquipmentCatalog.Image(sample, _skin.Id), Height = ChoiceHeight, Stretch = Stretch.Uniform }; _choiceImages.Add(portrait); stack.Children.Add(portrait);
            stack.Children.Add(new TextBlock { Text = item.Name, FontSize = 12, Foreground = WuxiaTheme.Brush(_skin.Text), TextAlignment = TextAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 6, 0, 0) });
            bool active = selected.EquipmentImage == "" && EquipmentCatalog.Item(selected, _skin.Id).Id == item.Id;
            var b = new Button { Content = stack, Padding = new Thickness(6), Margin = new Thickness(3), Background = WuxiaTheme.Brush(active ? _skin.Elevated : _skin.Surface), BorderBrush = WuxiaTheme.Brush(active ? _skin.Accent : _skin.Border), ToolTip = item.Name + " · " + item.Kind + "\n" + item.Provenance + (item.Source == "" ? "" : "\n" + item.Source) };
            b.Click += (_, _) => SelectWeapon(item.Id); _weapons.Children.Add(b);
        }
        _customName.Text = selected.EquipmentName; _customName.IsEnabled = selected.EquipmentImage != "";
        _error.Text = EquipmentCatalog.CustomMissing(selected) ? "自定义图片不可用，暂时显示主题藏品。可重新导入或恢复主题藏品。" : EquipmentCatalog.BuiltInMissing(selected, _skin.Id) ? "主题素材缺失或损坏，暂时显示兼容角色。请恢复该主题素材包，或导入自己的图片。" : "";
        _refreshing = false;
    }
}
