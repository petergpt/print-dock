#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
FACT_SCRIPT="$ROOT/scripts/fetch_surprise_fact.py"
NEWS_SCRIPT="$ROOT/scripts/fetch_news_digest.py"
IMAGEGEN_SCRIPT_DEFAULT="$HOME/.codex/skills/imagegen/scripts/image_gen.py"

PRINTDOCK_PATH="${PRINTDOCK_PATH:-$REPO_ROOT}"
IMAGEGEN_SCRIPT="${IMAGEGEN_SCRIPT:-$IMAGEGEN_SCRIPT_DEFAULT}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SKILL_VENV="${ROOT}/.venv"
MODE="news-digest"
SEED=""
OUT_DIR="${ROOT}/output/surprise-print/$(date +%Y%m%d-%H%M%S)"
DO_PRINT=1
DRY_RUN=0
PACE_MS=12
TIMEOUT_SEC=90
MODEL="gpt-image-1.5"
SIZE="1024x1536"
QUALITY="high"
NEWS_MAX_ITEMS=12

usage() {
  cat <<'EOF'
Usage: run_surprise_print.sh [options]

Options:
  --mode <news-digest|on-this-day|random-summary>
                                    Surprise source mode (default: news-digest)
  --news-max-items <int>            Number of headlines to analyze in news mode (default: 12)
  --seed <int>                      Deterministic seed (fact modes only)
  --out-dir <path>                  Output directory for artifacts
  --print                           Force sending to printer
  --no-print                        Skip sending to printer
  --dry-run                         Research + prompt only (no API image call, no print)
  --pace <ms>                       BLE pace in milliseconds (default: 12)
  --timeout <sec>                   printdock timeout seconds (default: 90)
  --model <name>                    Image model (default: gpt-image-1.5)
  --size <WxH>                      Image size (default: 1024x1536)
  --quality <level>                 low|medium|high|auto (default: high)
  --python-bin <path>               Python binary to use (default: python3)
  --printdock-path <path>           Path to hiprint-studio-mac package
  --imagegen-script <path>          Path to image_gen.py
  -h, --help                        Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --news-max-items)
      NEWS_MAX_ITEMS="$2"
      shift 2
      ;;
    --seed)
      SEED="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --print)
      DO_PRINT=1
      shift
      ;;
    --no-print)
      DO_PRINT=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      DO_PRINT=0
      shift
      ;;
    --pace)
      PACE_MS="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SEC="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --size)
      SIZE="$2"
      shift 2
      ;;
    --quality)
      QUALITY="$2"
      shift 2
      ;;
    --python-bin)
      PYTHON_BIN="$2"
      shift 2
      ;;
    --printdock-path)
      PRINTDOCK_PATH="$2"
      shift 2
      ;;
    --imagegen-script)
      IMAGEGEN_SCRIPT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

mkdir -p "$OUT_DIR"
FACT_JSON="$OUT_DIR/fact.json"
PROMPT_TXT="$OUT_DIR/prompt.txt"
IMAGE_OUT="$OUT_DIR/surprise.png"
PRINT_READY="$OUT_DIR/surprise_print_ready.png"
SUMMARY_MD="$OUT_DIR/summary.md"

if [[ ! -f "$IMAGEGEN_SCRIPT" ]]; then
  echo "imagegen script not found: $IMAGEGEN_SCRIPT" >&2
  exit 1
fi

ensure_python_runtime() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  if "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import importlib.util
assert importlib.util.find_spec("openai")
assert importlib.util.find_spec("PIL")
PY
  then
    return 0
  fi

  if [[ -x "$SKILL_VENV/bin/python" ]] && "$SKILL_VENV/bin/python" - <<'PY' >/dev/null 2>&1
import importlib.util
assert importlib.util.find_spec("openai")
assert importlib.util.find_spec("PIL")
PY
  then
    PYTHON_BIN="$SKILL_VENV/bin/python"
    return 0
  fi

  echo "Python deps missing in $PYTHON_BIN; bootstrapping local venv at $SKILL_VENV"
  python3 -m venv "$SKILL_VENV"
  "$SKILL_VENV/bin/pip" install --quiet openai pillow
  PYTHON_BIN="$SKILL_VENV/bin/python"
}

