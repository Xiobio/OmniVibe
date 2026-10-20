using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Media;

namespace CodeManager;

internal readonly record struct WheelStatusSummary(int Running, int Waiting, int Ready, int Errors, int Unlinked)
{
    internal int Attention => Waiting+Ready+Errors;
    internal string Label => Attention>0 ? Attention+" 项待处理" : Running>0 ? Running+" 个任务执行中" : Unlinked>0 ? "未接入自动状态" : "已查看 · 等待任务";
    internal string Color(SkinDefinition skin) => Errors>0 ? skin.Error : Waiting>0 ? skin.Waiting : Ready>0 ? skin.Ready : Running>0 ? skin.Running : skin.Muted;
    internal static WheelStatusSummary From(IEnumerable<Slot> slots)
    {
        int running=0,waiting=0,ready=0,errors=0,unlinked=0;
        foreach(var s in slots.Where(s=>s.Occupied && s.Connected)) {
            if (s.State==AgentState.Running && !WheelTaskStatus.Stale(s)) running++;
            else if(s.Unread && s.State==AgentState.Waiting)waiting++;
            else if(s.Unread && s.State==AgentState.Ready)ready++;
            else if(s.Unread && s.State==AgentState.Error)errors++;
            else if(!s.IntegrationConnected && s.State==AgentState.Unknown)unlinked++;
        }
        return new(running,waiting,ready,errors,unlinked);
    }
}

