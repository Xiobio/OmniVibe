using System;
using System.Collections.Generic;
using System.Linq;

namespace CodeManager;

public sealed record ShortcutBinding(int Id, string Name, string Gesture, string Purpose);

public static class ShortcutBindings
{
    public static IReadOnlyList<ShortcutBinding> All(Preferences p) => Enumerable.Range(1, 9)
        .Select(n => new ShortcutBinding(n, L.T("窗口 ") + n, p.TaskGesture(n), L.T("唤出对应窗口，再按一次恢复原样")))
        .Concat(new[] {
            new ShortcutBinding(11, L.T("任务总览"), p.TabTogglesInventory ? p.InventoryGesture : "", L.T("查看全部任务；滚轮选中，Enter / 点击进入，再按关闭")),
            new ShortcutBinding(13, L.T("快速轮盘"), p.RadialGesture, L.T("按住组合键 → 指向任务形象 → 松键进入")),
            new ShortcutBinding(12, L.T("排列 / 恢复"), p.ArrangeGesture, L.T("同时查看多个窗口，再按恢复原来的布局")),
            new ShortcutBinding(10, L.T("显示 / 隐藏入口"), p.ToggleGesture, L.T("临时隐藏或找回桌面上的悬浮入口"))
        }).ToArray();
    public static string Display(string? gesture) => string.IsNullOrWhiteSpace(gesture) ? L.T("未设置") : string.Join("+", gesture.Split('+').Select(token => token.ToUpperInvariant() switch { "OEM3" => L.T("反引号 (`)"), "SPACE" => L.T("空格"), "WHEEL" => L.T("滚轮"), "BACK" or "BACKSPACE" => "Backspace", _ => token }));
    public static bool Validate(Preferences p, out string error)
    {
        var used = new Dictionary<string, string>();
        foreach (var item in All(p)) {
            if (string.IsNullOrWhiteSpace(item.Gesture)) continue;
            if (!InputService.TryParseGesture(item.Gesture, out uint mods, out uint key)) { error = item.Name + L.T("：请录入有效按键。"); return false; }
            if (key == 0x7B || mods == 8 && key is 0x4C or 0x55 || mods == 3 && key == 0x2E || mods == 1 && key is 9 or 0x1B || mods == 2 && key == 0x1B) {
                error = item.Name + "：" + Display(item.Gesture) + L.T(" 由 Windows 保留，请换一个组合。"); return false;
            }
            string id = mods + ":" + key;
            if (used.TryGetValue(id, out string? other)) { error = item.Name + L.T(" 与「") + other + L.T("」使用了相同快捷键。"); return false; }
            used[id] = item.Name;
        }
        if (p.WheelSwitchEnabled && (int)p.MouseModifiers is < 1 or > 15) { error = L.T("滚轮切换需要至少一个修饰键。"); return false; }
        error = ""; return true;
    }
    public static bool IsTypingKey(string gesture) => InputService.TryParseGesture(gesture, out uint mods, out uint key) && mods == 0 && key is not (>= 0x70 and <= 0x87);
}
