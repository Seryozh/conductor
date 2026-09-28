#!/usr/bin/env python3
"""Compose the PNGs from `Conductor --render-ui-gallery folder` into contact sheets.

    python3 scripts/ui_gallery_grid.py <gallery folder> <output folder>

Writes conductor-ui-grid-core.png (the key states, sized for an image model) and
conductor-ui-grid-all.png (every state, grouped). Needs Pillow.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CANVAS = (102, 107, 117)        # the gallery's backdrop, so panel tiles merge into the sheet
INK = (245, 241, 232)
MUTED = (215, 218, 224)
FONT = "/System/Library/Fonts/Helvetica.ttc"
# The key states in reading order: one row per stage of a request.
CORE = ["idle-ready", "listening-fn-short", "listening-fn-long", "recognizing-short",
        "thinking", "acting-jev-step", "checking", "busy-listening-next-text",
        "answer-short", "answer-short-details", "answer-medium", "typing-with-text",
        "error-brain-with-answer", "error-speech-interrupted-draft", "setup-no-key", "permission-voice-request"]


def font(size, bold=False):
    return ImageFont.truetype(FONT, size, index=1 if bold else 0)


def tile(folder, entry, width):
    image = Image.open(folder / entry["file"]).convert("RGB")
    scale = min(0.5, width / image.width)    # renders are 2x: shown at their size in points unless too wide
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)


def caption(entry):
    return f"{entry['file'][:3]}  {entry['title']}"


def grid(folder, entries, columns, column_width, gap):
    """Row-major grid: every row top-aligned, so each state keeps a fixed, readable position."""
    label_font = font(15)
    cells = []
    for entry in entries:
        image = tile(folder, entry, column_width)
        cells.append((image, wrap(caption(entry), label_font, column_width - 12)))
    rows = [cells[i:i + columns] for i in range(0, len(cells), columns)]
    heights = [max(image.height + 8 + 20 * len(lines) for image, lines in row) for row in rows]
    section = Image.new("RGB", (columns * column_width + (columns - 1) * gap, sum(heights) + gap * (len(rows) - 1)), CANVAS)
    draw = ImageDraw.Draw(section)
    top = 0
    for row, height in zip(rows, heights):
        for column, (image, lines) in enumerate(row):
            x = column * (column_width + gap)
            section.paste(image, (x + (column_width - image.width) // 2, top))
            for number, line in enumerate(lines):
                draw.text((x + 14, top + image.height + 4 + 20 * number), line, font=label_font, fill=MUTED)
        top += height + gap
    return section


def wrap(text, face, width):
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = (line + " " + word).strip()
        if face.getlength(trial) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line] if line else lines


def sheet(title, sections, width, margin=40):
    head_font, section_font = font(30, bold=True), font(22, bold=True)
    height = margin + 50 + sum(56 + s.height + 30 for _, s in sections) + margin
    out = Image.new("RGB", (width, height), CANVAS)
    draw = ImageDraw.Draw(out)
    draw.text((margin, margin), title, font=head_font, fill=INK)
    top = margin + 50
    for name, section in sections:
        draw.text((margin, top + 14), name, font=section_font, fill=INK)
        out.paste(section, (margin, top + 56))
        top += 56 + section.height + 30
    return out


def main():
    folder, target = Path(sys.argv[1]), Path(sys.argv[2])
    target.mkdir(parents=True, exist_ok=True)
    entries = json.loads((folder / "gallery.json").read_text())
    by_name = {e["file"][4:-4].removeprefix("panel-"): e for e in entries}
    core = [by_name[name] for name in CORE]
    core_section = grid(folder, core, 4, 560, 24)
    core_sheet = sheet("Conductor command panel: key states (numbers match the full gallery)",
                       [("Rows: idle and listening · working · answers and typing · errors and setup", core_section)],
                       core_section.width + 80)
    core_sheet.save(target / "conductor-ui-grid-core.png", optimize=True)
    groups = {}
    for entry in entries:
        groups.setdefault(entry["group"], []).append(entry)
    layout = {"Command panel": (8, 460)}     # other groups: four wide columns
    order = ["Command panel", "Settings window", "Practice window", "Menus (reconstructed)", "Artwork"]
    sections = [(f"{name} ({len(groups[name])})", grid(folder, groups[name], *layout.get(name, (4, 940)), 20))
                for name in order if name in groups]
    width = max(section.width for _, section in sections) + 80
    all_sheet = sheet(f"Conductor UI: all {len(entries)} states (sample data, rendered offscreen)", sections, width)
    all_sheet.save(target / "conductor-ui-grid-all.png", optimize=True)
    for name in ("conductor-ui-grid-core.png", "conductor-ui-grid-all.png"):
        with Image.open(target / name) as image:
            print(name, image.size)


if __name__ == "__main__":
    main()
