#!/usr/bin/env python3
"""Join the README states from `Conductor --render-ui-gallery` into assets/flow.png.

Usage: python3 scripts/readme_flow.py <gallery folder> [assets/flow.png]
The gallery's README group (files named *-panel-readme-*.png) follows one request
from speech to answer. Needs Pillow and the macOS system font.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BACKGROUND = (14, 14, 14)
ACCENT = (255, 195, 74)
FOREGROUND = (245, 241, 232)
STEPS = [
    ("readme-listening", "Hold Fn and speak"),
    ("readme-thinking", "Claude Code or Codex plans"),
    ("readme-acting", "Jev picks the control"),
    ("readme-answer", "Conductor reports back"),
]


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    try:
        face.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return face


def main() -> None:
    folder = Path(sys.argv[1])
    output = Path(sys.argv[2] if len(sys.argv) > 2 else "assets/flow.png")
    panels = []
    for key, caption in STEPS:
        matches = sorted(folder.glob(f"*-panel-{key}.png"))
        if not matches:
            sys.exit(f"Missing {key} in {folder}; render the gallery first.")
        panels.append((Image.open(matches[0]).convert("RGB"), caption))

    cell = max(image.width for image, _ in panels)
    caption_height, margin, gap = 28, 24, 8  # captions sit in the render's own top padding
    rows = [panels[0:2], panels[2:4]]
    row_heights = [max(image.height for image, _ in row) for row in rows]
    width = margin * 2 + cell * 2 + gap
    height = margin * 2 + sum(caption_height + h for h in row_heights)
    canvas = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    number_font, text_font = font(34, "Bold"), font(34, "Semibold")

    y = margin
    for row_index, row in enumerate(rows):
        for column, (image, caption) in enumerate(row):
            x = margin + column * (cell + gap)
            label_x = x + 56  # the render's own backdrop padding, so captions align with the panel edge
            number = f"{row_index * 2 + column + 1}"
            canvas.paste(image, (x, y + caption_height))
            draw.text((label_x, y + 12), number, font=number_font, fill=ACCENT)
            draw.text((label_x + draw.textlength(number, font=number_font) + 16, y + 12), caption, font=text_font, fill=FOREGROUND)
        y += caption_height + row_heights[row_index]

    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, optimize=True)
    print(f"Wrote {output} ({width} × {height})")


if __name__ == "__main__":
    main()
