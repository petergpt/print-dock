# Surprise Print Skill

This module is independent from the app UI and can be used as a standalone workflow.

It:
- fetches current headlines,
- generates a themed image,
- crops to exact `5:8`,
- optionally prints through `printdock` (with readiness checks to avoid wasted prints).

## Quick Start

From repo root:

```bash
./skills/surprise-print/scripts/run_surprise_print.sh --no-print
```

Print (only if printer reports ready):

```bash
./skills/surprise-print/scripts/run_surprise_print.sh --print
```

## Requirements

- `OPENAI_API_KEY` must be set for image generation.
- The `imagegen` helper is expected at:
  - default: `$HOME/.codex/skills/imagegen/scripts/image_gen.py`
  - override with `--imagegen-script <path>`
- `printdock` is built from this repository by default.

## More

- Skill guide: `skills/surprise-print/SKILL.md`
- Runner script: `skills/surprise-print/scripts/run_surprise_print.sh`
