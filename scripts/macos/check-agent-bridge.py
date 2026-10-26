#!/usr/bin/env python3
"""Exercise the built observer and launcher against fake local CLIs only."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid


def main():
    binary = Path(sys.argv[1]).resolve()
    checks = []
    with tempfile.TemporaryDirectory(prefix="OmniVibe bridge ' 中文 ") as folder:
        root = Path(folder)
        tasks = [str(uuid.uuid4()).upper() for _ in range(9)]
        slots = [{"id": task, "number": index + 1, "name": "", "agentState": "unknown",
                  "unread": False, "message": ""} for index, task in enumerate(tasks)]
        slots[0]["window"] = {"id": str(uuid.uuid4()), "processID": 12345,
                              "applicationName": "Isolated fixture", "title": "Bridge test"}
        (root / "workspace.json").write_text(json.dumps({"schemaVersion": 1, "slots": slots}))
        fake_bin = root / "fake tools"
        fake_bin.mkdir()
        for provider in ("codex", "claude"):
            (fake_bin / provider).write_text(
                "#!" + sys.executable + "\nimport json, os, sys\n"
                "if sys.argv[1:2] == ['app-server']:\n"
                "    for line in sys.stdin:\n"
                "        request = json.loads(line)\n"
                "        if 'id' not in request: continue\n"
                "        result = {'config': {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'existing-user-hook'}]}]}}} if request['method'] == 'config/read' else {}\n"
                "        print(json.dumps({'id': request['id'], 'result': result}), flush=True)\n"
                "    sys.exit(0)\n"
                "print(json.dumps({'arguments': sys.argv[1:], 'cwd': os.getcwd()}))\n")
            (fake_bin / provider).chmod(0o755)
        env = dict(os.environ, PATH=str(fake_bin) + os.pathsep + os.environ.get("PATH", ""))
        base = ["--task", tasks[0], "--root", str(root)]

        def run(args, payload=None, command=None):
            invocation = command or [str(binary)] + args
            result = subprocess.run(invocation, input=payload, text=True, env=env,
                                    capture_output=True, timeout=10)
            assert result.returncode == 0, result.stderr
            return result

        for provider in ("codex", "claude"):
            options = ["--provider", provider] + base + ["--cwd", str(root), "--resume", "thread_123-abc"]
            tail = ["--", "--model", "fixture-model", "literal $() `text` ' 中文"]
            plan = json.loads(run(["plan"] + options + tail).stdout)
            actual = json.loads(run(["track"] + options + tail).stdout)
            assert actual["arguments"] == plan["arguments"][1:]
            assert Path(actual["cwd"]).resolve() == root.resolve()
            checks.append(provider + " exact argv, cwd, resume and literal forwarding")
            if provider == "codex":
                stop = next(item for item in plan["arguments"] if item.startswith("hooks.Stop="))
                assert "existing-user-hook" in stop and stop.index("existing-user-hook") < stop.index("--provider")
                checks.append("Codex effective user hooks retained before observer")
            if provider == "claude":
                settings = json.loads(plan["arguments"][2])
                command = settings["hooks"]["Stop"][0]["hooks"][0]["command"]
                marker = "PRIVATE_PROMPT_MUST_NOT_BE_SAVED"
                payload = json.dumps({"hook_event_name": "Stop", "session_id": "fixture-session",
                                      "prompt": marker, "last_assistant_message": marker})
                output = run([], payload=payload, command=["/bin/zsh", "-f", "-c", command])
                assert output.stdout == output.stderr == ""
                events = list((root / "events").glob("*.json"))
                assert len(events) == 1
                content = events[0].read_text()
                event = json.loads(content)
                assert marker not in content
                assert event["taskID"].upper() == tasks[0]
                assert event["state"] == "ready" and event["provider"] == "claude"
                checks.append("quoted hook command, silent exit, state-only event")
                events[0].unlink()

        output = run(["hook", "--provider", "codex"] + base, payload="{broken")
        assert output.stdout == output.stderr == "" and not list((root / "events").glob("*.json"))
        checks.append("malformed hook cannot interrupt CLI or enqueue state")
        run(["status", "--root", str(root), "--slot", "1", "--state", "waiting", "--message", "manual check"])
        event = json.loads(next((root / "events").glob("*.json")).read_text())
        assert event["taskID"].upper() == tasks[0] and event["state"] == "waiting"
        assert event["provider"] == "manual"
        checks.append("manual status resolves occupied slot to immutable task")
        rejected = subprocess.run([str(binary), "plan", "--provider", "codex", "--task", str(uuid.uuid4()),
                                   "--root", str(root)], capture_output=True, text=True, timeout=10)
        assert rejected.returncode != 0
        checks.append("retired task command rejected before launching agent")
    print(json.dumps({"passed": len(checks), "checks": checks}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
