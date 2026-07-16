# Export path threading — judged output as a file, passed by path

From RepoPrompt CE's path-not-inline export discipline: a panel command's judged result should be
persisted to a **real repo-local file**, and the next step should read it **by path** rather than receiving
it re-summarized inline. Inline re-summarization is lossy, token-heavy, and drifts across hand-offs; a path
on disk is a stable, inspectable seam — the same "two conversations kept separate" instinct as the
scoped-subagent firewall (`subagent-prompt-template.md`).

This is **opt-in** via `--export`. Without it, `/fusion`, `/fusion-plan`, and `/fusion-review` behave
exactly as before (answer in the chat). With it, they also write the deliverable to a file and return the
path.

## Where exports go

```bash
# compute a safe, repo-relative path (creates .fusion/exports/, never clobbers an existing file):
bash <skill-root>/scripts/fusion_export.sh path <verb> "<task or scope text>"
#   -> .fusion/exports/<verb>-<YYYY-MM-DD>-<slug>.md
```

`<verb>` is the command (`fusion` / `plan` / `review` / …); the slug is derived from the task text. Write
the judged answer (for `/fusion`), the lint-passing contract (for `/fusion-plan`), or the prioritized
findings (for `/fusion-review`) to that path, then present **both** the answer and the path.

## Threading into the next step

When the next step is a subagent (`/fusion-orchestrate`) or another agent/model, **do not paste the
content into the brief** — point at the file:

> Read the export at `.fusion/exports/<…>.md` first with Read; it is the authoritative plan/answer. Your
> job is item N.

The scoped-brief template already prefers "discoveries, not instructions"; a path is the cleanest
discovery. For a human/another-model hand-off, the export file IS the artifact to send.

## Stray-export cleanup

Exports accumulate. Prune superseded ones so `.fusion/exports/` reflects live work, not history:

```bash
bash <skill-root>/scripts/fusion_export.sh cleanup [days]   # delete *.md older than <days> (default 14)
```

The durable record of *finished* work is the Handoff Capsule (`handoffs/…`) and any committed plan, not the
scratch exports — so pruning old exports loses nothing that mattered.

## Safety

The helper only computes a path and prunes old files; it never writes content and never emits secrets.
The command writing the export still runs the `safety.md` secret scan before persisting — an export is a
shared artifact, same rules as a Context Pack or Handoff Capsule. Paths are repo-relative, never absolute.
