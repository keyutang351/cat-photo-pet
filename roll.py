"""Patch only the five v2 hover cells using extracted, despilled RGBA artwork."""
import argparse
from pathlib import Path
from PIL import Image, ImageChops

CELL = (192, 208)


def build(source, row, destination, preview):
    with Image.open(source) as image:
        atlas = image.convert("RGBA")
    with Image.open(row) as image:
        strip = image.convert("RGBA")
    if atlas.size != (1536, 2288) or strip.size != (960, 208):
        raise ValueError("Expected a v2 atlas and five registered 192 × 208 cells")
    if destination.resolve() == source.resolve():
        raise ValueError("Choose a separate output to keep the original atlas")
    original = atlas.copy()
    idle = atlas.crop((0, 0, *CELL)).getchannel("A").getbbox()
    if not idle:
        raise ValueError("Missing idle frame")
    poses = []
    for index in range(5):
        x = index * CELL[0]
        pose = strip.crop((x, 0, x + CELL[0], CELL[1]))
        bounds = pose.getchannel("A").getbbox()
        if not bounds or bounds[0] == 0 or bounds[2] == CELL[0]:
            raise ValueError(f"Missing or edge-touching roll pose {index + 1}")
        poses.append((pose, bounds))
    baseline = max(idle[3], max(b[3]-b[1]+2 for _, b in poses))
    if baseline >= CELL[1]:
        raise ValueError("Roll artwork too tall. Re-extract with shared scale and padding.")
    frames = []
    for index, (pose, bounds) in enumerate(poses):
        tile = Image.new("RGBA", CELL)
        tile.alpha_composite(pose, (0, baseline - bounds[3]))
        atlas.paste(tile, (index * CELL[0], 4 * CELL[1]))
        bg = Image.new("RGB", CELL, "#f8f5ef")
        bg.paste(tile, mask=tile.getchannel("A"))
        frames.append(bg)
    atlas.save(destination, "WEBP", lossless=True, exact=True)
    with Image.open(destination) as encoded:
        diff = ImageChops.difference(original, encoded.convert("RGBA"))
        diff.paste((0, 0, 0, 0), (0, 832, 960, 1040))
        if any(channel.getbbox() for channel in diff.split()):
            raise ValueError("Encoded atlas changed outside the hover cells")
    frames[0].save(preview, "GIF", save_all=True, append_images=frames[1:],
                   duration=[260, 160, 320, 160, 240], loop=0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ("atlas", "clean_row", "output_webp", "preview_gif"):
        parser.add_argument(arg, type=Path)
    args = parser.parse_args()
    build(args.atlas, args.clean_row, args.output_webp, args.preview_gif)