/// <summary>Quiet equipment HUD: one glyph per socket, one aggregate seal on the
/// core. State names belong in the immediate hover hint, never around the artwork.</summary>
internal static class WheelTaskStatus
{
    private static readonly Dictionary<string,Brush> Brushes=new();
    private static readonly Dictionary<(string,double),Pen> Pens=new();
    private static readonly Dictionary<(string,string,double,double),DrawingGroup> Labels=new();
    private static readonly Dictionary<(string,string),Brush> Glass=new();
    private static readonly Dictionary<string,Brush> Glows=new();
    private static readonly Dictionary<(double,Skin),Geometry> Seals=new();
    private static readonly Typeface Typeface=new(new FontFamily("Microsoft YaHei UI"),FontStyles.Normal,FontWeights.SemiBold,FontStretches.Normal);
    private static Brush B(string color) { if(Brushes.TryGetValue(color,out var b))return b;var brush=new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));brush.Freeze();Brushes[color]=brush;return brush; }
    private static Pen P(string color,double width) { if(Pens.TryGetValue((color,width),out var p))return p; p=new Pen(B(color),width){StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round};p.Freeze();Pens[(color,width)]=p;return p; }
    private static void Label(DrawingContext dc,string text,string color,double size,double width,double x,double y)
    {
        var key=(text,color,size,width);
        if(!Labels.TryGetValue(key,out var drawing)) {
            var formatted=new FormattedText(text,CultureInfo.GetCultureInfo("zh-CN"),FlowDirection.LeftToRight,Typeface,size,B(color),1) { MaxTextWidth=width,MaxLineCount=1,Trimming=TextTrimming.CharacterEllipsis,TextAlignment=TextAlignment.Center };
            drawing=new DrawingGroup();using(var c=drawing.Open())c.DrawText(formatted,new Point(-width/2,-formatted.Height/2));drawing.Freeze();if(Labels.Count>512)Labels.Clear();Labels[key]=drawing;
        }
        dc.PushTransform(new TranslateTransform(x,y));dc.DrawDrawing(drawing);dc.Pop();
    }
    internal static bool Stale(Slot slot) => slot.UpdatedAt.HasValue && slot.StateSource!="手动标记" && slot.IntegrationConnected && slot.State is AgentState.Running or AgentState.Waiting && DateTimeOffset.UtcNow-slot.UpdatedAt.Value>TimeSpan.FromMinutes(10);
    internal static bool NeedsMotion(IEnumerable<Slot> slots) => slots.Any(s=>s.Occupied && s.Connected && !Stale(s) && (s.State==AgentState.Running || s.Unread && s.State is AgentState.Waiting or AgentState.Ready or AgentState.Error));
    internal static string LabelFor(Slot slot) => !slot.Connected ? "已断开" : Stale(slot) ? "状态待确认" : slot.State switch {
        AgentState.Running=>"执行中",AgentState.Waiting=>slot.StateSource=="终端状态信号"?"通知待查看":"等待确认",AgentState.Ready=>slot.Unread?"回复待查看":"已查看回复",AgentState.Error=>"发生错误",_=>slot.IntegrationConnected?"等待任务":"未接入状态"
    };
    internal static bool CoreVisible(WheelStatusSummary summary) => summary.Attention>0 || summary.Running>0 || summary.Unlinked>0;
    internal static int CoreCount(WheelStatusSummary summary) => summary.Attention>0 ? summary.Attention : summary.Running;
    internal static AgentState CoreState(WheelStatusSummary summary) => summary.Errors>0 ? AgentState.Error : summary.Waiting>0 ? AgentState.Waiting : summary.Ready>0 ? AgentState.Ready : summary.Running>0 ? AgentState.Running : AgentState.Unknown;
    private static Brush Glow(string color)
    {
        if(Glows.TryGetValue(color,out var cached))return cached;
        var c=(Color)ColorConverter.ConvertFromString(color);c.A=65;
        var brush=new RadialGradientBrush(c,Colors.Transparent);brush.Freeze();Glows[color]=brush;return brush;
    }
    private static Brush SealGlass(SkinDefinition skin)
    {
        var key=(skin.Background,skin.Elevated);if(Glass.TryGetValue(key,out var cached))return cached;
        Color top=(Color)ColorConverter.ConvertFromString(skin.Elevated),bottom=(Color)ColorConverter.ConvertFromString(skin.Background);top.A=244;bottom.A=230;
        var brush=new LinearGradientBrush(top,bottom,90);brush.Freeze();Glass[key]=brush;return brush;
    }
    private static Geometry Seal(double width,SkinDefinition skin)
    {
        if(Seals.TryGetValue((width,skin.Id),out var cached))return cached;
        Geometry result;
        if(skin.Family is "mechanical" or "tactical" or "protocol" or "formation" or "arsenal") {
            double cut=skin.Id==Skin.Protocol?5:skin.Id==Skin.Tactical?2:4;
            var g=new StreamGeometry();using(var c=g.Open()) {
                c.BeginFigure(new Point(-width/2+cut,-9),true,true);
                c.PolyLineTo(new[]{new Point(width/2-cut,-9),new Point(width/2,-9+cut),new Point(width/2,9-cut),new Point(width/2-cut,9),new Point(-width/2+cut,9),new Point(-width/2,9-cut),new Point(-width/2,-9+cut)},true,false);
            }
            result=g;
        } else {
            double radius=skin.Id switch { Skin.Cinnabar=>2,Skin.InkJade=>4,Skin.Adventure=>3,Skin.Relic=>5,Skin.Starlight=>7,Skin.Wonderland=>8,_=>6 };
            result=new RectangleGeometry(new Rect(-width/2,-9,width,18),radius,radius);
        }
        result.Freeze();Seals[(width,skin.Id)]=result;return result;
    }
    // Theme workmanship stays in the existing 32 x 18 seal. All state glyphs
    // retain their common meaning, position and size; no extra labels or plates.
    private static void ThemeTrim(DrawingContext dc,SkinDefinition skin,double width,double flow,bool motion,bool attention)
    {
        double left=-width/2+2,right=width/2-2;
        var accent=P(skin.Accent,.65);var secondary=P(skin.Secondary,.6);
        dc.PushOpacity(attention && motion?.35+.25*Math.Pow(Math.Sin(flow*Math.PI*3),2):.44);
        switch(skin.Id) {
            case Skin.InkJade:
                dc.DrawLine(accent,new(left,-3),new(left,-6));dc.DrawLine(accent,new(left,-6),new(left+3,-6));
                dc.DrawLine(secondary,new(right,3),new(right,6));dc.DrawLine(secondary,new(right,6),new(right-3,6));break;
            case Skin.Midnight:
                dc.DrawEllipse(null,secondary,new(left+2,-4),1.5,2);dc.DrawEllipse(B(skin.Accent),null,new(right-2,5),.7,.7);break;
            case Skin.Cinnabar:
                dc.DrawLine(accent,new(left+2,-6),new(right-2,-6));dc.DrawLine(accent,new(left+2,6),new(right-2,6));break;
            case Skin.Hextech:
                dc.DrawLine(secondary,new(left,-3),new(left+2,-5));dc.DrawEllipse(B(skin.Secondary),null,new(right-2,5),1,1);break;
            case Skin.Tactical:
                for(int i=0;i<3;i++)dc.DrawLine(accent,new(left+i*2,5),new(left+i*2,7));break;
            case Skin.Protocol:
                dc.DrawLine(accent,new(right-5,-7),new(right,-2));dc.DrawLine(secondary,new(left,2),new(left+4,6));break;
            case Skin.Adventure:
                dc.DrawEllipse(B(skin.Accent),null,new(left+2,-5),.8,.8);dc.DrawEllipse(B(skin.Accent),null,new(right-2,5),.8,.8);break;
            case Skin.Arsenal:
                dc.DrawLine(accent,new(left,-4),new(left+4,-7));dc.DrawLine(accent,new(right-4,7),new(right,4));break;
            case Skin.Relic:
                dc.DrawLine(accent,new(left,-4),new(left,4));dc.DrawLine(secondary,new(right,-4),new(right,4));break;
            case Skin.Starlight:
                dc.DrawLine(accent,new(-3,-7),new(0,-5));dc.DrawLine(accent,new(0,-5),new(3,-7));break;
            case Skin.Formation:
                dc.DrawLine(secondary,new(left+1,-5),new(left+3,-7));dc.DrawLine(secondary,new(left+3,-7),new(left+5,-5));break;
            case Skin.Astral:
                dc.DrawEllipse(B(skin.Accent),null,new(left+2,-5),.8,.8);dc.DrawLine(secondary,new(right-4,6),new(right,6));break;
            case Skin.Wonderland:
                dc.DrawEllipse(null,secondary,new(left+2,-5),1.5,1);dc.DrawEllipse(null,accent,new(right-2,5),1.5,1);break;
        }
        dc.Pop();
    }
    private static void Glyph(DrawingContext dc,SkinDefinition skin,AgentState state,string color,double flow,bool motion,bool unread)
    {
        double breath=motion && unread ? .82+.16*Math.Pow(Math.Sin(flow*Math.PI*3),2) : 1;
        if(unread) {
            dc.PushOpacity(breath);dc.DrawEllipse(Glow(color),null,new Point(0,0),10,9);dc.Pop();
        }
        dc.PushOpacity(breath);
        switch(state) {
            case AgentState.Running:
                for(int i=0;i<3;i++) {
                    double opacity=motion ? .28+.70*Math.Pow(Math.Cos(flow*Math.PI*6-i*.75),2) : .5+i*.2;
                    dc.PushOpacity(opacity);double x=(i-1)*3.5;
                    if(skin.Family is "tactical" or "mechanical" or "protocol") dc.DrawRectangle(B(color),null,new Rect(x-.8,-2,1.6,4));
                    else dc.DrawEllipse(B(color),null,new Point(x,0),1.05,1.05);
                    dc.Pop();
                }
                break;
            case AgentState.Ready:
                dc.DrawLine(P(color,1.55),new Point(-3.6,0),new Point(-1.1,2.5));
                dc.DrawLine(P(color,1.55),new Point(-1.1,2.5),new Point(3.7,-3));break;
            case AgentState.Waiting:
                dc.DrawLine(P(color,1.55),new Point(-2,-3.3),new Point(-2,3.3));
                dc.DrawLine(P(color,1.55),new Point(2,-3.3),new Point(2,3.3));break;
            case AgentState.Error:
                dc.DrawLine(P(color,1.6),new Point(0,-3.7),new Point(0,.6));
                dc.DrawEllipse(B(color),null,new Point(0,3.3),.9,.9);break;
            default:
                dc.PushOpacity(.65);dc.DrawLine(P(color,1),new Point(-3,0),new Point(0,-3));dc.DrawLine(P(color,1),new Point(0,-3),new Point(3,0));dc.DrawLine(P(color,1),new Point(3,0),new Point(0,3));dc.DrawLine(P(color,1),new Point(0,3),new Point(-3,0));dc.Pop();break;
        }
        dc.Pop();
    }
    internal static void DrawSlot(DrawingContext dc,SkinDefinition skin,Slot slot,double w,double h,double flow,bool motion)
    {
        if(!slot.Occupied)return;
        bool stale=Stale(slot),attention=slot.Unread && slot.Connected && slot.State is AgentState.Ready or AgentState.Waiting or AgentState.Error;
        string color=stale?skin.Unknown:slot.StateColor;
        var state=slot.Connected && !stale?slot.State:AgentState.Unknown;
        dc.PushTransform(new TranslateTransform(-w/2+22,h/2-3));
        if(SkinCatalog.DecorationsEnabled && attention)ThemeTrim(dc,skin,18,flow+slot.Number*.13,motion && !stale,true);
        Glyph(dc,skin,state,color,flow+slot.Number*.13,motion && !stale,attention);dc.Pop();
    }
    internal static void DrawCore(DrawingContext dc,SkinDefinition skin,IReadOnlyList<Slot> slots,Slot? current,double flow,bool motion,double reveal=1)
    {
        var summary=WheelStatusSummary.From(slots);if(!CoreVisible(summary))return;
        int count=CoreCount(summary);string color=summary.Color(skin);var state=CoreState(summary);
        double width=count>0?32:19;
        // One small equipment seal, tucked into the lower-right corner. The only
        // persistent text is a meaningful aggregate count; artwork remains open.
        dc.PushTransform(new TranslateTransform(36,43));
        var plate=Seal(width,skin);
        dc.DrawGeometry(SealGlass(skin),null,plate);
        dc.PushOpacity(.32);dc.DrawGeometry(null,P(skin.Border,.6),plate);dc.Pop();
        dc.PushOpacity(.22);dc.DrawLine(P(skin.Accent,.6),new Point(-width/2+5,-7),new Point(width/2-5,-7));dc.Pop();
        if(SkinCatalog.DecorationsEnabled)ThemeTrim(dc,skin,width,flow,motion,summary.Attention>0);
        double glyphX=count>0?-6:0;
        dc.PushTransform(new TranslateTransform(glyphX,0));Glyph(dc,skin,state,color,flow,motion,summary.Attention>0);dc.Pop();
        if(count>0)Label(dc,count.ToString(CultureInfo.InvariantCulture),skin.Text,10,14,7.5,0);
        if(motion && summary.Attention>0 && reveal<1) {
            dc.PushOpacity((1-reveal)*.65);
            double spread=9+reveal*10;
            dc.DrawEllipse(B(color),null,new Point(-spread,-7-reveal*5),1.1,1.1);
            dc.DrawEllipse(B(color),null,new Point(6+reveal*9,-11-reveal*7),.8,.8);
            dc.Pop();
        }
        dc.Pop();
    }
}
