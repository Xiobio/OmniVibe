using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace CodeManager;

public sealed class TaskEditorWindow : Window
{
    public string TaskName { get; private set; } = "";
    public string TagColor { get; private set; } = "";
    public string ProjectDirectory { get; private set; } = "";
    public LaunchMode LaunchMode { get; private set; }
    public string ResumeSessionId { get; private set; } = "";
    public bool ResumeConversation { get; private set; }
    public string Notes { get; private set; } = "";
    public TaskEditorWindow(Slot slot, Native.Rect area)
    {
        Title = L.T("任务与恢复配置 · ") + slot.Number; Width = 560; Height = 730; ResizeMode = ResizeMode.NoResize; Topmost = true; ShowInTaskbar = false;
        Background = WuxiaTheme.Ink;
        SourceInitialized += (_, _) => Native.Decorate(this, noActivate: false);
        double scale = Native.ScreenAtCursor().Scale;
        Height = Math.Min(730, (area.Bottom - area.Top) / scale - 40);
        Left = (area.Left + (area.Right - area.Left) / 2d) / scale - Width / 2; Top = (area.Top + (area.Bottom - area.Top) / 2d) / scale - Height / 2;
        var root = new DockPanel { Margin = new Thickness(22) };
        var panel = new StackPanel { Margin = new Thickness(0, 0, 12, 0) };
        panel.Children.Add(new TextBlock { Text = L.T("任务名称"), FontSize = 14, Margin = new Thickness(0, 0, 0, 8) });
        var name = new TextBox { Text = slot.DisplayName, MaxLength = 80 }; panel.Children.Add(name);
        panel.Children.Add(new TextBlock { Text = L.T("颜色标签"), Margin = new Thickness(0, 15, 0, 8) });
        var palette = new ComboBox();
        string[] colors = { slot.TagColor, "#82B89B", "#D8B56B", "#CB6555", "#CFC09D", "#9C879F", "#7C9BAA" };
        foreach (string color in colors)
        {
            var item = new ComboBoxItem { Tag = color, Content = new Border { Width = 330, Height = 17, Background = (Brush)new BrushConverter().ConvertFromString(color)!, CornerRadius = new CornerRadius(3), Margin = new Thickness(4) } };
            palette.Items.Add(item); if (color == slot.TagColor) palette.SelectedItem = item;
        }
        if (palette.SelectedIndex < 0) palette.SelectedIndex = 0; panel.Children.Add(palette);
        panel.Children.Add(new TextBlock { Text = L.T("项目目录（可选，用于任务辨认与重连）"), Margin = new Thickness(0, 15, 0, 8) });
        var project = new TextBox { Text = slot.ProjectDirectory }; panel.Children.Add(project);
        panel.Children.Add(new TextBlock { Text = L.T("恢复时如何启动"), Margin = new Thickness(0, 15, 0, 8) });
        var mode = new ComboBox(); foreach (string title in new[] { L.T("尚未配置"), L.T("只打开项目终端（PowerShell）"), L.T("Claude Code · 自动接入状态"), L.T("Codex · 自动接入状态") }) mode.Items.Add(new ComboBoxItem { Content = title }); mode.SelectedIndex = (int)slot.LaunchMode; panel.Children.Add(mode);
        var resume = new CheckBox { IsChecked = slot.ResumeConversation, Content = new TextBlock { Text = L.T("恢复原 AI 对话（取消勾选则新建会话）") }, Margin = new Thickness(0, 14, 0, 8) }; panel.Children.Add(resume);
        panel.Children.Add(new TextBlock { Text = L.T("原会话 ID（接入 hooks 后自动记录）"), Margin = new Thickness(0, 8, 0, 8) });
        var session = new TextBox { Text = slot.ResumeSessionId, MaxLength = 36 }; panel.Children.Add(session);
        panel.Children.Add(new TextBlock { Text = L.T("仅恢复指定会话，不自动提交提示词。终端恢复不包含内存、未保存内容或任意后台命令。"), FontSize = 12, TextWrapping = TextWrapping.Wrap, Foreground = WuxiaTheme.Gold, Margin = new Thickness(0, 10, 0, 0) });
        panel.Children.Add(new TextBlock { Text = L.T("任务备忘 / 下次接着做什么"), Margin = new Thickness(0, 15, 0, 8) });
        var notes = new TextBox { Text = slot.Notes, AcceptsReturn = true, Height = 78, MaxLength = 1500, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }; panel.Children.Add(notes);
        var error = new TextBlock { Foreground = WuxiaTheme.Cinnabar, Margin = new Thickness(0, 7, 0, 0) }; panel.Children.Add(error);
        var save = new Button { Content = L.T("保存任务"), IsDefault = true, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
        save.Click += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(name.Text)) { error.Text = L.T("请给任务起一个名称。"); return; }
            if (!string.IsNullOrWhiteSpace(project.Text) && !System.IO.Directory.Exists(project.Text.Trim())) { error.Text = L.T("项目目录不存在。"); return; }
            if (session.Text.Trim() != "" && !Guid.TryParse(session.Text.Trim(), out _)) { error.Text = L.T("会话 ID 应为完整 UUID。"); return; }
            TaskName = name.Text.Trim(); TagColor = (string)((ComboBoxItem)palette.SelectedItem).Tag; ProjectDirectory = project.Text.Trim();
            LaunchMode = (LaunchMode)mode.SelectedIndex; ResumeConversation = resume.IsChecked == true; ResumeSessionId = session.Text.Trim(); Notes = notes.Text.Trim(); DialogResult = true;
        };
        DockPanel.SetDock(save, Dock.Bottom); root.Children.Add(save); root.Children.Add(new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }); Content = root; Loaded += (_, _) => { name.Focus(); name.SelectAll(); };
        PreviewKeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Escape) DialogResult = false; };
    }
}
