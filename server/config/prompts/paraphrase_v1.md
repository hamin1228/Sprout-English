# Paraphrase v1
Goal: Rewrite text preserving meaning, with tone and length controls.

Tones: neutral, formal, casual, friendly, polite, academic, concise
Lengths: shorter, same, longer

JSON contract:
{"candidates":[{"text":"string","tone":"string"}]}
Rules:
- Preserve core meaning; no added facts.
- Avoid idioms that distort intent.
- Return 1~5 candidates.