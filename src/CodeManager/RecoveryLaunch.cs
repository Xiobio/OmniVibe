using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace CodeManager;

public static class RecoveryLaunch
{
    public static string? Validation(Slot slot)
    {
        if (slot.LaunchMode == LaunchMode.Unconfigured) return "请先配置启动方式与项目目录";
        if (string.IsNullOrWhiteSpace(slot.ProjectDirectory)) return "请补充项目目录";
        if (!Path.IsPathFullyQualified(slot.ProjectDirectory) || !Directory.Exists(slot.ProjectDirectory)) return "项目目录不存在或不可访问";
        if (slot.LaunchMode != LaunchMode.Terminal && slot.ResumeConversation && !Guid.TryParse(slot.ResumeSessionId, out _)) return "缺少原会话 ID，可在配置中补充";
        return null;
    }
    public static string Quote(string text) => "'" + text.Replace("'", "''") + "'";
    public static string Acknowledgement(StateStore store, PendingRecovery pending) => Path.Combine(store.Root, "recovery", pending.Token + ".ready");
    public static string Script(Slot slot, StateStore store, PendingRecovery pending)
    {
        string title = "CM-RESTORE-" + pending.Token;
        string acknowledgement = Acknowledgement(store, pending);
        string script = "$ErrorActionPreference='Stop'; $Host.UI.RawUI.WindowTitle=" + Quote(title) + "; Set-Location -LiteralPath " + Quote(slot.ProjectDirectory) + "; " +
            "$ready=" + Quote(acknowledgement) + "; $deadline=[DateTime]::UtcNow.AddSeconds(25); while (!(Test-Path -LiteralPath $ready) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }; " +
            "if (!(Test-Path -LiteralPath $ready)) { Write-Host 'CodeManager did not reconnect this window. Keep it open and reconnect from the recovery panel.'; return }; " +
            "$Host.UI.RawUI.WindowTitle=" + Quote(slot.DisplayName) + "; ";
        if (slot.LaunchMode != LaunchMode.Terminal)
        {
            string starter = Path.Combine(AppContext.BaseDirectory, "scripts", "Start-TrackedSession.ps1");
            script += "& " + Quote(starter) + " -TaskId " + Quote(slot.Id) + " -Provider " + Quote(slot.LaunchMode == LaunchMode.Claude ? "claude" : "codex") + " -DataRoot " + Quote(store.Root) + " -ProjectDirectory " + Quote(slot.ProjectDirectory);
            if (slot.ResumeConversation) script += " -ResumeSessionId " + Quote(slot.ResumeSessionId);
        }
        return script;
    }
    public static ProcessStartInfo StartInfo(Slot slot, StateStore store, PendingRecovery pending, string? terminalPath = null)
    {
        var start = new ProcessStartInfo { UseShellExecute = true, WorkingDirectory = slot.ProjectDirectory };
        string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        string wt = terminalPath ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Microsoft", "WindowsApps", "wt.exe");
        if (File.Exists(wt))
        {
            start.FileName = wt;
            foreach (var argument in new[] { "-w", "new", "new-tab", "--title", "CM-RESTORE-" + pending.Token, shell }) start.ArgumentList.Add(argument);
        }
        else start.FileName = shell;
        foreach (string argument in new[] { "-NoLogo", "-NoProfile", "-NoExit", "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(Script(slot, store, pending))) }) start.ArgumentList.Add(argument);
        return start;
    }
    public static WindowIdentity? ExistingMatch(Slot slot, IEnumerable<Slot> slots, IReadOnlyList<WindowIdentity> windows)
    {
        if (slot.Window == null) return null;
        string title = slot.Window.Title.Trim();
        if (title.Length < 7 || new[] { "Windows PowerShell", "PowerShell", "Command Prompt", "命令提示符", "Windows Terminal" }.Contains(title, StringComparer.OrdinalIgnoreCase)) return null;
        if (slots.Count(s => s.Occupied && string.Equals(s.Window!.Title, title, StringComparison.Ordinal)) != 1) return null;
        var matches = windows.Where(w => w.Title == title && w.ProcessName.Equals(slot.Window.ProcessName, StringComparison.OrdinalIgnoreCase) && !slots.Any(s => s != slot && Native.Matches(s.Window) && s.Window!.Handle == w.Handle)).ToArray();
        return matches.Length == 1 ? matches[0] : null;
    }
    public static WindowIdentity? PendingMatch(PendingRecovery pending, IReadOnlyList<WindowIdentity> windows)
    {
        if (!Guid.TryParseExact(pending.Token, "N", out _)) return null;
        var matches = windows.Where(w => w.Title.Contains("CM-RESTORE-" + pending.Token, StringComparison.Ordinal) && w.ProcessName.ToLowerInvariant() is "windowsterminal" or "windowsterminalpreview" or "powershell" or "conhost" or "openconsole").ToArray();
        return matches.Length == 1 ? matches[0] : null;
    }
}
