#!/usr/bin/env python3
"""Split a 4x3 chroma-keyed BoomPet rig sheet into trimmed PNG parts."""

from pathlib import Path
import sys

from PIL import Image


PART_SLOTS = (
    ("body", (0.00, 0.00, 0.29, 0.38)),
    ("head", (0.29, 0.00, 0.58, 0.38)),
    ("ear-left", (0.58, 0.00, 0.78, 0.38)),
    ("ear-right", (0.78, 0.00, 1.00, 0.38)),
    ("leg-front-left", (0.00, 0.38, 0.27, 0.68)),
    ("leg-front-right", (0.27, 0.38, 0.52, 0.68)),
    ("leg-rear-left", (0.52, 0.38, 0.76, 0.68)),
    ("leg-rear-right", (0.76, 0.38, 1.00, 0.68)),
    ("tail", (0.00, 0.68, 0.29, 1.00)),
    ("eyes", (0.29, 0.68, 0.54, 1.00)),
    ("mouth", (0.54, 0.68, 0.76, 1.00)),
    ("shadow", (0.76, 0.68, 1.00, 1.00)),
)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: split-rig-sheet.py INPUT.png OUTPUT_DIRECTORY", file=sys.stderr)
        return 2

    source = Image.open(sys.argv[1]).convert("RGBA")
    output = Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    for name, slot in PART_SLOTS:
        left, top, right, bottom = slot
        cell = source.crop((
            round(left * source.width),
            round(top * source.height),
            round(right * source.width),
            round(bottom * source.height),
        ))
        alpha_box = cell.getchannel("A").getbbox()
        if alpha_box is None:
            raise ValueError(f"{name} cell has no visible pixels")
        trimmed = cell.crop(alpha_box)
        padded = Image.new(
            "RGBA",
            (trimmed.width + 16, trimmed.height + 16),
            (0, 0, 0, 0),
        )
        padded.alpha_composite(trimmed, (8, 8))
        padded.save(output / f"{name}.png")
        print(f"{name}: {padded.width}x{padded.height}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
