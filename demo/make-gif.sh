#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'Usage: bash demo/make-gif.sh work/conductor-demo.mov\n' >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RECORDING="$1"
case "$RECORDING" in
  /*) ;;
  *) RECORDING="$PWD/$RECORDING" ;;
esac
if [ ! -f "$RECORDING" ]; then
  printf 'Recording not found: %s\n' "$RECORDING" >&2
  exit 2
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  printf 'FFmpeg is needed to make the GIF.\n' >&2
  exit 2
fi

mkdir -p "$REPO_ROOT/work"
PALETTE="$REPO_ROOT/work/conductor-palette.png"
GIF="$REPO_ROOT/assets/demo.gif"
PENDING_DIR="$(mktemp -d "$REPO_ROOT/work/conductor-demo-XXXXXX")"
PENDING_GIF="$PENDING_DIR/demo.gif"
trap 'rm -rf "$PENDING_DIR"' EXIT
ffmpeg -nostdin -hide_banner -loglevel error -ss 0 -i "$RECORDING" -t 38 \
  -vf 'fps=12,scale=1200:-1:flags=lanczos,palettegen' \
  -frames:v 1 -y "$PALETTE"
ffmpeg -nostdin -hide_banner -loglevel error -ss 0 -i "$RECORDING" -i "$PALETTE" -t 38 \
  -filter_complex '[0:v]fps=12,scale=1200:-1:flags=lanczos[frames];[frames][1:v]paletteuse=dither=sierra2_4a' \
  -loop 0 -y "$PENDING_GIF"
mv -f "$PENDING_GIF" "$GIF"

python3 - "$REPO_ROOT/README.md" <<'PY'
from pathlib import Path
import sys

readme = Path(sys.argv[1])
text = readme.read_text()
start, end = '<!-- demo:start -->', '<!-- demo:end -->'
if text.count(start) != 1 or text.count(end) != 1:
    raise SystemExit('README demo markers are missing or duplicated; GIF was saved but not embedded.')
before, rest = text.split(start, 1)
current, after = rest.split(end, 1)
if 'real screen recording is still pending' not in current and 'assets/demo.gif' not in current:
    raise SystemExit('README demo section was edited; GIF was saved but not embedded.')
readme.write_text(before + start + '\n\n![Conductor demo](assets/demo.gif)\n\n' + end + after)
PY

printf 'Created %s and linked it in README.md. Review both before committing.\n' "$GIF"
