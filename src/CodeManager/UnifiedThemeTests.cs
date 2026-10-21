using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace CodeManager;

public static class UnifiedThemeTests
{
    public static List<SelfTests.Result> Run(string output)
    {
        var results = new List<SelfTests.Result>(); Directory.CreateDirectory(output);
        void Check(bool condition,string message) { if (!condition) throw new InvalidOperationException(message); }
        void Test(string name, Action action) { try { action(); results.Add(new(name,true,"OK")); } catch(Exception ex) { results.Add(new(name,false,ex.ToString())); } }
        string? live = TerminalThemeService.FindSettings();
        string? hash = live == null ? null : Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(live)));
        Test("All thirteen themes: complete static assets, usable independent animation and full profile arguments", () => {
            foreach (var skin in SkinCatalog.All) {
                var picker = new SkinPicker(skin.Id,true); picker.DecorationsEnabled = () => false;
                var checkbox = Nodes(picker).OfType<CheckBox>().Single(c => System.Windows.Automation.AutomationProperties.GetName(c)=="Terminal 背景动画");
                Check(checkbox.IsEnabled && checkbox.IsChecked==true && picker.TerminalAnimationEnabled,skin.Slug+": saved animation cannot be selected");
                var args = picker.TerminalAppearanceArguments();
                Check(args.Contains("-EnableAnimation") && args.Contains("-DisableArtwork") && args.Contains("-AllProfiles") && !args.Contains("-ChromeOnly"),skin.Slug+": incomplete suite arguments");
                Check(!picker.Scene.AssetStatus.Contains("未找到") && !picker.Scene.AssetStatus.Contains("暂无"),skin.Slug+": preview missing actual static asset");
                foreach(string suffix in new[]{"c-v1.png","frame-only-v1.png","c-v1.gif","frame-only-v1.gif"}) Check(File.Exists(Path.Combine(AppContext.BaseDirectory,"themes/windows-terminal/assets/refined-v1",skin.Slug+"-"+suffix)),skin.Slug+": missing "+suffix);
            }
        });
        Test("Settings save invokes one unified applier; animation persists and caller draft stays unchanged", () => {
            var source = new Preferences { Skin=Skin.Hextech }; int called=0; Preferences? applied=null;
            var dialog = new SettingsWindow(source,new Native.Rect(0,0,1920,1040),"") { ShowActivated=false,Topmost=false,Left=-20000,Top=-20000 };
            dialog.ApplyThemeAsync = p => { called++; applied=p.Copy(); return Task.FromResult(new TerminalThemeReceipt(true,"fixture","Applied")); };
            Dispatcher.CurrentDispatcher.BeginInvoke(() => {
                var picker=Nodes(dialog.Content).OfType<SkinPicker>().Single(); picker.SelectSkin(Skin.Midnight);
                Nodes(picker).OfType<CheckBox>().Single(c=>System.Windows.Automation.AutomationProperties.GetName(c)=="Terminal 背景动画").IsChecked=true;
                Nodes(dialog.Content).OfType<Button>().Single(b=>b.Content as string=="保存并应用").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            },DispatcherPriority.ApplicationIdle);
            Check(dialog.ShowDialog()==true && called==1 && applied?.Skin==Skin.Midnight && applied.TerminalAnimation && dialog.Result.TerminalAnimation,"Unified settings transaction not committed");
            Check(source.Skin==Skin.Hextech && !source.TerminalAnimation,"Settings mutated caller before acceptance");
            var roundtrip=JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(dialog.Result,StateStore.Json),StateStore.Json)!;
            Check(roundtrip.TerminalAnimation && new SkinPicker(roundtrip.Skin,roundtrip.TerminalAnimation).TerminalAnimationEnabled,"Saved animation disappeared on reopening");
        });
        Test("Failed Terminal application keeps the settings draft open and reports the failure", () => {
            var source=new Preferences { Skin=Skin.InkJade };
            var dialog=new SettingsWindow(source,new Native.Rect(0,0,1920,1040),"") { ShowActivated=false,Topmost=false,Left=-20000,Top=-20000 };
            try {
                dialog.ApplyThemeAsync=_=>Task.FromException<TerminalThemeReceipt>(new IOException("fixture appearance failure")); dialog.Show();
                Nodes(dialog.Content).OfType<SkinPicker>().Single().SelectSkin(Skin.Cinnabar);
                Nodes(dialog.Content).OfType<Button>().Single(b=>b.Content as string=="保存并应用").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
                Check(dialog.IsVisible && dialog.Result.Skin==Skin.InkJade && Nodes(dialog.Content).OfType<TextBlock>().Any(t=>t.Text.Contains("fixture appearance failure")),"Terminal failure was silently accepted");
            } finally { dialog.Close(); }
        });
        const string fixture="""
        {"defaultProfile":"keep-guid","actions":[{"command":"paste","keys":"ctrl+v"}],"profiles":{"defaults":{"font":{"face":"fixture font","size":17},"backgroundImage":"old.png"},"list":[{"guid":"keep-guid","name":"fixture","commandline":"cmd.exe /k echo preserve","startingDirectory":"D:\\task","environment":{"KEEP":"value"},"tabColor":"#123456","colorScheme":"Campbell","backgroundImage":"pinned.png","foreground":"#000000","unfocusedAppearance":{"backgroundImage":"pinned-unfocused.png","foreground":"#111111"}}]}}
        """;
        Test("Actual C# applier switches all thirteen suites including pinned profiles without touching launch settings", () => {
            var records=new List<object>();
            foreach (var skin in SkinCatalog.All) {
                string folder=Path.Combine(output,skin.Slug); Directory.CreateDirectory(folder); string settings=Path.Combine(folder,"settings.json"); File.WriteAllText(settings,fixture);
                string claudeTheme=Path.Combine(folder,"claude","themes","omnivibe.json");
                var receipt=TerminalThemeService.ApplyAsync(new Preferences {Skin=skin.Id},settings,Path.Combine(folder,"assets"),claudeTheme).GetAwaiter().GetResult();
                Check(receipt.Applied && File.ReadAllText(receipt.BackupPath)==fixture,skin.Slug+": backup is not byte exact");
                using var document=JsonDocument.Parse(File.ReadAllText(settings)); var root=document.RootElement; var profiles=root.GetProperty("profiles"); var defaults=profiles.GetProperty("defaults"); var profile=profiles.GetProperty("list")[0];
                Check(root.GetProperty("defaultProfile").GetString()=="keep-guid" && profile.GetProperty("commandline").GetString()=="cmd.exe /k echo preserve" && profile.GetProperty("environment").GetProperty("KEEP").GetString()=="value" && defaults.GetProperty("font").GetProperty("face").GetString()=="fixture font",skin.Slug+": task launch/preferences changed");
                string scheme="OmniVibe / "+skin.Name;
                Check(root.GetProperty("theme").GetString()==scheme && defaults.GetProperty("colorScheme").GetString()==scheme && profile.GetProperty("colorScheme").GetString()==scheme && profile.GetProperty("unfocusedAppearance").GetProperty("colorScheme").GetString()==scheme,skin.Slug+": suite stayed split");
                Check(!profile.TryGetProperty("foreground",out _) && !profile.TryGetProperty("tabColor",out _),skin.Slug+": explicit overrides blocked the skin");
                string image=defaults.GetProperty("backgroundImage").GetString()!; Check(image.EndsWith(".png") && File.Exists(image) && profile.GetProperty("backgroundImage").GetString()==image,skin.Slug+": static image did not apply");
                using var claude=JsonDocument.Parse(File.ReadAllText(claudeTheme)); var overrides=claude.RootElement.GetProperty("overrides");
                string band=overrides.GetProperty("userMessageBackground").GetString()!;
                Check(claude.RootElement.GetProperty("name").GetString()=="OmniVibe" && System.Text.RegularExpressions.Regex.IsMatch(band,"^#[0-9A-F]{6}$") && band!="#373737",skin.Slug+": Claude message band was not retinted");
                records.Add(new {skin=skin.Slug,applied=true,all_profiles=true,background=image,claude_base=claude.RootElement.GetProperty("base").GetString(),claude_user_message=band});
            }
            File.WriteAllText(Path.Combine(output,"actual-applier.json"),JsonSerializer.Serialize(records,StateStore.Json));
        });
        Test("Three classic themes: explicit animation installs GIF and static switch installs PNG", () => {
            foreach(var skin in SkinCatalog.All.Take(3)) {
                string folder=Path.Combine(output,skin.Slug),settings=Path.Combine(folder,"settings.json");
                TerminalThemeService.ApplyAsync(new Preferences {Skin=skin.Id,TerminalAnimation=true},settings,Path.Combine(folder,"assets")).GetAwaiter().GetResult();
                using(var json=JsonDocument.Parse(File.ReadAllText(settings))) Check(json.RootElement.GetProperty("profiles").GetProperty("defaults").GetProperty("backgroundImage").GetString()!.EndsWith(".gif"),"Animation toggle did not install GIF");
                TerminalThemeService.ApplyAsync(new Preferences {Skin=skin.Id},settings,Path.Combine(folder,"assets")).GetAwaiter().GetResult();
                using var after=JsonDocument.Parse(File.ReadAllText(settings)); Check(after.RootElement.GetProperty("profiles").GetProperty("defaults").GetProperty("backgroundImage").GetString()!.EndsWith(".png"),"Disabling animation retained GIF");
            }
        });
        Test("Malformed settings reject actual application and live Terminal remains untouched", () => {
            string bad=Path.Combine(output,"invalid-settings.json");File.WriteAllText(bad,"{invalid fixture");bool rejected=false;
            try {TerminalThemeService.ApplyAsync(new Preferences(),bad,Path.Combine(output,"invalid-assets")).GetAwaiter().GetResult();} catch(IOException){rejected=true;}
            Check(rejected && File.ReadAllText(bad)=="{invalid fixture","Invalid settings were overwritten");
            Check(live==null || Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(live)))==hash,"Fixture validation changed live Terminal");
        });
        return results;
    }
    private static IEnumerable<DependencyObject> Nodes(object? value)
    {
        if(value is not DependencyObject node)yield break;yield return node;
        foreach(object child in LogicalTreeHelper.GetChildren(node))foreach(var descendant in Nodes(child))yield return descendant;
    }
}
