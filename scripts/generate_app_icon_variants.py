#!/usr/bin/env python3
"""Generate the unified, color-coded CL application icon family."""

from pathlib import Path

from PIL import Image, ImageColor, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "app_icons"
FONT_BOLD = Path("/System/Library/Fonts/SFNS.ttf")
FONT_ROUNDED = Path("/System/Library/Fonts/SFNSRounded.ttf")

VARIANTS = {
    "CL_Audio_Show_Control": ("SHOW CONTROL", "#D84A4A"),
    "CL_Ableton": ("BUILDER", "#E58A3A"),
    "CL_MIDI_RTP_Diagnostic": ("MIDI RTP DIAG", "#D5A735"),
    "CL_MIDI_Network": ("MIDI NETWORK", "#32B89C"),
    "CL_MIDI_Analyzer": ("MIDI ANALYZER", "#3E9ED6"),
    "CL_MIDI_Performance": ("MIDI PERFORMANCE", "#3974D8"),
    "CL_MIDI_RTP": ("MIDI RTP", "#6557C8"),
}


def fitted_font(text: str, maximum_width: int, start_size: int) -> ImageFont.FreeTypeFont:
    size = start_size
    while size > 28:
        font = ImageFont.truetype(str(FONT_BOLD), size)
        left, _, right, _ = font.getbbox(text)
        if right - left <= maximum_width:
            return font
        size -= 2
    return ImageFont.truetype(str(FONT_BOLD), size)


def render_variant(label: str, color: str) -> Image.Image:
    size = 1024
    accent = ImageColor.getrgb(color)
    gradient = Image.linear_gradient("L").resize((size, size))
    top = Image.new("RGB", (size, size), (40, 47, 57))
    bottom = Image.new("RGB", (size, size), (10, 14, 20))
    tile = Image.composite(bottom, top, gradient).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((34, 34, 990, 990), radius=218, fill=255)
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    image.paste(tile, (0, 0), mask)

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(
        (58, 58, 966, 966), radius=196, outline=(*accent, 220), width=24
    )
    image = Image.alpha_composite(image, glow.filter(ImageFilter.GaussianBlur(30)))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((42, 42, 982, 982), radius=210, outline=(118, 129, 143, 150), width=8)
    draw.rounded_rectangle((68, 68, 956, 956), radius=184, outline=(*accent, 235), width=14)

    ring_box = (196, 142, 828, 774)
    draw.arc(ring_box, 202, 522, fill=(*accent, 255), width=28)
    cl_font = ImageFont.truetype(str(FONT_ROUNDED), 330)
    draw.text((512, 430), "CL", font=cl_font, anchor="mm", fill=(*accent, 255),
              stroke_width=2, stroke_fill=(255, 255, 255, 90))

    bars = (18, 34, 58, 88, 54, 30, 48, 72, 44, 24)
    start_x = 326
    for index, height in enumerate(bars):
        x = start_x + index * 31
        draw.rounded_rectangle((x, 692 - height // 2, x + 12, 692 + height // 2),
                               radius=6, fill=(*accent, 235))

    draw.rounded_rectangle((214, 792, 810, 800), radius=4, fill=(*accent, 220))
    label_font = fitted_font(label, 720, 82)
    draw.text((512, 866), label, font=label_font, anchor="mm", fill=(244, 247, 250, 255))
    return image


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, (label, color) in VARIANTS.items():
        image = render_variant(label, color)
        image.save(OUTPUT / f"{name}.png", format="PNG", optimize=True)
        image.save(OUTPUT / f"{name}.icns", format="ICNS")

    show_control = OUTPUT / "CL_Audio_Show_Control.png"
    (ROOT / "assets" / "cl_audio_show_control_icon_1024.png").write_bytes(show_control.read_bytes())
    (ROOT / "cl_audio_logo.png").write_bytes(show_control.read_bytes())
    (ROOT / "CL_AUDIO.icns").write_bytes(
        (OUTPUT / "CL_Audio_Show_Control.icns").read_bytes()
    )


if __name__ == "__main__":
    main()
