using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CodeManager;

internal static class LocalizationTests
{
    internal static List<SelfTests.Result> Run()
    {
        var results = new List<SelfTests.Result>();
        void Test(string name, Action action)
        {
            try { action(); results.Add(new(name, true, "OK")); }
            catch (Exception ex) { results.Add(new(name, false, ex.ToString())); }
        }
        void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
        Test("English resource: unique keys, valid formats, matching arguments", () =>
        {
            using var stream = typeof(L).Assembly.GetManifestResourceStream("OmniVibe.Localization.English")!;
            using var reader = new StreamReader(stream);
            var keys = new HashSet<string>();
            while (reader.ReadLine() is string line)
            {
                int tab = line.IndexOf('\t'); if (tab < 0) continue;
                string key = line[..tab], value = line[(tab + 1)..];
                Check(keys.Add(key) && value.Length > 0, "Duplicate or empty: " + key);
                string Args(string text) => string.Join(",", Regex.Matches(text, @"(?<!\{)\{(\d+)(?:[^{}]*)\}").Select(m => m.Groups[1].Value).OrderBy(s => s));
                Check(Args(key) == Args(value), "Format arguments changed: " + key);
                if (Args(key) != "") { CompositeFormat.Parse(key); CompositeFormat.Parse(value); }
            }
            Check(keys.Count >= 500, "Language resource incomplete");
        });
        Test("Default theme and sound follow Relic; saved preferences survive serialization", () =>
        {
            var prefs = new Preferences();
            Check(prefs.Skin == Skin.Relic && SignatureAudio.ResolveTheme(prefs) == Skin.Relic, "Wrong new-user theme");
            prefs.Language = "en"; prefs.Skin = Skin.Hextech;
            var copy = JsonSerializer.Deserialize<Preferences>(JsonSerializer.Serialize(prefs))!;
            Check(copy.Language == "en" && copy.Skin == Skin.Hextech, "Existing choice lost");
        });
        Test("Localized UI preserves task data and terminal signal behavior", () =>
        {
            Check(L.IsEnglish, "Run this test with --language=en");
            var slot = new Slot { Number = 1, Name = "用户项目 · API", StateSource = "终端状态信号", State = AgentState.Waiting, Connected = true, Window = new() { Title = "用户终端", ProcessName = "fixture" } };
            string before = JsonSerializer.Serialize(slot);
            Check(WheelTaskStatus.LabelFor(slot) == L.T("通知待查看"), "Signal source comparison changed");
            _ = slot.IntegrationLabel;
            Check(JsonSerializer.Serialize(slot) == before, "Display translated stored user data");
            Check(L.T("设置") != "设置", "English not applied");
            Check(TaskNotifications.Caption(AgentState.Ready) == "Response unread", "System notification caption stayed Chinese");
            foreach (string message in new[] { "需要你的输入", "终端正在执行（标题或进度信号）", "终端发出通知，请查看结果或确认请求", "忙碌标记已结束，完成状态待确认", "手动标记", "外部事件" })
                Check(L.HasTranslation(message), "Untranslated status text: " + message);
            foreach (string hook in new[] { "SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop", "StopFailure", "Interrupt", "SessionEnd" })
                Check(L.HasTranslation(HookBridge.Parse("claude", Guid.NewGuid().ToString(), "{\"hook_event_name\":\"" + hook + "\"}")!.Message), "Untranslated hook status: " + hook);
        });
        Test("All themes retain identity and expose English metadata", () =>
        {
            Check(SkinCatalog.All.Count == 13 && SkinCatalog.All.Select(s => s.Id).Distinct().Count() == 13, "Missing theme");
            foreach (var skin in SkinCatalog.All)
            {
                Check(!Regex.IsMatch(skin.Name + skin.Subtitle, @"[\u4e00-\u9fff?]"), "Untranslated theme: " + skin.Slug);
                Check(skin.SlotNumber(1) == "01", "English slot label");
                Check(EquipmentCatalog.Pack(skin.Id).Items.Count == 9, "Missing loadout");
            }
        });
        return results;
    }
}
