# Contradiction matrix

After the first blind round in `/fusion-ultra`, the judge writes a compact matrix instead of immediately
averaging answers.

```json
{
  "consensus": [],
  "contradictions": [
    {
      "claim": "",
      "positions": { "opus_a": "", "opus_b": "", "gpt": "", "gemini": "" },
      "severity": "blocking | non_blocking",
      "needs": "test | source | code trace | user decision"
    }
  ],
  "blind_spots": [],
  "targeted_probes": [
    {
      "assignee": "codex | gemini | opus | deterministic",
      "question": "",
      "required_output": ""
    }
  ]
}
```

`positions` is keyed per **realized** panelist from the manifest — include one key per realized panelist;
an absent panelist gets **no key** (absence ≠ agreement). In wide/ultra rounds the two cold Opus runs get
separate keys (`opus_a`, `opus_b`) — Opus-vs-Opus disagreement is a paid-for signal, never merge them.
Each `targeted_probes` entry's `required_output` must name its discriminating oracle per
`references/probe-quality.md`.

Only blocking or uncertainty-reducing probes get a second round.
