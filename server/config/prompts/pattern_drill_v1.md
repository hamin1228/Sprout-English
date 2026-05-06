# Pattern Drill v1
Goal: Generate practice items for the pattern and grade user's answer with meaning-preserving tolerance.

JSON contract for "generate":
{
  "items": [
    {"prompt": "string", "answers": ["string", "..."]}
  ]
}

Constraints:
- Keep semantics faithful to the given pattern.
- Provide 3~7 diverse correct answers for each item.
- Simple CEFR A2-B1 vocabulary by default unless context says otherwise.