using System;

namespace CodeManager;

public enum OverviewSize { Compact, Standard, Spacious, Large, Panoramic }

internal static class OverviewSizing
{
    internal static readonly string[] Labels = {
        L.T("紧凑 · 少占桌面"), L.T("标准 · 中等卡片"), L.T("宽敞 · 放大预览"), L.T("超大 · 推荐"), L.T("近全屏 · 保留桌面边距")
    };
    internal static OverviewSize Normalize(OverviewSize size) => Enum.IsDefined(size) ? size : OverviewSize.Large;
    internal static (double Width, double Height) Measure(int columns, int rows, double availableWidth, double availableHeight, OverviewSize size)
    {
        int index = (int)Normalize(size);
        double factor = new[] { .85, 1, 1.25, 1.5, 2 }[index];
        double fraction = new[] { .70, .78, .84, .90, .95 }[index];
        double width = index == 4 ? availableWidth * fraction : (columns == 1 ? 520 : columns == 2 ? 900 : 1180) * factor;
        double height = index == 4 ? availableHeight * fraction : (146 + rows * 250) * factor;
        return (Math.Max(1, Math.Min(width, Math.Min(availableWidth - 48, availableWidth * fraction))),
            Math.Max(1, Math.Min(height, Math.Min(availableHeight - 48, availableHeight * fraction))));
    }
}
