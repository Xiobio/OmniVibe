using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows.Media;

namespace CodeManager;

/// <summary>One palette contract shared by native controls, equipment cards and terminal presets.</summary>
public sealed record SkinDefinition(
    Skin Id, string Slug, string Name, string Subtitle, string DockTitle, string OverviewTitle,
    string Family, string Background, string Surface, string Elevated, string Text, string Muted,
    string Accent, string Secondary, string Border, string Running, string Waiting, string Ready,
    string Error, string Unknown, string CardBackground, string CardText, double CornerRadius,
    FontFamily TitleFont)
{
    public string Artwork => $"skins/{Slug}/illustration.png";
    public bool IsLight => SkinCatalog.Luminance(Background) > .5;
    public string SlotNumber(int number) => Family is "ink" or "arsenal" or "relic" ?
        (number is >= 1 and <= 9 ? new[] { "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖" }[number - 1] : "零") :
        number.ToString(Family is "tactical" or "protocol" ? "D2" : "0", CultureInfo.InvariantCulture);
}

public static class SkinCatalog
{
    public static bool DecorationsEnabled { get; set; } = true;
    public static SkinDefinition Current => Get(WuxiaTheme.CurrentSkin);
    private static readonly FontFamily Modern = new("Bahnschrift, Microsoft YaHei UI, Segoe UI");
    private static readonly FontFamily Classic = new("KaiTi, STKaiti, FangSong, SimSun");
    private static readonly FontFamily Elegant = new("Georgia, Microsoft YaHei UI, Segoe UI");
    public static IReadOnlyList<SkinDefinition> All { get; } = Array.AsReadOnly(new[]
    {
        new SkinDefinition(Skin.InkJade, "ink-jade", "墨玉机关", "水墨 · 机关 · 玉石", "九宫剑匣", "九宫百宝囊", "ink", "#111714", "#241F18", "#343B2C", "#E7D8B6", "#B9AE94", "#BFA76C", "#82B89B", "#8F7D54", "#82B89B", "#E6C279", "#ACD5AB", "#F38E7C", "#ABB5A5", "#D8C8A5", "#342D22", 2, Classic),
        new SkinDefinition(Skin.Midnight, "midnight", "玄夜青金", "夜色 · 青金 · 山海", "玄夜剑匣", "玄夜百宝囊", "ink", "#111827", "#18283F", "#263C58", "#E8E5D8", "#B1BDCE", "#BDB27D", "#76BBC8", "#7B98A8", "#85D5C7", "#EFCE81", "#ADD9BE", "#FF9E99", "#AAB9CC", "#CBD2D7", "#243344", 2, Classic),
        new SkinDefinition(Skin.Cinnabar, "cinnabar", "朱砂藏锋", "漆红 · 古铜 · 藏锋", "藏锋剑匣", "朱砂百宝囊", "ink", "#211516", "#352023", "#4B3031", "#F1DDCD", "#CCB4A6", "#DAAA78", "#D98B7B", "#AB8266", "#B6D5AC", "#F0CA7C", "#C1D9B5", "#FFA08D", "#C7AFA7", "#DBC5AD", "#442C26", 2, Classic),
        new SkinDefinition(Skin.Hextech, "hextech", "海克斯枢纽", "黄铜齿环 · 棱晶能量", "棱晶接入枢纽", "海克斯控制中枢", "mechanical", "#091A27", "#102B3B", "#1B3D4E", "#F1E8D2", "#A9C4D0", "#E6BE75", "#5EE6E0", "#92764C", "#65E4C5", "#FFD279", "#B1E6A7", "#FF9B89", "#ACBDC8", "#15313F", "#F1E8D2", 3, Elegant),
        new SkinDefinition(Skin.Tactical, "tactical", "战术终端", "炭黑合金 · 坐标标尺", "设备接入终端", "战术监控矩阵", "tactical", "#101714", "#1A2520", "#2B3830", "#E9EFE7", "#B4C4B8", "#D9BA6C", "#A6C994", "#718372", "#A6D6A0", "#FFD274", "#BBE5C4", "#FFA08D", "#B1BEB2", "#1B2822", "#E9EFE7", 0, Modern),
        new SkinDefinition(Skin.Protocol, "protocol", "行动协议", "几何切角 · 高对比指令", "行动接入面板", "并行行动协议", "protocol", "#151D26", "#25313E", "#354251", "#F4EEE3", "#C2C9D1", "#FF8C8E", "#75E0D4", "#8996A1", "#81E0C0", "#FAD27B", "#B3E3C1", "#FF9B9B", "#BCC7D0", "#202D39", "#F4EEE3", 0, Modern),
        new SkinDefinition(Skin.Adventure, "adventure", "冒险装备栏", "锻钢浮雕 · 皮革装具", "冒险装备栏", "远征背包与任务", "equipment", "#211A17", "#342820", "#493B2B", "#F0E0C1", "#C8B899", "#EAC480", "#91BCD4", "#A88B59", "#A8DAAF", "#FFD27B", "#C1DE9C", "#FF9B7F", "#C5B9A5", "#30271F", "#F0E0C1", 5, Elegant),
        new SkinDefinition(Skin.Arsenal, "arsenal", "无间兵器匣", "玄铁兵装 · 赤铜符印", "无间兵器匣", "兵器收纳阵列", "arsenal", "#191719", "#2D2528", "#443336", "#EFDFCA", "#C4AFA3", "#E1AD79", "#D3817C", "#A98161", "#ACD6B0", "#F3CA7E", "#C7D8A4", "#FF9C8C", "#C2B5AC", "#292326", "#EFDFCA", 1, Classic),
        new SkinDefinition(Skin.Relic, "relic", "灵蕴法宝匣", "玄岩石龛 · 錾金灵蕴", "灵蕴法宝匣", "灵蕴器物图录", "relic", "#1A1B19", "#2C2C27", "#414035", "#E8DDC3", "#C1B79C", "#D6B674", "#ADBA9A", "#98855D", "#B1CEAD", "#EBD08B", "#CADDAE", "#F3A08A", "#C2C1AF", "#292A25", "#E8DDC3", 10, Classic),
        new SkinDefinition(Skin.Starlight, "starlight", "星曜指挥台", "蓝金星冠 · 玉石辉光", "星曜指挥台", "星曜协同战阵", "fantasy", "#112238", "#1C3550", "#2D4962", "#F1E7D3", "#B7C9D9", "#ECD097", "#82DBDF", "#A28C62", "#94E0C5", "#FFE097", "#B7E6C2", "#FFAAA0", "#BCCADB", "#1C344C", "#F1E7D3", 11, Elegant),
        new SkinDefinition(Skin.Formation, "formation", "Agent 备战席", "蓝紫棋局 · 金色羁绊", "Agent 备战席", "Agent 阵容与项目", "formation", "#1D1A35", "#2B2848", "#3D375D", "#F2E8D9", "#C6BEDB", "#F0CE88", "#BCA9EF", "#A193BB", "#9CE0C7", "#FFDA8B", "#C2E8AE", "#FFA5AE", "#C9BEDC", "#2C2847", "#F2E8D9", 16, Modern),
        new SkinDefinition(Skin.Astral, "astral", "星旅背包", "深蓝星图 · 香槟细线", "星旅道具袋", "星旅任务图鉴", "astral", "#172A41", "#223B54", "#35506A", "#F1EBDD", "#C2CDD8", "#EAD6AE", "#9DCAD9", "#A6A28F", "#A8DCCF", "#F5D797", "#BDE4B7", "#FFB0A2", "#C6D1DC", "#EDE5D6", "#263E50", 8, Elegant),
        new SkinDefinition(Skin.Wonderland, "wonderland", "三界百宝袋", "青瓷彩绘 · 云纹绣金", "三界百宝袋", "三界百宝图鉴", "wonderland", "#EFF8F6", "#E1F0EA", "#D0E6DF", "#183C48", "#46616A", "#7C5918", "#216C77", "#729B94", "#236653", "#815C17", "#356733", "#A63739", "#53656D", "#FFF8E9", "#263E45", 18, Classic)
    });

    public static SkinDefinition Get(Skin skin) => All.FirstOrDefault(s => s.Id == skin) ?? All[0];
    public static double Luminance(string hex)
    {
        Color c = (Color)ColorConverter.ConvertFromString(hex);
        static double Linear(byte v) { double n = v / 255d; return n <= .04045 ? n / 12.92 : Math.Pow((n + .055) / 1.055, 2.4); }
        return .2126 * Linear(c.R) + .7152 * Linear(c.G) + .0722 * Linear(c.B);
    }
    public static double Contrast(string a, string b) { double x = Luminance(a), y = Luminance(b); return (Math.Max(x, y) + .05) / (Math.Min(x, y) + .05); }
}
