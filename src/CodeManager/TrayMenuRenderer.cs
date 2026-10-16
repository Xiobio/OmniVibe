using System.Drawing;
using System.Windows.Forms;

namespace CodeManager;

internal sealed class TrayMenuRenderer : ToolStripProfessionalRenderer
{
    public TrayMenuRenderer() : base(new Colors()) { RoundedEdges = false; }
    private static Color ColorOf(string value) => ColorTranslator.FromHtml(value);
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = ColorOf(e.Item.Enabled ? SkinCatalog.Current.Text : SkinCatalog.Current.Muted);
        base.OnRenderItemText(e);
    }
    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
    {
        e.ArrowColor = ColorOf(e.Item?.Enabled == false ? SkinCatalog.Current.Muted : SkinCatalog.Current.Text);
        base.OnRenderArrow(e);
    }
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
    {
        using var pen = new Pen(ColorOf(SkinCatalog.Current.Border));
        int middle = e.Item.Height / 2; e.Graphics.DrawLine(pen, 10, middle, e.Item.Width - 10, middle);
    }
    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
    {
        var skin = SkinCatalog.Current;
        var box = e.ImageRectangle;
        using var fill = new SolidBrush(ColorOf(skin.Elevated));
        using var outline = new Pen(ColorOf(skin.Border));
        using var mark = new Pen(ColorOf(e.Item.Enabled ? skin.Text : skin.Muted), 1.7f);
        var saved = e.Graphics.Save();
        try
        {
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            e.Graphics.FillRectangle(fill, box); e.Graphics.DrawRectangle(outline, box);
            e.Graphics.DrawLines(mark, new[] {
                new PointF(box.Left + box.Width * .20f, box.Top + box.Height * .52f),
                new PointF(box.Left + box.Width * .43f, box.Top + box.Height * .74f),
                new PointF(box.Left + box.Width * .82f, box.Top + box.Height * .25f) });
        }
        finally { e.Graphics.Restore(saved); }
    }
    private sealed class Colors : ProfessionalColorTable
    {
        public override Color MenuItemSelected => ColorOf(SkinCatalog.Current.Elevated);
        public override Color MenuItemSelectedGradientBegin => MenuItemSelected;
        public override Color MenuItemSelectedGradientEnd => MenuItemSelected;
        public override Color MenuItemPressedGradientBegin => MenuItemSelected;
        public override Color MenuItemPressedGradientMiddle => MenuItemSelected;
        public override Color MenuItemPressedGradientEnd => MenuItemSelected;
        public override Color MenuItemBorder => ColorOf(SkinCatalog.Current.Accent);
        public override Color ToolStripDropDownBackground => ColorOf(SkinCatalog.Current.Background);
        public override Color ImageMarginGradientBegin => ToolStripDropDownBackground;
        public override Color ImageMarginGradientMiddle => ToolStripDropDownBackground;
        public override Color ImageMarginGradientEnd => ToolStripDropDownBackground;
        public override Color MenuBorder => ColorOf(SkinCatalog.Current.Border);
        public override Color CheckBackground => ColorOf(SkinCatalog.Current.Elevated);
        public override Color CheckSelectedBackground => MenuItemSelected;
        public override Color CheckPressedBackground => MenuItemSelected;
        public override Color SeparatorDark => ColorOf(SkinCatalog.Current.Border);
        public override Color SeparatorLight => ToolStripDropDownBackground;
    }
}
