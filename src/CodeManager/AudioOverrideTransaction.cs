using System;
using System.Collections.Generic;
using System.IO;

namespace CodeManager;

internal sealed record AudioOverrideChange(Skin Skin, AudioCue Cue, string? Identity, string? Source);

/// <summary>Stage every file before changing any override; restore earlier writes on failure.</summary>
internal static class AudioOverrideTransaction
{
    private sealed record Staged(AudioOverrideChange Change, string Target, string? Backup, string? Input);
    internal static bool TryApply(IReadOnlyList<AudioOverrideChange> changes, out string error)
    {
        var staged = new List<Staged>(); var applied = new List<Staged>(); var temporary = new List<string>();
        var retainedBackups = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        error = "";
        try
        {
            foreach (var change in changes)
            {
                string directory = GameAudio.OverrideDirectory(change.Skin, change.Identity);
                Directory.CreateDirectory(directory);
                string target = Path.Combine(directory, change.Cue.ToString().ToLowerInvariant() + ".wav");
                string prefix = Path.Combine(directory, ".omnivibe-draft-" + Guid.NewGuid().ToString("N"));
                string? backup = null, input = null;
                if (File.Exists(target)) { backup = prefix + ".backup"; temporary.Add(backup); File.Copy(target, backup); File.SetAttributes(backup, FileAttributes.Normal); }
                if (change.Source != null)
                {
                    if (!GameAudio.ValidateWave(change.Source, out string invalid)) throw new InvalidDataException(invalid);
                    input = prefix + ".wav"; temporary.Add(input); File.Copy(change.Source, input);
                    File.SetAttributes(input, FileAttributes.Normal);
                    if (!GameAudio.ValidateWave(input, out invalid)) throw new InvalidDataException(invalid);
                }
                staged.Add(new(change, target, backup, input));
            }
            GameAudio.Stop();
            foreach (var item in staged)
            {
                var change = item.Change;
                if (item.Input == null) GameAudio.RemoveOverride(change.Skin, change.Cue, change.Identity);
                else GameAudio.ImportOverride(change.Skin, change.Cue, item.Input, change.Identity);
                applied.Add(item);
            }
            return true;
        }
        catch (Exception exception) when (exception is IOException or InvalidDataException or UnauthorizedAccessException or ArgumentException or InvalidOperationException)
        {
            string rollbackError = "";
            for (int i = applied.Count - 1; i >= 0; i--)
            {
                var item = applied[i];
                try
                {
                    GameAudio.RemoveOverride(item.Change.Skin, item.Change.Cue, item.Change.Identity);
                    if (item.Backup != null) File.Copy(item.Backup, item.Target, true);
                }
                catch (Exception restore) when (restore is IOException or UnauthorizedAccessException)
                {
                    if (item.Backup != null) retainedBackups.Add(item.Backup);
                    rollbackError += "\n恢复失败：" + item.Target + " · " + restore.Message + (item.Backup == null ? "" : "\n原文件备份保留在：" + item.Backup);
                }
            }
            error = (rollbackError == "" ? "音频保存失败，已取消本轮更改：" : "音频保存未完成，请查看保留的备份：") + exception.Message + rollbackError;
            return false;
        }
        finally
        {
            foreach (string path in temporary)
                try { if (!retainedBackups.Contains(path) && File.Exists(path)) File.Delete(path); } catch (Exception cleanup) when (cleanup is IOException or UnauthorizedAccessException) { }
        }
    }
}
