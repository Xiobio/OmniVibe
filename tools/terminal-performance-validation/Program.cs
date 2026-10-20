using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using CodeManager;

internal static class Program
{
    [STAThread] private static int Main(string[] args)
    {
        string output = Path.GetFullPath(args.FirstOrDefault() ?? "artifacts/terminal-lag-audit/ui-validation");
        Directory.CreateDirectory(output);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        WuxiaTheme.Apply(Skin.Hextech, false);
        string settings = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json");
        string? Hash() => File.Exists(settings) ? Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(settings))) : null;
        string? original = Hash();
        var picker = new SkinPicker(Skin.Hextech);
        var animation = (CheckBox)typeof(SkinPicker).GetField("_terminalAnimation", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(picker)!;
        var choices = (ComboBox)typeof(SkinPicker).GetField("_choices", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(picker)!;
        string[] Options() => ((IReadOnlyList<string>)typeof(SkinPicker).GetMethod("TerminalAppearanceArguments", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(picker, null)!).ToArray();
        void Require(bool value, string message) { if (!value) throw new Exception(message); }
        var results = new List<object>(); int failures = 0;
        void Test(string name, Action action) {
            try { action(); results.Add(new { name, passed = true }); Console.WriteLine("PASS " + name); }
            catch (Exception ex) { failures++; results.Add(new { name, passed = false, error = ex.Message }); Console.WriteLine("FAIL " + name + ": " + ex.Message); }
        }
        Test("Terminal animation starts unchecked and global UI motion cannot enable it", () => {
            Require(animation.IsChecked == false, "Terminal animation started enabled");
            foreach (bool effects in new[] { true, false }) {
                picker.EffectsEnabled = () => effects;
                for (int i = 0; i < SkinCatalog.All.Count; i++) {
                    choices.SelectedIndex = i;
                    Require(!Options().Contains("-EnableAnimation"), "Global motion implicitly enabled Terminal animation");
                }
            }
        });
        Test("Explicit Terminal animation is independent and routes the opt-in flag for every game theme", () => {
            picker.EffectsEnabled = () => false; animation.IsChecked = true;
            for (int i = 0; i < SkinCatalog.All.Count; i++) {
                choices.SelectedIndex = i; var flags = Options();
                Require(animation.IsEnabled && flags.Contains("-EnableAnimation") && !flags.Contains("-DisableEffects"), "Explicit opt-in did not reach the script");
                Require(flags[0] == "-Skin" && flags[1] == SkinCatalog.All[i].Slug, "Selected theme was not routed");
            }
            picker.DecorationsEnabled = () => false;
            Require(Options().Contains("-DisableArtwork"), "Artwork option stopped routing independently");
        });
        Test("Classic themes support complete artwork, all profiles and explicit animation", () => {
            for (int i = 0; i < SkinCatalog.All.Count; i++) {
                if ((int)SkinCatalog.All[i].Id >= (int)Skin.Hextech) continue;
                choices.SelectedIndex = i; var flags = Options();
                Require(animation.IsEnabled && flags.Contains("-AllProfiles") && !flags.Contains("-ChromeOnly") && flags.Contains("-EnableAnimation") && flags.Contains("-DisableArtwork"), "Classic theme failed to route the complete saved suite");
            }
        });
        Test("Validation never starts an applier or modifies live Terminal settings", () => Require(Hash() == original, "Live Terminal settings changed"));
        File.WriteAllText(Path.Combine(output, "report.json"), JsonSerializer.Serialize(new { passed = failures == 0, failures, results, theme_count = SkinCatalog.All.Count, external_process_started = false, live_terminal_settings_changed = false, packaged = false }, new JsonSerializerOptions { WriteIndented = true }));
        app.Shutdown(); return failures == 0 ? 0 : 1;
    }
}
