"""Check unattended scheduling does not interrupt work or bypass queued user input."""

import unittest

from schedule_review import MARKER, dispatch


class FakeRpc:
    def __init__(self, status="idle", pending=None, race=False):
        self.status = status
        self.pending = list(pending or [])
        self.race = race
        self.calls = []
        self.reads = 0

    def call(self, method, params):
        self.calls.append((method, params))
        if method == "thread/read":
            self.reads += 1
            status = "active" if self.race and self.reads > 1 else self.status
            return {"thread": {"status": {"type": status}}}
        if method == "thread/queue/list":
            return {"data": self.pending, "nextCursor": None}
        if method == "thread/queue/add":
            self.pending.append({"id": "new", "input": params["input"]})
            return {}
        if method == "thread/queue/start":
            return {"turn": {"id": "review-turn"}}
        raise AssertionError(f"Unexpected method: {method}")


class SchedulingTests(unittest.TestCase):
    config = {"review_thread_id": "existing-review-thread"}

    def test_active_review_is_never_queued_or_interrupted(self):
        rpc = FakeRpc(status="active")
        self.assertEqual(dispatch(rpc, self.config)["action"], "skipped_active_review")
        self.assertEqual([x[0] for x in rpc.calls], ["thread/read"])

    def test_user_message_takes_priority(self):
        rpc = FakeRpc(pending=[{"id": "user", "input": [{"type": "text", "text": "暂停"}]}])
        self.assertEqual(dispatch(rpc, self.config)["action"], "skipped_user_queue")
        self.assertFalse(any(x[0] == "thread/queue/start" for x in rpc.calls))

    def test_existing_review_reused_without_duplicate(self):
        rpc = FakeRpc(pending=[{"id": "existing", "input": [{"type": "text", "text": MARKER}]}])
        self.assertEqual(dispatch(rpc, self.config)["action"], "started_review")
        self.assertFalse(any(x[0] == "thread/queue/add" for x in rpc.calls))
        self.assertEqual(rpc.calls[-1][1]["queuedSubmissionId"], "existing")

    def test_fresh_review_starts_on_existing_thread(self):
        rpc = FakeRpc()
        self.assertEqual(dispatch(rpc, self.config)["turn_id"], "review-turn")
        self.assertEqual(sum(x[0] == "thread/queue/add" for x in rpc.calls), 1)
        self.assertTrue(all(x[1]["threadId"] == "existing-review-thread" for x in rpc.calls))

    def test_user_start_race_leaves_review_queued(self):
        rpc = FakeRpc(race=True)
        self.assertEqual(dispatch(rpc, self.config)["action"], "queued_review_waiting_for_active_turn")
        self.assertFalse(any(x[0] == "thread/queue/start" for x in rpc.calls))

    def test_dry_run_never_adds_or_starts(self):
        rpc = FakeRpc()
        self.assertEqual(dispatch(rpc, self.config, dry_run=True)["action"], "would_start_review")
        self.assertFalse(any(x[0] in ("thread/queue/start", "thread/queue/add") for x in rpc.calls))

    def test_automatically_consumed_queue_is_not_started_twice(self):
        class AutoConsumingRpc(FakeRpc):
            def call(self, method, params):
                result = super().call(method, params)
                if method == "thread/queue/add":
                    self.pending.clear()
                    self.status = "active"
                return result
        rpc = AutoConsumingRpc()
        self.assertEqual(dispatch(rpc, self.config)["action"], "started_review_automatically")
        self.assertFalse(any(x[0] == "thread/queue/start" for x in rpc.calls))


if __name__ == "__main__":
    unittest.main()
