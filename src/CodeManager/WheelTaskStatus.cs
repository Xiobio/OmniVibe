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
    internal string Label => Errors>0 ? Errors+" 处异常 · 待处理" : Waiting>0 ? Waiting+" 项需要处理" : Ready>0 ? Ready+" 个回复待查看" : Running>0 ? Running+" 个任务执行中" : Unlinked>0 ? "未接入自动状态" : "已查看 · 等待任务";
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

/// <summary>State feedback independent of weapon art: theme-colored rune rails,
/// live motion and a persistent aggregate notification inside the 116px idle host.</summary>
internal static class WheelTaskStatus
{
    private static readonly Dictionary<string,Brush> Brushes=new();
    private static readonly Dictionary<(string,double),Pen> Pens=new();
    private static readonly Dictionary<(string,string,double,double),DrawingGroup> Labels=new();
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
    private static void Rail(DrawingContext dc,SkinDefinition skin,string color,double half,double y,double flow,bool active,bool attention)
    {
        dc.PushOpacity(.38);dc.DrawLine(P(color,1),new Point(-half,y),new Point(half,y));dc.Pop();
        // Material-specific finials: instrument diamonds, mechanical notches,
        // tactical ticks and star points. These do not surround the weapon art.
        bool angular=skin.Family is "mechanical" or "tactical" or "protocol" or "formation";
        foreach(double x in new[]{-half,half}) {
            double lean=x<0?-3:3;
            dc.DrawLine(P(color,1),new Point(x,y),new Point(x+lean,y-(angular?4:2)));
            if(!angular)dc.DrawLine(P(color,1),new Point(x,y),new Point(x-lean,y+2));
        }
        if(active) {
            double t=(flow*3)%1, x=-half+half*2*t;
            dc.PushOpacity(attention?.55+.4*Math.Pow(Math.Sin(flow*Math.PI*6),2):.9);
            if(attention) {
                dc.DrawLine(P(color,2),new Point(-half,y),new Point(half,y));
                dc.DrawLine(P(color,1.2),new Point(-half-2,y-5),new Point(-half-2,y+3));
                dc.DrawLine(P(color,1.2),new Point(half+2,y-5),new Point(half+2,y+3));
            } else {
                dc.DrawLine(P(color,2),new Point(Math.Max(-half,x-12),y),new Point(x,y));
                dc.DrawEllipse(B(color),null,new Point(x,y),1.7,1.7);
            }
            dc.Pop();
        }
    }
    internal static void DrawSlot(DrawingContext dc,SkinDefinition skin,Slot slot,double w,double h,double flow,bool motion)
    {
        if(!slot.Occupied)return;
        string color=Stale(slot)?skin.Unknown:slot.StateColor; bool attention=slot.Unread && slot.Connected && slot.State is AgentState.Ready or AgentState.Waiting or AgentState.Error;
        Rail(dc,skin,color,w*.36,h/2+4,flow+slot.Number*.13,motion && slot.Connected && !Stale(slot) && (attention || slot.State==AgentState.Running),attention);
        dc.PushOpacity(.94);dc.DrawRoundedRectangle(B(skin.Background),null,new Rect(-w*.54,h/2+8,w*1.08,16),5,5);dc.Pop();
        Label(dc,LabelFor(slot),color,9,w*1.02,0,h/2+16);
    }
    internal static void DrawCore(DrawingContext dc,SkinDefinition skin,IReadOnlyList<Slot> slots,Slot? current,double flow,bool motion)
    {
        if(!slots.Any(s=>s.Occupied))return;
        var summary=WheelStatusSummary.From(slots);string color=summary.Color(skin);
        bool animated=motion && (summary.Attention>0 || summary.Running>0);
        // Gentle breathing and moving accents fit entirely inside the compact host.
        Rail(dc,skin,color,44,29,flow,animated,summary.Attention>0);
        dc.PushOpacity(.96);dc.DrawRoundedRectangle(B(skin.Background),P(color,.75),new Rect(-55,34,110,21),9,9);dc.Pop();
        Label(dc,summary.Label,color,9,105,0,44);
        if(summary.Attention>0) {
            dc.PushOpacity(animated?.6+.4*Math.Pow(Math.Sin(flow*Math.PI*6),2):1);
            dc.DrawEllipse(B(skin.Background),P(color,1.3),new Point(43,-40),11,11);
            Label(dc,summary.Attention.ToString(),color,11,19,43,-40);dc.Pop();
        }
        if(summary.Running>0 && summary.Attention>0) Label(dc,summary.Running+" 执行中",skin.Running,8,84,0,-47);
    }
}
