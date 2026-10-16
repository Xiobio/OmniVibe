using System.Drawing;
using System.Windows.Forms;
namespace CodeManager;
internal sealed class TrayMenuRenderer : ToolStripProfessionalRenderer
{
    public TrayMenuRenderer() : base(new Colors()) { RoundedEdges = false; }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    { e.TextColor = e.Item.Enabled ? Color.FromArgb(250, 234, 203) : Color.FromArgb(165, 170, 157); base.OnRenderItemText(e); }
    private sealed class Colors : ProfessionalColorTable
    {
        public override Color MenuItemSelected => Color.FromArgb(52, 74, 62);
        public override Color MenuItemBorder => Color.FromArgb(155, 197, 168);
        public override Color ToolStripDropDownBackground => Color.FromArgb(22, 30, 27);
        public override Color ImageMarginGradientBegin => ToolStripDropDownBackground;
        public override Color ImageMarginGradientMiddle => ToolStripDropDownBackground;
        public override Color ImageMarginGradientEnd => ToolStripDropDownBackground;
        public override Color MenuBorder => Color.FromArgb(173, 145, 94);
    }
}