run_printdock_via_app_wrapper() {
  local wrapper_app="$OUT_DIR/printdock-cli.app"
  local wrapper_bin="$wrapper_app/Contents/MacOS/printdock"
  local bin_path
  local built_bin
  local stdout_log="$OUT_DIR/printdock.stdout.log"
  local stderr_log="$OUT_DIR/printdock.stderr.log"
  local cmd="${1:-}"

  swift build --package-path "$PRINTDOCK_PATH" --product printdock >/dev/null
  bin_path="$(swift build --package-path "$PRINTDOCK_PATH" --show-bin-path)"
  built_bin="$bin_path/printdock"

  if [[ ! -f "$built_bin" ]]; then
    echo "Could not find built printdock binary: $built_bin" >&2
    return 1
  fi

  rm -rf "$wrapper_app"
  mkdir -p "$wrapper_app/Contents/MacOS"
  cp "$built_bin" "$wrapper_bin"

  cat > "$wrapper_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>printdock-cli</string>
  <key>CFBundleDisplayName</key><string>printdock-cli</string>
  <key>CFBundleIdentifier</key><string>com.printdock.cli.bundle</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>printdock</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>printdock needs Bluetooth to connect to your Hi-Print printer.</string>
  <key>NSBluetoothPeripheralUsageDescription</key><string>printdock needs Bluetooth to connect to your Hi-Print printer.</string>
</dict>
</plist>
PLIST

  if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$wrapper_app" >/dev/null 2>&1 || true
  fi

  rm -f "$stdout_log" "$stderr_log"
  open -W -n "$wrapper_app" \
    --stdout "$stdout_log" \
    --stderr "$stderr_log" \
    --args "$@"

  if [[ -s "$stdout_log" ]]; then
    cat "$stdout_log"
  fi
  if [[ -s "$stderr_log" ]]; then
    cat "$stderr_log" >&2
  fi

  if [[ "$cmd" == "print" ]]; then
    if [[ -s "$stdout_log" ]] && grep -q "PRINT_DONE" "$stdout_log"; then
      return 0
    fi
    echo "printdock did not report PRINT_DONE; check logs: $stdout_log and $stderr_log" >&2
    return 1
  fi

  if [[ "$cmd" == "status" ]]; then
    if [[ -s "$stdout_log" ]] && grep -q "^STATUS " "$stdout_log"; then
      return 0
    fi
    echo "printdock status did not return STATUS output; check logs: $stdout_log and $stderr_log" >&2
    return 1
  fi
}

ensure_printer_ready() {
  local attempts=2
  local wait_seconds=8
  local status_timeout="$TIMEOUT_SEC"
  local attempt

  if (( status_timeout > 20 )); then
    status_timeout=20
  fi

  for ((attempt=1; attempt<=attempts; attempt++)); do
    echo "==> Checking printer readiness (attempt ${attempt}/${attempts})"

    if run_printdock_via_app_wrapper status --timeout "$status_timeout"; then
      if [[ -s "$OUT_DIR/printdock.stdout.log" ]] && grep -q "^READY true$" "$OUT_DIR/printdock.stdout.log"; then
        return 0
      fi
      if [[ "$attempt" -lt "$attempts" ]]; then
        echo "Printer not ready yet. Waiting ${wait_seconds}s before retry."
      fi
    elif [[ "$attempt" -lt "$attempts" ]]; then
      echo "Unable to read printer status. Waiting ${wait_seconds}s before retry."
    fi

    if [[ "$attempt" -lt "$attempts" ]]; then
      sleep "$wait_seconds"
    fi
  done

  echo "Printer is not ready for a new job. Skipping print to avoid waste." >&2
  return 1
}

case "$MODE" in
  news-digest)
    if [[ ! -x "$NEWS_SCRIPT" ]]; then
      echo "Missing news script: $NEWS_SCRIPT" >&2
      exit 1
    fi
    "$NEWS_SCRIPT" --max-items "$NEWS_MAX_ITEMS" --out "$FACT_JSON" >/dev/null
    ;;
  on-this-day|random-summary)
    if [[ ! -x "$FACT_SCRIPT" ]]; then
      echo "Missing fact script: $FACT_SCRIPT" >&2
      exit 1
    fi
    seed_args=()
    if [[ -n "$SEED" ]]; then
      seed_args=(--seed "$SEED")
    fi
    "$FACT_SCRIPT" --mode "$MODE" "${seed_args[@]}" --out "$FACT_JSON" >/dev/null
    ;;
  *)
    echo "Invalid --mode: $MODE" >&2
    exit 2
    ;;
esac

