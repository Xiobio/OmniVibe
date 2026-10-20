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

/// <summary>Readable equipment HUD: high-contrast state tickets and one compact
/// aggregate. Short captions and distinct shapes work without color or motion.</summary>
internal static class WheelTaskStatus
{
    private static readonly Dictionary<string,Brush> Brushes=new();
    private static readonly Dictionary<(string,double),Pen> Pens=new();
    private static readonly Dictionary<(string,string,double,double),DrawingGroup> Labels=new();
    private static readonly Dictionary<(string,string),Brush> Glass=new();
    private static readonly Dictionary<string,Brush> Glows=new();
    private static readonly Dictionary<(double,bool),Geometry> Seals=new();
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
        var c=(Color)ColorConverter.ConvertFromString(color);c.A=115;
        var brush=new RadialGradientBrush(c,Colors.Transparent);brush.Freeze();Glows[color]=brush;return brush;
    }
    private static Brush SealGlass(SkinDefinition skin)
    {
        var key=(skin.Background,skin.Elevated);if(Glass.TryGetValue(key,out var cached))return cached;
        Color top=(Color)ColorConverter.ConvertFromString(skin.Elevated),bottom=(Color)ColorConverter.ConvertFromString(skin.Background);top.A=244;bottom.A=230;
        var brush=new LinearGradientBrush(top,bottom,90);brush.Freeze();Glass[key]=brush;return brush;
    }
    private static Geometry Seal(double width,bool angular)
    {
        if(Seals.TryGetValue((width,angular),out var cached))return cached;
        Geometry result;
        if(angular) {
            var g=new StreamGeometry();using(var c=g.Open()) {
                c.BeginFigure(new Point(-width/2+4,-9),true,true);
                c.PolyLineTo(new[]{new Point(width/2-3,-9),new Point(width/2,-6),new Point(width/2,5),new Point(width/2-4,9),new Point(-width/2+3,9),new Point(-width/2,6),new Point(-width/2,-5)},true,false);
            }
            result=g;
        } else result=new RectangleGeometry(new Rect(-width/2,-9,width,18),6,6);
        result.Freeze();Seals[(width,angular)]=result;return result;
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
        // Keep the weapon silhouette free: its foot carries a readable status
        // ticket, independently of desktop wallpaper and the portrait's colors.
        double scale=Math.Clamp(w/88,.75,1.1);
        dc.PushTransform(new TranslateTransform(6,h/2-2));dc.PushTransform(new ScaleTransform(scale,scale));
        double width=state==AgentState.Unknown?22:56;
        var plate=Seal(width,skin.Family is "mechanical" or "tactical" or "protocol" or "formation");
        string ink=attention?ContrastInk(color):color;
        dc.DrawGeometry(attention?B(color):SealGlass(skin),P(attention?ink:color,.8),plate);
        if(attention && motion) {
            dc.PushOpacity(.2+.45*Math.Pow(Math.Sin(flow*Math.PI*3),2));
            dc.DrawLine(P(color,2.2),new Point(-width/2+5,-12),new Point(width/2-5,-12));dc.Pop();
        }
        dc.PushTransform(new TranslateTransform(state==AgentState.Unknown?0:-17,0));
        dc.PushTransform(new ScaleTransform(1.35,1.35));Glyph(dc,skin,state,ink,flow+slot.Number*.13,motion && !stale,false);dc.Pop();dc.Pop();
        if(state!=AgentState.Unknown)Label(dc,state==AgentState.Ready && !slot.Unread?"已看":ShortCaption(state),ink,10.5,31,9,0);
        dc.Pop();dc.Pop();
    }
    internal static string ShortCaption(AgentState state) => state switch { AgentState.Ready=>"待看",AgentState.Waiting=>"确认",AgentState.Error=>"异常",AgentState.Running=>"运行",_=>"未连" };
    private static string ContrastInk(string color) => SkinCatalog.Luminance(color)>.35?"#101B20":"#FFFFFF";
    internal static void DrawCore(DrawingContext dc,SkinDefinition skin,IReadOnlyList<Slot> slots,Slot? current,double flow,bool motion,double reveal=1)
    {
        var summary=WheelStatusSummary.From(slots);if(!CoreVisible(summary))return;
        int count=CoreCount(summary);string color=summary.Color(skin);var state=CoreState(summary);
        bool attention=summary.Attention>0;
        double width=count>0?84:26;
        // A clear bottom seal fits inside the 116 px compact host. It never
        // encloses the character or adds a second ring around the equipment.
        dc.PushTransform(new TranslateTransform(0,41));dc.PushTransform(new ScaleTransform(1,1.4));
        var plate=Seal(width,skin.Family is "mechanical" or "tactical" or "protocol" or "formation");
        dc.DrawGeometry(SealGlass(skin),P(color,1.15),plate);
        if(attention) {
            double pulse=motion?.5+.5*Math.Pow(Math.Sin(flow*Math.PI*3),2):1;
            dc.PushOpacity(pulse);dc.DrawLine(P(color,2),new Point(-width/2+7,-8),new Point(width/2-7,-8));dc.Pop();
        }
        dc.Pop();
        double glyphX=count>0?-27:0;
        dc.PushTransform(new TranslateTransform(glyphX,0));
        dc.DrawRoundedRectangle(B(color),null,new Rect(-9,-9,18,18),4,4);
        dc.PushTransform(new ScaleTransform(1.4,1.4));Glyph(dc,skin,state,ContrastInk(color),flow,motion,false);dc.Pop();dc.Pop();
        if(count>0) {
            Label(dc,count.ToString(CultureInfo.InvariantCulture),color,16,18,-7,0);
            Label(dc,attention?"待办":"运行",skin.Text,11,28,19,0);
        }
        if(motion && attention && reveal<1) {
            dc.PushOpacity((1-reveal)*.8);
            double spread=20+reveal*32;
            dc.DrawLine(P(color,2),new Point(-spread,-17),new Point(-spread+7,-22));
            dc.DrawLine(P(color,2),new Point(spread-7,-22),new Point(spread,-17));
            dc.Pop();
        }
        dc.Pop();
    }
}
