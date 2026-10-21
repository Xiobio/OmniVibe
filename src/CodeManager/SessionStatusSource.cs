using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace CodeManager;

public sealed record AgentSession(string Id, string Provider, string File, string Project, string Title, DateTimeOffset Modified)
{
    public string Label => (Provider == "codex" ? "Codex" : "Claude Code") + " · " + Title;
    public string Detail => Project + " · " + Modified.ToLocalTime().ToString("MM-dd HH:mm") + " · " + Id[..Math.Min(8, Id.Length)];
}
internal sealed record SessionTarget(string TaskId, long Handle, string Title, string SessionId, string File);
internal sealed record SessionUpdate(SessionTarget Target, AgentSession Session, StatusEvent? Status, bool Initial);

/// <summary>Read-only, bounded local transcript observation. Never launches an agent,
/// reads a terminal screen, stores conversation text, or infers completion from silence.</summary>
public sealed class SessionStatusSource
{
    private readonly string _codex, _claude;
    private IReadOnlyList<AgentSession> _sessions = Array.Empty<AgentSession>();
    private DateTime _scanAfter;
    private readonly Dictionary<string, Cursor> _cursors = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentQueue<string> _resets = new();
    private readonly ConcurrentDictionary<string,Metadata> _metadata = new(StringComparer.OrdinalIgnoreCase);
    private sealed record Metadata(long Length,DateTime Written,DateTime Created,AgentSession? Session);
    internal void Reset(string taskId) => _resets.Enqueue(taskId);
    private sealed class Cursor { internal long Offset; internal byte[] Pending = Array.Empty<byte>(); internal bool Started; internal AgentSession? Session; internal DateTime Written,Created; }
    public SessionStatusSource(string? codexRoot = null, string? claudeRoot = null)
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        _codex = codexRoot ?? Path.Combine(Environment.GetEnvironmentVariable("CODEX_HOME") ?? Path.Combine(home, ".codex"), "sessions");
        _claude = claudeRoot ?? Path.Combine(Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR") ?? Path.Combine(home, ".claude"), "projects");
    }
    internal static string String(JsonElement e, string key) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";
    private static bool True(JsonElement e, string key) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.True;
    private static bool LocalCommand(JsonElement e)
    {
        string text = e.TryGetProperty("message", out var message) ? String(message, "content").TrimStart() : "";
        return text.StartsWith("<command-name>", StringComparison.Ordinal) || text.StartsWith("<command-message>", StringComparison.Ordinal) || text.StartsWith("<local-command-", StringComparison.Ordinal);
    }
    private bool Allowed(string file) => new[] { _codex, _claude }.Any(root => Path.GetFullPath(file).StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase));
    private static IEnumerable<string> ReadPart(string file, bool tail, int limit)
    {
        using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        long start = tail ? Math.Max(0, stream.Length - limit) : 0; stream.Position = start;
        byte[] buffer = new byte[Math.Min(limit, (int)Math.Min(stream.Length, int.MaxValue))]; int count = stream.Read(buffer, 0, buffer.Length);
        string text = Encoding.UTF8.GetString(buffer, 0, count); var lines = text.Split('\n');
        return lines.Skip(start > 0 ? 1 : 0).Take(Math.Max(0, lines.Length - (start > 0 ? 2 : 1))).ToArray();
    }
    private AgentSession? Inspect(string file, string provider, IReadOnlyDictionary<string, string> titles)
    {
        var info=new FileInfo(file);string key=provider+"|"+info.FullName;
        if(_metadata.TryGetValue(key,out var cached) && cached.Length==info.Length && cached.Written==info.LastWriteTimeUtc && cached.Created==info.CreationTimeUtc) {
            var value=cached.Session;
            return value!=null && titles.TryGetValue(value.Id,out var renamed)?value with{Title=renamed}:value;
        }
        string id = "", cwd = "", title = "";
        var lines=ReadPart(file,false,65536);
        if(info.Length>65536)lines=lines.Concat(ReadPart(file,true,65536));
        foreach (string line in lines)
        {
            try {
                using var json = JsonDocument.Parse(line); var e = json.RootElement;
                if (provider == "codex" && String(e, "type") == "session_meta" && e.TryGetProperty("payload", out var p)) {
                    if (p.TryGetProperty("source", out var source) && source.ValueKind == JsonValueKind.Object) return null;
                    id = String(p,"id"); cwd = String(p,"cwd"); title = String(p,"title");
                } else if (provider == "claude") {
                    if (True(e,"isSidechain")) return null;
                    if (id == "") id = String(e,"sessionId");
                    if (cwd == "") cwd = String(e,"cwd");
                    if (String(e,"type") == "ai-title") title = String(e,"aiTitle");
                }
            } catch (JsonException) { }
        }
        if (!Guid.TryParse(id, out _)) return null;
        if (title == "") title = Path.GetFileName(cwd.TrimEnd('\\','/')) + " · " + id[..8];
        var session=new AgentSession(id,provider,file,cwd,title,info.LastWriteTimeUtc);
        if(_metadata.Count>=128)foreach(string old in _metadata.Keys.Take(32))_metadata.TryRemove(old,out _);
        _metadata[key]=new(info.Length,info.LastWriteTimeUtc,info.CreationTimeUtc,session);
        return titles.TryGetValue(id,out var indexed)?session with{Title=indexed}:session;
    }
    public Task<IReadOnlyList<AgentSession>> DiscoverAsync() => Task.Run(Discover);
    private IReadOnlyList<AgentSession> Discover()
    {
        var files = new List<(string File, string Provider)>(); var titles = new Dictionary<string,string>();
        try {
            string index = Path.Combine(Path.GetDirectoryName(_codex)!, "session_index.jsonl");
            if (File.Exists(index)) foreach (string line in ReadPart(index,true,524288)) try { using var d = JsonDocument.Parse(line); string id = String(d.RootElement,"id"), name = String(d.RootElement,"thread_name"); if (id != "" && name != "") titles[id] = name; } catch (JsonException) { }
            for (int days = 0; days < 14; days++) {
                string day = Path.Combine(_codex, DateTime.UtcNow.AddDays(-days).ToString("yyyy/MM/dd"));
                if (Directory.Exists(day)) files.AddRange(Directory.EnumerateFiles(day,"*.jsonl").Take(300).Select(f => (f,"codex")));
            }
            if (Directory.Exists(_claude)) foreach (var project in Directory.EnumerateDirectories(_claude).Take(128)) files.AddRange(Directory.EnumerateFiles(project,"*.jsonl").Take(256).Select(f => (f,"claude")));
        } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        var sessions = new List<AgentSession>();
        foreach (var file in files.OrderByDescending(f => File.GetLastWriteTimeUtc(f.File)).Take(96)) try {
            var session = Inspect(file.File,file.Provider,titles); if (session != null) sessions.Add(session);
        } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        return sessions.GroupBy(s => (s.Provider,s.Id)).Select(g => g.First()).ToArray();
    }
    internal static bool MatchesTitle(string window, string title)
    {
        window=TerminalStatusSignals.CleanTitle(window);
        return title.Length >= 4 && (window.Trim().Equals(title.Trim(),StringComparison.OrdinalIgnoreCase) || window.StartsWith(title + " | ",StringComparison.OrdinalIgnoreCase));
    }
    internal Task<IReadOnlyList<SessionUpdate>> PollAsync(IReadOnlyList<SessionTarget> targets) => Task.Run<IReadOnlyList<SessionUpdate>>(() => {
        while(_resets.TryDequeue(out string? reset)) foreach(string key in _cursors.Keys.Where(k=>k.StartsWith(reset+"|",StringComparison.Ordinal)).ToArray()) _cursors.Remove(key);
        // Bound sessions already have an exact file and ID. A global discovery
        // scan is only needed to resolve an unbound/missing session.
        if (targets.Any(t=>t.File=="" || !Allowed(t.File) || !File.Exists(t.File)) && DateTime.UtcNow >= _scanAfter) { _sessions = Discover(); _scanAfter = DateTime.UtcNow.AddSeconds(8); }
        var updates = new List<SessionUpdate>();
        foreach (var target in targets) try {
            AgentSession? session = null;
            if (target.File != "" && Allowed(target.File) && File.Exists(target.File)) {
                var info=new FileInfo(target.File);
                _cursors.TryGetValue(target.TaskId+"|"+target.File,out var previous);
                // Appended records do not invalidate the already verified session
                // header. File replacement/truncation or same-size rewrite does.
                bool retained=previous is {Started:true,Session:not null} && previous.Created==info.CreationTimeUtc && info.Length>=previous.Offset && (info.Length>previous.Offset || previous.Written==info.LastWriteTimeUtc);
                session=retained?previous!.Session:Inspect(target.File,target.File.StartsWith(_codex,StringComparison.OrdinalIgnoreCase)?"codex":"claude",new Dictionary<string,string>());
            }
            if (session == null && target.SessionId != "") session = _sessions.SingleOrDefault(s => s.Id == target.SessionId);
            if (session == null && target.SessionId == "" && target.File == "") {
                var matches = _sessions.Where(s => MatchesTitle(target.Title,s.Title)).ToArray();
                if (matches.Length == 1 && targets.Count(t => MatchesTitle(t.Title,matches[0].Title)) == 1 && !targets.Any(t => t.TaskId != target.TaskId && (t.SessionId == matches[0].Id || t.File.Equals(matches[0].File,StringComparison.OrdinalIgnoreCase)))) session = matches[0];
            }
            if (session == null || (target.SessionId != "" && target.SessionId != session.Id)) continue;
            string key = target.TaskId + "|" + session.File;
            if (!_cursors.TryGetValue(key,out var cursor)) _cursors[key] = cursor = new();
            var stamp=new FileInfo(session.File);
            if(cursor.Started && cursor.Created==stamp.CreationTimeUtc && cursor.Offset==stamp.Length && cursor.Written==stamp.LastWriteTimeUtc)continue;
            if(cursor.Started && (cursor.Created!=stamp.CreationTimeUtc || cursor.Offset==stamp.Length && cursor.Written!=stamp.LastWriteTimeUtc)) { cursor.Offset=0;cursor.Pending=Array.Empty<byte>();cursor.Started=false; }
            bool initial = !cursor.Started;
            StatusEvent? latest = null;
            using var stream = new FileStream(session.File,FileMode.Open,FileAccess.Read,FileShare.ReadWrite | FileShare.Delete);
            if (cursor.Offset > stream.Length) { cursor.Offset = 0; cursor.Pending = Array.Empty<byte>(); cursor.Started = false; initial = true; }
            if (!cursor.Started && stream.Length > 131072) { cursor.Offset = stream.Length - 131072; stream.Position = cursor.Offset; while (stream.Position < stream.Length && stream.ReadByte() != '\n') {} cursor.Offset = stream.Position; }
            stream.Position = cursor.Offset; var bytes = new byte[(int)Math.Min(131072,stream.Length-cursor.Offset)]; int count = stream.Read(bytes,0,bytes.Length); cursor.Offset += count;
            var data = new byte[cursor.Pending.Length+count]; cursor.Pending.CopyTo(data,0); Array.Copy(bytes,0,data,cursor.Pending.Length,count);
            int from = 0;
            for (int i = 0; i < data.Length; i++) if (data[i] == '\n') {
                string line = Encoding.UTF8.GetString(data,from,i-from); from = i+1;
                var status = Parse(session.Provider,target.TaskId,session.Id,line);
                if (status != null && (latest == null || status.At >= latest.At)) latest = status;
            }
            cursor.Pending = data.Length-from <= 262144 ? data[from..] : Array.Empty<byte>(); cursor.Started = true;
            stamp.Refresh();cursor.Session=session;cursor.Created=stamp.CreationTimeUtc;cursor.Written=stamp.LastWriteTimeUtc;
            if (initial || latest != null) updates.Add(new(target,session,latest,initial));
        } catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException) { }
        var active = targets.Select(t => t.TaskId).ToHashSet(); foreach (string key in _cursors.Keys.Where(k => !active.Contains(k.Split('|')[0])).ToArray()) _cursors.Remove(key);
        foreach(string key in _cursors.Keys.Take(Math.Max(0,_cursors.Count-36)).ToArray())_cursors.Remove(key);
        return updates;
    });
    internal static StatusEvent? Parse(string provider, string taskId, string sessionId, string line)
    {
        try {
            using var doc = JsonDocument.Parse(line); var e = doc.RootElement;
            if (True(e,"isSidechain") || !DateTimeOffset.TryParse(String(e,"timestamp"),out var at)) return null;
            AgentState? state = null; string type = String(e,"type"), eventName = "";
            if (provider == "codex" && e.TryGetProperty("payload",out var p)) {
                eventName = String(p,"type");
                if (type == "event_msg") state = eventName switch { "task_started" => AgentState.Running, "task_complete" or "turn_complete" => AgentState.Ready, "task_failed" => AgentState.Error, "turn_aborted" => AgentState.Unknown, _ => null };
                if (type == "response_item" && eventName is "function_call_output" or "custom_tool_call_output") state = AgentState.Running;
            } else if (provider == "claude") {
                if (String(e,"sessionId") is string id && id != "" && id != sessionId) return null;
                // Local slash commands (/model, /compact…) and their output are
                // recorded as user entries but start no model turn; a model-backed
                // command still shows Running from its first tool use below.
                if (type == "user" && !True(e,"isMeta") && !LocalCommand(e)) state = AgentState.Running;
                if (type == "system" && String(e,"subtype") == "turn_duration") state = AgentState.Ready;
                if (type == "assistant" && e.TryGetProperty("message",out var message)) {
                    if (True(e,"isApiErrorMessage")) state = AgentState.Error;
                    else if (String(message,"stop_reason") is "end_turn" or "max_tokens") state = AgentState.Ready;
                    else if (message.TryGetProperty("content",out var blocks) && blocks.ValueKind == JsonValueKind.Array && blocks.EnumerateArray().Any(b => String(b,"type") == "tool_use" && String(b,"name") == "AskUserQuestion")) state = AgentState.Waiting;
                    else if (String(message,"stop_reason") == "tool_use") state = AgentState.Running;
                }
            }
            if (state == null) return null;
            return new() { TaskId=taskId,Provider=provider,SessionId=sessionId,State=state.Value,At=at,EventName="Transcript",Message=state switch { AgentState.Running=>"AI 正在执行",AgentState.Ready=>"本轮回复已结束，请查看结果",AgentState.Waiting=>"需要你的输入",AgentState.Error=>"本轮执行发生错误，请查看终端",_=>"本轮已中断" } };
        } catch (JsonException) { return null; }
    }
}
