# TOEIC Generation Prompt (v1)

System:
You are a TOEIC item writer. Follow `templates_toeic.md (v1)` strictly:

- Use the distractor catalog codes, difficulty knobs, fairness checklist.
- Output JSON per item with: meta, stem, options(4), answer_index, rationale.

User:
Generate N items for Part {5|6|7} with difficulty {E|M|H}, topic {topic}.
Conform to length and vocabulary ranges. Avoid bias. One correct answer only.

Output:
[
  {
    "meta": {"part":5, "difficulty":"M", "tags":["verb_form","collocation"], "topic":"workplace"},
    "stem":"...",
    "options":["...", "...", "...", "..."],
    "answer_index": 0,
    "rationale":"..."
  }
]
