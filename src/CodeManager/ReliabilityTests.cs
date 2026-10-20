using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

namespace CodeManager;

/// <summary>Isolated fixtures: no Manager, global input hooks, user settings or audio.</summary>
public static class ReliabilityTests
{
    public static List<SelfTests.Result> Run()
    {
        var results = new List<SelfTests.Result>();
        string root = Path.Combine(Path.GetTempPath(), "OmniVibe-reliability-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
        void Test(string name, Action action) {
            try { action(); results.Add(new(name, true, "OK")); }
            catch (Exception ex) { results.Add(new(name, false, ex.ToString())); }
        }
        try
        {
            Test("Configuration: nested null fields repaired without losing task identity or original bytes", () => {
                var store = new StateStore(Path.Combine(root, "nested")); var state = new AppState();
                var task = state.Slots[0]; task.Name = "Preserved task"; task.Window = new() { Title = "Original title", ProcessName = "fixture", Handle = 42 };
                state.RecentTasks.Add(new() { Task = new() { Number = 3, Window = new() { Title = "Recent" } } });
                state.Layout.Add(new() { SlotId = task.Id, Window = task.Window });
                state.Popup = new() { SlotId = task.Id, Window = task.Window };
                var json = JsonSerializer.SerializeToNode(state, StateStore.Json)!;
                foreach (string field in new[] { "Name", "ProjectDirectory", "SessionId", "AgentProvider", "Message", "StateSource" }) json["Slots"]![0]![field] = null;
                json["Slots"]![0]!["Window"]!["Title"] = null; json["Slots"]![0]!["Window"]!["ProcessName"] = null;
                json["RecentTasks"]![0]!["Task"]!["Window"]!["Title"] = null;
                json["Layout"]!.AsArray().Add((JsonNode?)null); json["Popup"]!["Window"]!["Title"] = null;
                string original = json.ToJsonString(); File.WriteAllText(store.StateFile, original);
                var loaded = store.Load(); var slot = loaded.Slots[0];
                Check(slot.Id == task.Id && slot.Window?.Handle == 42 && slot.Window.Title == "" && slot.Window.ProcessName == "", "Task identity lost or nested null retained");
                Check(slot.Name == "" && slot.ProjectDirectory == "" && slot.SessionId == "" && slot.Message == "", "Nullable text was not normalized");
                Check(loaded.Layout.Count == 1 && loaded.Popup?.Window.Title == "" && loaded.RecentTasks[0].Task.Window?.Title == "", "Nested recovery structures were not normalized");
                Check(RecoveryLaunch.ExistingMatch(slot, loaded.Slots, Array.Empty<WindowIdentity>()) == null, "Empty title matched a window");
                string backup = Directory.GetFiles(store.Root, "tasks.json.recovery-*").Single();
                Check(File.ReadAllText(backup) == original && File.ReadAllText(store.StateFile) == original && store.LoadWarning != null, "Original configuration was not preserved");
                store.Save(loaded); store.Load(); Check(store.LoadWarning == null, "Successful reload retained a stale warning");
            });
            Test("Configuration: invalid slot structure falls back with byte-preserving backup", () => {
                var store = new StateStore(Path.Combine(root, "invalid")); var state = new AppState(); state.Slots[1].Id = state.Slots[0].Id;
                store.Save(state); byte[] original = File.ReadAllBytes(store.StateFile); var loaded = store.Load();
                Check(loaded.Slots.Select(s => s.Id).Distinct().Count() == 9 && store.LoadWarning != null, "Invalid IDs accepted");
                Check(File.ReadAllBytes(Directory.GetFiles(store.Root, "tasks.json.recovery-*").Single()).SequenceEqual(original), "Backup changed original bytes");
                var raw = new Slot { Window = new() { Title = null!, ProcessName = null! } };
                Check(RecoveryLaunch.ExistingMatch(raw, new[] { raw }, Array.Empty<WindowIdentity>()) == null, "Recovery bypassed null safety");
            });
            Test("Status: age signals uncertainty; long jobs, terminal states and manual marks retain semantics", () => {
                var now = DateTimeOffset.UtcNow;
                var slot = new Slot { Window = new(), Connected = true, IntegrationConnected = true, State = AgentState.Running, UpdatedAt = now.AddMinutes(-11) };
                Check(slot.StatusMayBeStaleAt(now) && slot.StateLabel.Contains("状态可能过期") && slot.Tooltip.Contains("最近更新"), "Missing age indication");
                Check(slot.State == AgentState.Running && slot.IntegrationConnected, "Age mutated task state or assumed a disconnected agent");
                slot.State = AgentState.Waiting; Check(slot.StatusMayBeStaleAt(now), "Old waiting state was not marked uncertain");
                slot.UpdatedAt = now.AddMinutes(-9); Check(!slot.StatusMayBeStaleAt(now), "Recent event was marked stale");
                slot.UpdatedAt = now; Check(!slot.StatusMayBeStaleAt(now), "New event did not clear uncertainty");
                slot.UpdatedAt = now.AddHours(-3);
                foreach (var state in new[] { AgentState.Ready, AgentState.Error, AgentState.Unknown }) { slot.State = state; Check(!slot.StatusMayBeStaleAt(now), "Completed/error/unknown result expired"); }
                slot.State = AgentState.Running; slot.StateSource = "手动标记";
                Check(!slot.StatusMayBeStaleAt(now), "Manual state treated as hook liveness");
                slot.IntegrationConnected = false;
                slot.StateSource = "外部事件"; Check(slot.StatusMayBeStaleAt(now), "External event age was ignored");
                slot.Connected = false; Check(!slot.StatusMayBeStaleAt(now) && slot.StateLabel.Contains("已断开"), "Window disconnection was obscured");
            });
            Test("Inbox: bounded oldest-first backlog, event ordering, retention until acknowledgement", () => {
                var store = new StateStore(Path.Combine(root, "backlog")); var inbox = new StatusEventInbox(store);
                var start = DateTimeOffset.UtcNow.AddMinutes(-2);
                for (int i = 0; i < 1000; i++) {
                    string path = Path.Combine(store.EventsDirectory, i.ToString("D4") + ".json");
                    File.WriteAllText(path, JsonSerializer.Serialize(new StatusEvent { TaskId = "fixture", At = start.AddMilliseconds(999 - i) }, StateStore.Json));
                    File.SetLastWriteTimeUtc(path, start.UtcDateTime.AddMilliseconds(i));
                }
                var batch = inbox.ReadAsync().GetAwaiter().GetResult();
                Check(batch.Count == StatusEventInbox.BatchSize && batch.All(p => int.Parse(Path.GetFileNameWithoutExtension(p.Path)) < 24), "Batch was not bounded to oldest files");
                Check(batch.Select(p => p.Status.At).SequenceEqual(batch.Select(p => p.Status.At).OrderBy(t => t)), "Events not ordered by event time");
                Check(Directory.GetFiles(store.EventsDirectory, "*.json").Length == 1000, "Read acknowledged unapplied events");
                var retry = inbox.ReadAsync().GetAwaiter().GetResult();
                Check(retry.Select(x => x.Path).OrderBy(x => x).SequenceEqual(batch.Select(x => x.Path).OrderBy(x => x)), "Unacknowledged batch was lost");
                inbox.AcknowledgeAsync(batch).GetAwaiter().GetResult();
                Check(Directory.GetFiles(store.EventsDirectory, "*.json").Length == 976, "Acknowledgement deleted unrelated events");
            });
            Test("Inbox: rejects malformed, oversized and future events; tolerates locks and nullable text", () => {
                var store = new StateStore(Path.Combine(root, "validation")); var inbox = new StatusEventInbox(store);
                File.WriteAllText(Path.Combine(store.EventsDirectory, "broken.json"), "{broken");
                File.WriteAllText(Path.Combine(store.EventsDirectory, "oversized.json"), new string(' ', 32769));
                store.Send(new() { TaskId = "future", At = DateTimeOffset.UtcNow.AddDays(1) });
                store.Send(new() { TaskId = "valid", Message = null!, Provider = null!, SessionId = null! });
                string lockedPath = Path.Combine(store.EventsDirectory, "locked.json");
                File.WriteAllText(lockedPath, JsonSerializer.Serialize(new StatusEvent { TaskId = "locked" }, StateStore.Json));
                using (var locked = new FileStream(lockedPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None)) {
                    var batch = inbox.ReadAsync().GetAwaiter().GetResult();
                    Check(batch.Count == 1 && batch[0].Status.TaskId == "valid" && batch[0].Status.Message == "" && batch[0].Status.Provider == "", "Bad file blocked valid event or null escaped boundary");
                    Check(Directory.GetFiles(store.EventsDirectory, "*.rejected").Length == 3 && File.Exists(lockedPath), "Invalid events not quarantined or locked event lost");
                }
                Check(inbox.ReadAsync().GetAwaiter().GetResult().Count == 2, "Previously locked file was not retried");
                using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
                try { inbox.ReadAsync(cancelled.Token).GetAwaiter().GetResult(); throw new Exception("Cancelled read completed"); } catch (OperationCanceledException) { }
            });
            Test("Portraits: background warmup yields frozen bounded cached images and supports cancellation", () => {
                var slots = new AppState().Slots; int callbacks = 0;
                SelfTests.WaitForTask(EquipmentCatalog.PrewarmAsync(slots, Skin.Hextech, () => Interlocked.Increment(ref callbacks)));
                Check(callbacks == 9, "Not all portraits warmed");
                foreach (var slot in slots) {
                    var image = EquipmentCatalog.Image(slot, Skin.Hextech, true);
                    Check(image != null && image.IsFrozen && Math.Max(image.PixelWidth, image.PixelHeight) <= 512, "Warm image missing, thread-affine or oversized");
                }
                // Rotate beyond the LRU budget, then refill the original theme.
                SelfTests.WaitForTask(Task.WhenAll(SkinCatalog.All.Select(s => EquipmentCatalog.PrewarmAsync(slots, s.Id))));
                SelfTests.WaitForTask(EquipmentCatalog.PrewarmAsync(slots, Skin.Hextech));
                Check(slots.All(s => EquipmentCatalog.Image(s, Skin.Hextech, true) is { IsFrozen: true }), "Evicted theme could not be refilled");
                using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
                try { EquipmentCatalog.PrewarmAsync(slots, Skin.Protocol, cancellation: cancelled.Token).GetAwaiter().GetResult(); throw new Exception("Cancelled warmup completed"); } catch (OperationCanceledException) { }
            });
        }
        finally { Directory.Delete(root, true); }
        return results;
    }
}
