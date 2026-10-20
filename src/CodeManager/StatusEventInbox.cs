using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace CodeManager;

internal sealed record PendingStatusEvent(string Path, StatusEvent Status);

/// <summary>Disk work only. Never reads slots, calls WPF, or acknowledges unapplied events.</summary>
internal sealed class StatusEventInbox
{
    internal const int BatchSize = 24;
    private readonly StateStore _store;
    private DateTime _nextCleanup;
    internal StatusEventInbox(StateStore store) => _store = store;
    internal Task<IReadOnlyList<PendingStatusEvent>> ReadAsync(CancellationToken cancellation = default) => Task.Run<IReadOnlyList<PendingStatusEvent>>(() =>
    {
        // Keep only the oldest batch in memory, even with a large producer backlog.
        var oldest = new PriorityQueue<string, long>();
        foreach (string path in Directory.EnumerateFiles(_store.EventsDirectory, "*.json"))
        {
            cancellation.ThrowIfCancellationRequested();
            try { oldest.Enqueue(path, -File.GetLastWriteTimeUtc(path).Ticks); if (oldest.Count > BatchSize) oldest.Dequeue(); }
            catch (IOException) { }
        }
        var pending = new List<PendingStatusEvent>(BatchSize);
        foreach (string path in oldest.UnorderedItems.Select(x => x.Element))
        {
            cancellation.ThrowIfCancellationRequested();
            try
            {
                using var stream = File.OpenRead(path);
                if (stream.Length > 32768) { stream.Dispose(); Reject(path); continue; }
                var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
                var status = JsonSerializer.Deserialize<StatusEvent>(bytes, StateStore.Json);
                if (status == null || string.IsNullOrWhiteSpace(status.TaskId) || !Enum.IsDefined(status.State) || status.At > DateTimeOffset.UtcNow.AddMinutes(1))
                { stream.Dispose(); Reject(path); continue; }
                status.Message ??= ""; status.Provider ??= ""; status.SessionId ??= ""; status.ProjectDirectory ??= "";
                status.SuggestedName ??= ""; status.EventName ??= "";
                pending.Add(new(path, status));
            }
            catch (JsonException) { Reject(path); }
            catch (IOException) { /* Retry locked or partially published files on a later poll. */ }
            catch (UnauthorizedAccessException) { /* One inaccessible file must not starve other tasks. */ }
        }
        if (DateTime.UtcNow >= _nextCleanup)
        {
            _nextCleanup = DateTime.UtcNow.AddHours(1);
            CleanupRejected(cancellation);
        }
        return pending.OrderBy(p => p.Status.At).ToArray();
    }, cancellation);
    internal Task AcknowledgeAsync(IReadOnlyList<PendingStatusEvent> batch, CancellationToken cancellation = default) => Task.Run(() =>
    {
        foreach (var item in batch)
        {
            cancellation.ThrowIfCancellationRequested();
            try { File.Delete(item.Path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }, cancellation);
    private static void Reject(string path)
    {
        try { File.Move(path, path + ".rejected", true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
    private void CleanupRejected(CancellationToken cancellation)
    {
        var newest = new PriorityQueue<string, long>();
        foreach (string path in Directory.EnumerateFiles(_store.EventsDirectory, "*.rejected"))
        {
            cancellation.ThrowIfCancellationRequested();
            try
            {
                var modified = File.GetLastWriteTimeUtc(path);
                if (modified < DateTime.UtcNow.AddDays(-7)) File.Delete(path);
                else { newest.Enqueue(path, modified.Ticks); if (newest.Count > 128) File.Delete(newest.Dequeue()); }
            }
            catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
