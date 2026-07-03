# Contradiction matrix

After the first blind round in `/fusion-ultra`, the judge writes a compact matrix instead of immediately
averaging answers.

```json
{
  "consensus": [],
  "contradictions": [
    {
      "claim": "",
      "opus_position": "",
      "gpt_position": "",
      "gemini_position": "",
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

Only blocking or uncertainty-reducing probes get a second round.
