#!/usr/bin/env python3
"""Generate the color-coded CL application icon family."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "assets" / "cl_audio_show_control_icon_1024.png"
OUTPUT = ROOT / "assets" / "app_icons"

VARIANTS = {
    "CL_Audio_Show_Control": "#D84A4A",
    "CL_Ableton": "#E58A3A",
    "CL_MIDI_Network": "#32B89C",
    "CL_MIDI_RTP_Diagnostic": "#3E9ED6",
    "CL_MIDI_Analyzer": "#3974D8",
    "CL_MIDI_Performance": "#6557C8",
}


def render_variant(base: Image.Image, color: str) -> Image.Image:
    accent = Image.new("RGBA", base.size, (0, 0, 0, 0))
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.rounded_rectangle((58, 58, 966, 966), radius=205, outline=color, width=42)
    glow = glow.filter(ImageFilter.GaussianBlur(28))
    glow.putalpha(glow.getchannel("A").point(lambda value: int(value * 0.42)))
    accent.alpha_composite(glow)

    draw = ImageDraw.Draw(accent)
    draw.rounded_rectangle((70, 70, 954, 954), radius=192, outline=color, width=24)
    draw.rounded_rectangle((185, 81, 839, 117), radius=18, fill=color)
    draw.ellipse((790, 790, 922, 922), fill=color, outline=(255, 255, 255, 225), width=8)
    draw.ellipse((832, 832, 880, 880), fill=(255, 255, 255, 238))
    return Image.alpha_composite(base, accent)


def main() -> None:
    base = Image.open(BASE).convert("RGBA")
    if base.size != (1024, 1024):
        raise SystemExit(f"Dimensions inattendues pour {BASE}: {base.size}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, color in VARIANTS.items():
        image = render_variant(base, color)
        image.save(OUTPUT / f"{name}.png", format="PNG", optimize=True)
        image.save(OUTPUT / f"{name}.icns", format="ICNS")
    # The PyInstaller specification keeps this stable technical filename.
    (ROOT / "CL_AUDIO.icns").write_bytes(
        (OUTPUT / "CL_Audio_Show_Control.icns").read_bytes()
    )


if __name__ == "__main__":
    main()
