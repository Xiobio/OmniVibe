using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace CodeManager;

public sealed record TerminalThemeReceipt(bool Applied, string BackupPath, string Message);

public static class TerminalThemeService
{
    internal static IReadOnlyList<string> Arguments(Skin skin, bool animation, bool artwork)
    {
        var args = new List<string> { "-Skin", SkinCatalog.Get(skin).Slug, "-AllProfiles" };
        if (animation) args.Add("-EnableAnimation");
        if (!artwork) args.Add("-DisableArtwork");
        return args;
    }
    internal static string? FindSettings()
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var candidates = new List<string>();
        foreach (var process in Process.GetProcessesByName("WindowsTerminal")) {
            using (process) try {
                string? exe = process.MainModule?.FileName;
                if (exe?.Contains("WindowsTerminalPreview", StringComparison.OrdinalIgnoreCase) == true)
                    candidates.Add(Path.Combine(local,"Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"));
                if (exe != null && File.Exists(Path.Combine(Path.GetDirectoryName(exe)!,".portable"))) candidates.Add(Path.Combine(Path.GetDirectoryName(exe)!,"settings/settings.json"));
            } catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or NotSupportedException) { }
        }
        candidates.AddRange(new[] { "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json", "Microsoft/Windows Terminal/settings.json", "Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" }.Select(p => Path.Combine(local,p)));
        return candidates.FirstOrDefault(File.Exists);
    }
    public static async Task<TerminalThemeReceipt> ApplyAsync(Preferences preferences, string? settingsPath = null, string? assetRoot = null)
    {
        settingsPath ??= FindSettings();
        if (settingsPath == null) return new(false,"","未找到 Windows Terminal 配置，已仅保存 OmniVibe 外观。");
        string script = Path.Combine(AppContext.BaseDirectory,"themes/windows-terminal/Apply-Skin.ps1");
        if (!File.Exists(script)) throw new IOException("Terminal 外观应用器缺失，请从源码重新运行。");
        var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
        foreach (string arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script, "-SettingsPath", Path.GetFullPath(settingsPath) }) start.ArgumentList.Add(arg);
        if (assetRoot != null) { start.ArgumentList.Add("-AssetRoot"); start.ArgumentList.Add(Path.GetFullPath(assetRoot)); }
        foreach (string arg in Arguments(preferences.Skin,preferences.TerminalAnimation,preferences.DecorationsEnabled)) start.ArgumentList.Add(arg);
        using var process = Process.Start(start) ?? throw new IOException("无法启动 Terminal 外观应用器。");
        var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        try { await process.WaitForExitAsync(timeout.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) { try { process.Kill(entireProcessTree:true); } catch (InvalidOperationException) { } throw new IOException("Terminal 外观应用超时，当前 OmniVibe 主题未更改。"); }
        string text = await output.ConfigureAwait(false), problem = await error.ConfigureAwait(false);
        if (process.ExitCode != 0) throw new IOException(problem.Split(new[] {'\r','\n'},StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "Terminal 外观未能应用，请重试。");
        using var result = JsonDocument.Parse(text);
        var json = result.RootElement;
        string backup = json.GetProperty("BackupPath").GetString() ?? "";
        if (json.GetProperty("Skin").GetString() != SkinCatalog.Get(preferences.Skin).Slug || !json.GetProperty("AllProfiles").GetBoolean() || !File.Exists(backup)) throw new IOException("Terminal 应用结果不完整，未确认同步成功。");
        return new(true,backup,"Terminal 与 OmniVibe 已应用同一套主题。");
    }
}
