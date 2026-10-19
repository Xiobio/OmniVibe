using System.Drawing;
using System.Windows.Forms;

namespace CodeManager;

internal static class ProductIcon
{
    // Return an owned native icon; callers dispose it after their NotifyIcon.
    internal static Icon CreateTrayIcon()
    {
        using var stream = typeof(ProductIcon).Assembly.GetManifestResourceStream("OmniVibe.Brand.Icon");
        return stream == null
            ? (Icon)SystemIcons.Application.Clone()
            : new Icon(stream, SystemInformation.SmallIconSize);
    }
}
