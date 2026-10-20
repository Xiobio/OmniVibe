# Focused experience audit

Run from the repository root:

```
dotnet run --project tools/experience-audit/ExperienceAudit.csproj -c Debug
```

The project reference rebuilds current production source to an isolated
`artifacts/experience-audit/product-build/`, without replacing the running app.
The probe loads WPF styles but
does not run the product's App startup or Manager constructor, install hooks,
register shortcuts, show windows, or operate on a CLI. A Manager fixture is
constructed without its constructor and only the dependencies needed by the
audited production methods are supplied. State files are isolated under
`artifacts/experience-audit/isolated-state/`. The custom-audio failure probe uses
a fresh random, unreferenced entity directory and deletes it afterwards.

Current output: `artifacts/experience-audit/report-after.json`. Each run creates a
fresh UUID state directory. The original `report.json` and `Program.cs` are
preserved as historical before evidence; `Program.cs` is excluded from the build.
`AfterAudit.cs` asserts the corrected behavior, including real batch files,
atomic override rollback, and silence for every operation except window switch.

All ten current groups pass:

1. Same state/message preserves an already read indicator; changed content becomes unread.
2. Twenty-four real event files are applied in order and cause one atomic state write.
3. A locked state file retains all 24 input events and dirty state; retry writes once and commits the final timestamp.
4. An identical event replay preserves read state, is discarded and writes no state.
5. Eight warm 24-event bursts cause eight writes, measured including JSON reads and event deletion.
6. A second override locked exclusively leaves the first untouched.
7. A read-only second override rolls back a newly created first override.
8. A read-only second override restores an existing first override byte for byte.
9. Capture, notifications and every other non-switch operation stay silent, both inside and outside a picker transaction.
10. Move and reorder preserve functional identity, uniqueness and event routing.

Override failure cases also assert no abandoned staging files. Every audio target
uses a new random identity, and cleanup restores file attributes before deleting
only that fixture directory. No task configuration, theme selection, or CLI is
changed. `FileSystemWatcher` counts the actual unique `tasks.json.tmp-*` creations
from `StateStore.AtomicWrite`; state content and source event deletion are checked
separately so a write count alone cannot masquerade as successful processing.

Latest warm-burst result: median 10.42 ms, maximum 13.92 ms for 24 real events in a
102 KB valid state, one atomic write per batch. These timings are evidence from
this machine, not cross-device performance limits. The before benchmark below
excluded event reads/deletion, so compare the write count directly rather than
treating the measurements as identical workloads.

Historical findings against the pre-audit build (now corrected):

| Finding | Priority | Actual evidence | Suggested direction |
| --- | --- | --- | --- |
| Failed audio draft commit partially persists earlier changes | P2 | Two valid WAV drafts; hold the second target open with `FileShare.None`; `TryCommit` returns false but the first target exists | Stage/preflight the whole batch, retain previous bytes and roll back on any failure; do not apply drafts until all settings validation is done |
| Picker capture has no sound | P2 | `PlayCue(Capture)` with `_dialog=true` emits nothing, same call after dialog guard cleared starts the real audio engine | Close/end the picker dialog before committing successful Bind, or explicitly defer one successful capture cue until `EndDialog` |
| Duplicate status re-arms an already read indicator | P2 | Ready + same message is marked read, then same Ready/message with a newer timestamp marks it unread again | Keep monotonic UpdatedAt, but only re-arm unread/pulse for meaningful state/content/session change; retain unread while it has not been read |
| Bounded status processing can still miss UI frames | P2 | 24 `SetStatus` calls synchronously write a valid 102 KB state 24 times; eight batches median 31.69 ms, max 32.37 ms on the local disk | Batch state persistence and visual invalidation once per consumed batch; retain strict event ordering and transition notification semantics |

The last measurement includes normal per-status refresh work but excludes file
enumeration, event JSON reads and native checks, so it does not overstate those
additional costs. It is a short burst latency issue, not evidence of sustained
high CPU usage.

Positive check: MoveSlot → ReorderSlot retains functional task ID, unique IDs
and correct routing of a subsequent event carrying the original task ID.

Read-only lifecycle review also found that InputService unhooks mouse/keyboard/
WinEvent handles and disposes its message source; DockWindow stops both timers,
unsubscribes Rendering, closes menus/hints on Closed; InventoryWindow stops its
timer, disposes thumbnails/mask and unsubscribes slots on Closed. No reproducible
leak is asserted from this review. Full foreground-sensitive minimize/focus and
native window tests remain in the product's existing self-test suite.
