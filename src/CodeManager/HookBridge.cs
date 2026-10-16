using System;
using System.Linq;
using System.Text.Json;

namespace CodeManager;

public static class HookBridge
{
    public static StatusEvent? Parse(string provider, string taskId, string json, DateTimeOffset? at = null)
    {
        if (provider is not ("claude" or "codex") || !Guid.TryParse(taskId, out _) || json.Length > 1_048_576) return null;
        json = json.TrimStart('\uFEFF');
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        string Text(string name) => root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
        if (Text("agent_id") != "" || Text("subagent_id") != "") return null;
        string name = Text("hook_event_name");
        AgentState state;
        string message;
        switch (name)
        {
            case "SessionStart":
                if (Text("source") == "compact") return null;
                state = AgentState.Unknown; message = "会话已连接，等待提交任务"; break;
            case "UserPromptSubmit": case "PostToolUse": case "ElicitationResult":
                state = AgentState.Running; message = "AI 正在执行"; break;
            case "PermissionRequest": case "Elicitation":
                state = AgentState.Waiting; message = "需要你的确认或输入"; break;
            case "Notification":
                if (Text("notification_type") is not ("permission_prompt" or "elicitation_dialog")) return null;
                state = AgentState.Waiting; message = "需要你的确认或输入"; break;
            case "Stop": state = AgentState.Ready; message = "本轮回复已结束，请查看结果"; break;
            case "StopFailure": state = AgentState.Error; message = "本轮执行发生错误，请查看终端"; break;
            case "Interrupt": state = AgentState.Unknown; message = "本轮已中断"; break;
            case "SessionEnd": state = AgentState.Unknown; message = "CLI 会话已结束"; break;
            default: return null;
        }
        string suggested = Text("session_title");
        if (suggested == "" && name == "UserPromptSubmit") suggested = Text("prompt").Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
        if (suggested.Length > 60) suggested = suggested[..60] + "…";
        return new StatusEvent
        {
            TaskId = taskId, State = state, Message = message, Provider = provider, SessionId = Text("session_id"),
            ProjectDirectory = Text("cwd"), SuggestedName = suggested.Trim(), At = at ?? DateTimeOffset.UtcNow,
            SessionEnded = name == "SessionEnd", EventName = name
        };
    }
}
