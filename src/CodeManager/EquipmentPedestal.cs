using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Media;

namespace CodeManager;

/// <summary>A small, theme-specific mounting accent; the entity silhouette stays unobstructed.</summary>
internal static class EquipmentPedestal
{
    private static readonly Dictionary<(Skin, double, double), DrawingGroup> Cache = new();
    internal static void Draw(DrawingContext dc, SkinDefinition skin, Rect bounds)
    {
        if (bounds.Width < 1 || bounds.Height < 1) return;
        var key = (skin.Id, bounds.Width, bounds.Height);
        if (!Cache.TryGetValue(key, out var drawing)) {
            drawing = new DrawingGroup();
            using (var context = drawing.Open()) {
                var edge = new Pen(WuxiaTheme.Brush(skin.Accent), .8) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                var secondary = new Pen(WuxiaTheme.Brush(skin.Secondary), .65);
                double w = bounds.Width, y = bounds.Height * .55, end = Math.Min(6, w * .1);
                context.DrawLine(secondary, new Point(end * 2, y), new Point(w - end * 2, y));
                void Line(double x1, double y1, double x2, double y2) => context.DrawLine(edge, new Point(x1, y1), new Point(x2, y2));
                switch (skin.Family) {
                    case "mechanical":
                    case "formation":
                        foreach (double x in new[] { end, w - end }) {
                            var gem = new StreamGeometry(); using (var p = gem.Open()) { p.BeginFigure(new Point(x, y-2), false, true); p.LineTo(new Point(x+2,y), true,false); p.LineTo(new Point(x,y+2),true,false); p.LineTo(new Point(x-2,y),true,false); } gem.Freeze(); context.DrawGeometry(null,edge,gem);
                        }
                        break;
                    case "tactical":
                        Line(0,y-3,0,y+1); Line(0,y+1,end,y+1); Line(w,y-3,w,y+1); Line(w,y+1,w-end,y+1);
                        Line(w*.48,y+2,w*.52,y+2); break;
                    case "protocol":
                        Line(0,y-3,end,y+2); Line(end,y+2,end*2,y+2); Line(w,y-3,w-end,y+2); Line(w-end,y+2,w-end*2,y+2); break;
                    case "fantasy":
                    case "astral":
                        foreach (double x in new[] { end, w-end }) { Line(x-3,y,x+3,y); Line(x,y-3,x,y+3); }
                        Line(w*.47,y+2,w*.5,y+4); Line(w*.5,y+4,w*.53,y+2); break;
                    case "wonderland":
                    case "ink":
                    case "relic":
                        Line(0,y-1,end,y+1); Line(end,y+1,end*2,y-1); Line(w,y-1,w-end,y+1); Line(w-end,y+1,w-end*2,y-1); break;
                    default:
                        Line(0,y-2,0,y+2); Line(0,y+2,end,y+2); Line(w,y-2,w,y+2); Line(w,y+2,w-end,y+2); break;
                }
            }
            drawing.Freeze(); if (Cache.Count >= 128) Cache.Clear(); Cache[key] = drawing;
        }
        dc.PushTransform(new TranslateTransform(bounds.X, bounds.Y)); dc.DrawDrawing(drawing); dc.Pop();
    }
}
