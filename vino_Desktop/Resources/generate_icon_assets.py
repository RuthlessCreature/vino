#!/usr/bin/env python3

from pathlib import Path

from PIL import Image, ImageColor, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent
ICONSET = ROOT / "AppIcon.iconset"
SOURCE_PNG = ROOT / "vino_Desktop_icon_1024.png"
ICNS = ROOT / "vino_Desktop.icns"


def rounded_rectangle(draw: ImageDraw.ImageDraw, box, radius, outline, width):
    draw.rounded_rectangle(box, radius=radius, outline=outline, width=width)


def make_master_icon(size: int = 1024) -> Image.Image:
    scale = 4
    canvas_size = size * scale
    image = Image.new("RGBA", (canvas_size, canvas_size), ImageColor.getrgb("#050608"))
    draw = ImageDraw.Draw(image)

    accent = ImageColor.getrgb("#62F0FF")
    stroke = ImageColor.getrgb("#24303A")
    cyan_soft = ImageColor.getrgb("#7AF5FF")
    success = ImageColor.getrgb("#55E39E")

    rounded_rectangle(
        draw,
        (84 * scale, 84 * scale, (size - 84) * scale, (size - 84) * scale),
        radius=160 * scale,
        outline=stroke,
        width=12 * scale,
    )
    rounded_rectangle(
        draw,
        (132 * scale, 132 * scale, (size - 132) * scale, (size - 132) * scale),
        radius=132 * scale,
        outline=accent,
        width=10 * scale,
    )

    glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    rounded_rectangle(
        glow_draw,
        (132 * scale, 132 * scale, (size - 132) * scale, (size - 132) * scale),
        radius=132 * scale,
        outline=accent + (255,),
        width=26 * scale,
    )
    glow = glow.filter(ImageFilter.GaussianBlur(18 * scale))
    image = Image.alpha_composite(image, glow)
    draw = ImageDraw.Draw(image)

    for index in range(7):
        offset = 220 * scale + index * 70 * scale
        alpha = 35 if index % 2 == 0 else 22
        draw.line(
            [(190 * scale, offset), ((size - 190) * scale, offset)],
            fill=accent + (alpha,),
            width=2 * scale,
        )

    v_points = [
        (246 * scale, 248 * scale),
        (392 * scale, 248 * scale),
        (512 * scale, 640 * scale),
        (632 * scale, 248 * scale),
        (778 * scale, 248 * scale),
        (576 * scale, 812 * scale),
        (448 * scale, 812 * scale),
    ]
    draw.line(v_points[:4], fill=accent, width=42 * scale, joint="curve")
    draw.line(v_points[3:], fill=accent, width=42 * scale, joint="curve")
    draw.polygon(v_points, fill=None, outline=cyan_soft)

    ring_box = (560 * scale, 400 * scale, 820 * scale, 660 * scale)
    draw.ellipse(ring_box, outline=accent, width=24 * scale)
    draw.ellipse(
        (608 * scale, 448 * scale, 772 * scale, 612 * scale),
        outline=cyan_soft,
        width=12 * scale,
    )
    draw.ellipse(
        (666 * scale, 506 * scale, 714 * scale, 554 * scale),
        fill=success,
    )

    corner = [
        (214 * scale, 742 * scale),
        (286 * scale, 742 * scale),
        (286 * scale, 814 * scale),
    ]
    draw.line(corner, fill=accent, width=18 * scale)

    return image.resize((size, size), Image.Resampling.LANCZOS)


def main():
    ICONSET.mkdir(parents=True, exist_ok=True)
    master = make_master_icon(1024)
    master.save(SOURCE_PNG)

    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for file_name, size in sizes:
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(ICONSET / file_name)


if __name__ == "__main__":
    main()
