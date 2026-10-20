using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;

namespace CodeManager;

public sealed class SessionLinkWindow : Window
{
    public AgentSession? SelectedSession { get; private set; }
    public SessionLinkWindow(IReadOnlyList<AgentSession> sessions, Slot slot, Native.Rect area)
    {
        Title="连接任务状态"; Width=720; Height=560; Background=WuxiaTheme.Ink;
        ShowInTaskbar=false; WindowStartupLocation=WindowStartupLocation.CenterScreen;
        SourceInitialized += (_,_) => Native.Decorate(this,noActivate:false);
        var root=new DockPanel { Margin=new Thickness(24) }; Content=root;
        var head=new StackPanel(); DockPanel.SetDock(head,Dock.Top);root.Children.Add(head);
        head.Children.Add(new TextBlock { Text="连接正在使用的 CLI 会话",FontSize=23,FontWeight=FontWeights.SemiBold });
        head.Children.Add(new TextBlock { Text=slot.Number+" · "+slot.DisplayName,FontSize=14,Margin=new Thickness(0,8,0,8) });
        head.Children.Add(new TextBlock { Text="选择这个窗口里正在运行的会话。无需退出 CLI；连接后自动跟踪执行与回复。权限确认的精确事件可再接入 hooks。",TextWrapping=TextWrapping.Wrap,Foreground=WuxiaTheme.Brush(SkinCatalog.Current.Muted),Margin=new Thickness(0,0,0,16) });
        var list=new ListBox { BorderThickness=new Thickness(0),Background=WuxiaTheme.Ink };
        foreach(var session in sessions) {
            var panel=new StackPanel { Margin=new Thickness(10,8,10,8) };
            panel.Children.Add(new TextBlock { Text=session.Label,FontSize=15,TextTrimming=TextTrimming.CharacterEllipsis });
            panel.Children.Add(new TextBlock { Text=session.Detail,FontSize=11,TextTrimming=TextTrimming.CharacterEllipsis,Foreground=WuxiaTheme.Brush(SkinCatalog.Current.Muted),Margin=new Thickness(0,5,0,0) });
            list.Items.Add(new ListBoxItem { Content=panel,Tag=session,HorizontalContentAlignment=HorizontalAlignment.Stretch });
        }
        var footer=new StackPanel { Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right,Margin=new Thickness(0,16,0,0) }; DockPanel.SetDock(footer,Dock.Bottom);root.Children.Add(footer);
        var cancel=new Button { Content="取消",Margin=new Thickness(0,0,12,0) };cancel.Click+=(_,_)=>Close();footer.Children.Add(cancel);
        var connect=new Button { Content="连接所选会话",IsEnabled=false }; footer.Children.Add(connect);
        void Commit() { if (list.SelectedItem is ListBoxItem { Tag: AgentSession session }) { SelectedSession=session; DialogResult=true; } }
        connect.Click+=(_,_)=>Commit();list.SelectionChanged+=(_,_)=>connect.IsEnabled=list.SelectedItem!=null;list.MouseDoubleClick+=(_,_)=>Commit();
        if(sessions.Count==0) root.Children.Add(new TextBlock { Text="尚未发现本地 Codex / Claude Code 会话。请先在终端启动 CLI，或使用菜单中的 hooks 接入方式。",TextWrapping=TextWrapping.Wrap,Margin=new Thickness(10) });
        else { root.Children.Add(list); var selected=list.Items.OfType<ListBoxItem>().FirstOrDefault(i=>i.Tag is AgentSession s && s.Id==slot.SessionId);if(selected!=null)list.SelectedItem=selected; }
    }
}