"$PYTHON_BIN" - "$FACT_JSON" "$PROMPT_TXT" "$SUMMARY_MD" <<'PY'
import json
import sys
from pathlib import Path

fact_path = Path(sys.argv[1])
prompt_path = Path(sys.argv[2])
summary_path = Path(sys.argv[3])

obj = json.loads(fact_path.read_text(encoding="utf-8"))
prompt = obj.get("prompt", "Create a beautiful vertical editorial illustration with no text.")

prompt_path.write_text(prompt + "\n", encoding="utf-8")

lines = [
    f"# {obj.get('headline', 'Surprise Print')}\n",
    f"- Mode: {obj.get('mode', 'unknown')}",
    f"- Date: {obj.get('date', 'N/A')}",
    f"- Summary: {obj.get('theme_summary') or obj.get('fact', 'N/A')}",
    f"- Source: {obj.get('source_title', 'N/A')} ({obj.get('source_url', 'N/A')})",
    "",
]

headlines = obj.get("headlines") or []
if headlines:
    lines.extend(["## Headlines Used", ""])
    for item in headlines:
        title = item.get("title", "(untitled)")
        source = item.get("source", "Unknown")
        link = item.get("link", "")
        lines.append(f"- {title} ({source})")
        if link:
            lines.append(f"  Link: {link}")
    lines.append("")

lines.extend(["## Image Prompt", "", prompt, ""])
summary_path.write_text("\n".join(lines), encoding="utf-8")
PY

ensure_python_runtime

image_cmd=(
  "$PYTHON_BIN" "$IMAGEGEN_SCRIPT" generate
  --prompt-file "$PROMPT_TXT"
  --model "$MODEL"
  --size "$SIZE"
  --quality "$QUALITY"
  --output-format png
  --out "$IMAGE_OUT"
  --force
  --use-case stylized-concept
  --constraints "No text, no letters, no numbers, no logos, no watermark."
)

if [[ "$DRY_RUN" -eq 1 ]]; then
  image_cmd+=(--dry-run)
  echo "==> Dry run: image generation request preview"
else
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "OPENAI_API_KEY is not set. Export it or use --dry-run." >&2
    exit 1
  fi
  echo "==> Generating surprise image"
fi

"${image_cmd[@]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run complete. Artifacts written to: $OUT_DIR"
  echo "- $FACT_JSON"
  echo "- $PROMPT_TXT"
  echo "- $SUMMARY_MD"
  exit 0
fi

# Normalize to printer ratio (5:8 portrait) before sending.
# Enforce exact integer 5:8 output dimensions and fail if crop validation fails.
crop_dims="$("$PYTHON_BIN" - "$IMAGE_OUT" "$PRINT_READY" <<'PY'
from pathlib import Path
import sys

from PIL import Image

src = Path(sys.argv[1])
dst = Path(sys.argv[2])

with Image.open(src) as image:
    src_w, src_h = image.size
    unit = min(src_w // 5, src_h // 8)
    if unit <= 0:
        raise SystemExit(f"Image too small for 5:8 crop: {src_w}x{src_h}")

    crop_w = 5 * unit
    crop_h = 8 * unit
    left = (src_w - crop_w) // 2
    top = (src_h - crop_h) // 2
    cropped = image.crop((left, top, left + crop_w, top + crop_h))
    cropped.save(dst, format="PNG")

with Image.open(dst) as out:
    out_w, out_h = out.size

if out_w * 8 != out_h * 5:
    raise SystemExit(f"Invalid crop ratio after write: {out_w}x{out_h}")

print(f"{out_w} {out_h}")
PY
)"

read -r crop_w crop_h <<<"$crop_dims"
echo "Prepared printer-ready image at exact 5:8 ratio: $PRINT_READY (${crop_w}x${crop_h})"

if [[ "$DO_PRINT" -eq 1 ]]; then
  if [[ ! -d "$PRINTDOCK_PATH" ]]; then
    echo "printdock package path not found: $PRINTDOCK_PATH" >&2
    exit 1
  fi

  ensure_printer_ready

  echo "==> Sending image to Hi-Print"
  run_printdock_via_app_wrapper print "$PRINT_READY" --pace "$PACE_MS" --timeout "$TIMEOUT_SEC"
else
  echo "Image generated. Printing skipped (--no-print)."
  echo "Printer-ready image: $PRINT_READY"
fi

echo "Done. Artifacts in: $OUT_DIR"
