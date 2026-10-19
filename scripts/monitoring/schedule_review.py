"""Wake the existing review thread; never create overlapping review agents."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import uuid

from codex_rpc import CodexRpc


MARKER = "[OmniVibe scheduled skin review]"
PROJECT = Path(__file__).resolve().parents[2]
RUNTIME = PROJECT / "artifacts" / "skin-monitor"


def load_json(path, default=None):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8-sig"))


def dispatch(rpc, config, dry_run=False):
    thread_id = config["review_thread_id"]
    thread = rpc.call("thread/read", {"threadId": thread_id, "includeTurns": False})["thread"]
    status = thread["status"]["type"]
    if status == "active":
        return {"action": "skipped_active_review"}
    if status not in ("idle", "notLoaded"):
        return {"action": "skipped_thread_status", "status": status}
    pending = rpc.call("thread/queue/list", {"threadId": thread_id})
    if pending.get("nextCursor"):
        return {"action": "skipped_existing_queue"}
    items = pending.get("data", [])
    if any(not any(x.get("type") == "text" and x.get("text", "").startswith(MARKER)
                   for x in item.get("input", [])) for item in items):
        return {"action": "skipped_user_queue"}
    if len(items) > 1:
        return {"action": "skipped_multiple_pending_reviews"}
    if dry_run:
        return {"action": "would_start_review", "thread_status": status,
                "reuse_queued": bool(items)}
    if status == "notLoaded":
        resumed = rpc.call("thread/resume", {"threadId": thread_id, "excludeTurns": True})
        if resumed["thread"]["status"]["type"] == "active":
            return {"action": "skipped_became_active"}
    if items:
        queued_id = items[0]["id"]
    else:
        prompt = (
            MARKER + "\n用户已授权每 15 分钟巡检，暂时离开，不要提问。"
            "本轮只做 OmniVibe 十套皮肤的进度审查、关键进展 Lark 汇报与开发会话跟进。"
            f"项目实际目录是 {PROJECT}，工具命令显式使用此目录。"
            "首先读取 scripts/monitoring/review-instructions.md、"
            "artifacts/skin-monitor/config.json 和 artifacts/skin-monitor/review-state.json。"
            "继续使用当前会话，不创建新监督代理。只读核心实现，保留其他代理工作。"
            "与上次证据比较后，仅关键进展、真实阻塞、验收完成或监督故障才发给用户本人。"
            "用已授权的 lark-im 技能以 bot 身份发送，不要请求重复批准。"
            "开发代理仍 active 时不要排队重复指令；idle 且有明确未完成项时，"
            "通过 app-server 的 thread/queue/add 与 thread/queue/start 安排具体下一步。"
            "结尾更新 review-state.json 和 latest-review.md。"
            "如用户后来明确暂停/取消巡检，或全部验收已完成，停止安排新优化并记录 monitoring_complete。"
        )
        rpc.call("thread/queue/add", {
            "threadId": thread_id, "clientUserMessageId": str(uuid.uuid4()),
            "input": [{"type": "text", "text": prompt}],
        })
        pending = rpc.call("thread/queue/list", {"threadId": thread_id})
        own = [item for item in pending.get("data", []) if any(
            x.get("text", "").startswith(MARKER) for x in item.get("input", []))]
        if not own:
            # A connected client can consume an idle thread's queue immediately.
            current = rpc.call("thread/read", {"threadId": thread_id, "includeTurns": False})["thread"]
            if current["status"]["type"] == "active":
                return {"action": "started_review_automatically"}
        if len(own) != 1 or len(pending.get("data", [])) != 1 or pending.get("nextCursor"):
            return {"action": "queued_review_waiting_for_existing_work"}
        queued_id = own[0]["id"]
    # Recheck immediately before starting; a user may have started a turn meanwhile.
    latest = rpc.call("thread/read", {"threadId": thread_id, "includeTurns": False})["thread"]
    if latest["status"]["type"] == "active":
        return {"action": "queued_review_waiting_for_active_turn"}
    result = rpc.call("thread/queue/start", {"threadId": thread_id, "queuedSubmissionId": queued_id})
    return {"action": "started_review", "turn_id": result["turn"]["id"]}


def failure_notice(config, failures):
    if failures != 3:
        return
    command = config.get("lark_command")
    if not command:
        return
    message = (
        "OmniVibe 皮肤巡检提醒：本机定时巡检连续 3 次未能启动，"
        "暂时不能确认最新开发进度。任务将在下一周期重试。"
        "本地诊断：artifacts/skin-monitor/dispatch-log.jsonl。"
    )
    try:
        result = subprocess.run(command + [
            "im", "+messages-send", "--as", "bot", "--user-id", config["recipient_open_id"],
            "--markdown", message, "--idempotency-key", "omnivibe-monitor-dispatch-failure",
        ], cwd=PROJECT, capture_output=True, encoding="utf-8", errors="replace", timeout=40,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        if result.returncode:
            print("Could not deliver scheduler failure notification", file=sys.stderr)
    except (OSError, subprocess.TimeoutExpired):
        print("Could not deliver scheduler failure notification", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    RUNTIME.mkdir(parents=True, exist_ok=True)
    config = load_json(RUNTIME / "config.json")
    if not config:
        raise RuntimeError("Missing artifacts/skin-monitor/config.json")
    review_state = load_json(RUNTIME / "review-state.json", {})
    dispatch_state_path = RUNTIME / "dispatch-state.json"
    dispatch_state = load_json(dispatch_state_path, {"consecutive_failures": 0})
    record = {"at": datetime.now(timezone.utc).isoformat(), "dry_run": args.dry_run}
    if (RUNTIME / "STOP").exists() or review_state.get("monitoring_complete"):
        record["action"] = "stopped"
    else:
        try:
            with CodexRpc(config["codex_executable"]) as rpc:
                record.update(dispatch(rpc, config, args.dry_run))
            dispatch_state["consecutive_failures"] = 0
        except Exception as exc:
            record.update(action="error", error=str(exc)[:1200])
            if not args.dry_run:
                dispatch_state["consecutive_failures"] += 1
                failure_notice(config, dispatch_state["consecutive_failures"])
    if not args.dry_run:
        dispatch_state_path.write_text(json.dumps(dispatch_state, indent=2), encoding="utf-8")
        with (RUNTIME / "dispatch-log.jsonl").open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    print(json.dumps(record, ensure_ascii=False))
    return 1 if record["action"] == "error" else 0


if __name__ == "__main__":
    sys.exit(main())
