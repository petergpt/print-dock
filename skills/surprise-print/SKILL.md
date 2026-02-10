---
name: surprise-print
description: Research a set of current news headlines, prioritize uplifting and curiosity-driven stories, synthesize a visual theme, generate a playful surprise mini-poster image with the OpenAI Image API, center-crop it to the Hi-Print protocol ratio (5:8), and optionally print it via printdock. Use when a user wants a fun daily-news visual, a surprise print generated from real same-day stories, or an end-to-end research-to-image-to-printer demo.
---

# Surprise Print

Turn today's news into one visually coherent, upbeat "news mood" print.

## Run Behavior (Agent Rules)

- Use a single direct execution command for normal runs:
```bash
./skills/surprise-print/scripts/run_surprise_print.sh --print
```
- Prioritize fun and curiosity-forward headlines (science, culture, tech, human achievement).
- Avoid selecting or emphasizing gruesome, graphic, or tragedy-focused stories when alternatives exist.
- Do not check `Codex Learnings.md` for this skill unless the user explicitly asks.
- Do not run separate preflight probes (`command -v`, ad hoc pip checks, etc.). The runner bootstraps its own `.venv` when needed.
- The runner performs a printer readiness check before sending and skips the print if the device reports not-ready/error status.
- Use `--no-print` only if the user explicitly requests preview-only behavior.
- Keep user updates minimal: start, generation in progress, done/error.

## Quick Start

- Dry run (news research + prompt only):
```bash
./skills/surprise-print/scripts/run_surprise_print.sh --dry-run
```

- Generate image but do not print:
```bash
./skills/surprise-print/scripts/run_surprise_print.sh --no-print
```

- Full run (research + generate + print):
```bash
./skills/surprise-print/scripts/run_surprise_print.sh
```

Printing is ON by default. To force print explicitly, run:
```bash
./skills/surprise-print/scripts/run_surprise_print.sh --print
```

Use `--no-print` only when you explicitly want to skip hardware output.

## Workflow

1. Collect fresh headlines from multiple Google News RSS feeds.
2. Prefer uplifting/curiosity headlines and de-prioritize grim or graphic stories.
3. Build a compact theme summary and extract visual motifs.
4. Generate a text-free vertical editorial illustration in a playful, optimistic style via imagegen.
5. Auto-crop to printer-ready 5:8 ratio and print with `printdock` (unless `--no-print` is passed).
6. Save artifacts in `output/surprise-print/<timestamp>/`:
   - `fact.json` (news digest)
   - `prompt.txt` (final image prompt)
   - `summary.md` (headline/source trace)
   - `surprise.png` (generated image)
   - `surprise_print_ready.png` (printer-ready 5:8 crop)

## Modes

- `news-digest` (default): analyze a set of current headlines with an upbeat, fun-first bias.
- `on-this-day`: optional historical surprise mode.
- `random-summary`: optional random-topic mode.

## Important Options

- `--news-max-items <int>`: number of headlines to analyze (default 12).
- `--mode <news-digest|on-this-day|random-summary>`
- `--print`: force hardware print output.
- `--pace <ms>` and `--timeout <sec>`: BLE print tuning (default pace is `12` ms for safer sends).
- `--dry-run`: validate research + prompt without API calls or printing.

## Printer Ratio Notes

- Hi-Print protocol payload target in this project is `640x1024` (`5:8`), not exact `2:3`.
- The script generates high-resolution vertical art, then center-crops to an exact integer `5:8` image before printing.
- Crop output is validated and the run fails if ratio is not exactly `5:8`.
- Keep key subjects near center to protect composition during crop.

## API Key Setup

Set `OPENAI_API_KEY` in your shell startup file.

For your zsh setup, add this line to:
- `/Users/peter/.zshrc`

```bash
export OPENAI_API_KEY="your_api_key_here"
```

Then restart the terminal (or run `source /Users/peter/.zshrc`).

## Reference

- Prompt/theme tweaks: `references/theme-ideas.md`
- News source details: `references/news-sources.md`
