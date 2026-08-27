#!/usr/bin/env python3
"""Generate the Overlay's branding PNGs from the brand master.

Source of truth: ../meta/brand/logo.svg (the Aity mark; meta and ios must
sit side by side, as the workspace AGENTS.md prescribes). The generated
PNGs are COMMITTED - this script only runs again when the brand master
changes. Never hand-edit a generated asset (meta/brand/README.md).

Outputs (dimensions mirror the Pin's default assets in
ownCloud/Resources/Theming/com.owncloud.ios-app/):

  overlay/common/.../branding-assets/
    branding-logo.png                   2048x2048 opaque white, mark centred
    branding-background.png             1280x1920 flat white
    branding-splashscreen-logo.png      2048x2048 opaque white, mark centred
    branding-splashscreen-background.png  1x1 flat white (stretched at runtime)
    branding-sidebar-link-icon.png      2048x2048 transparent, mark centred
  overlay/production/.../branding-assets/
    branding-icon.png                   1024x1024 opaque white, mark centred
                                        (the app-icon source; fastlane's
                                        appicon plugin slices it)
  overlay/staging/.../branding-assets/
    branding-icon.png                   same, plus the STG corner badge

Tooling: python3 with cairosvg + Pillow (pip install cairosvg pillow), the
pure-Linux equivalent of the rsvg-convert/ImageMagick pipeline upstream
uses for its own badge. The STG badge text needs a bold TTF; DejaVu Sans
Bold (every mainstream distro) is looked up first.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

try:
    import cairosvg
    from PIL import Image, ImageDraw, ImageFont
except ImportError as exc:  # pragma: no cover
    print(
        f"generate-assets: missing dependency ({exc}); run: pip install cairosvg pillow",
        file=sys.stderr,
    )
    sys.exit(1)

REPO_ROOT = Path(__file__).resolve().parent.parent
LOGO_SVG = REPO_ROOT.parent / "meta" / "brand" / "logo.svg"

COMMON = REPO_ROOT / "overlay/common/ownCloud/Resources/Theming/branding-assets"
PRODUCTION = REPO_ROOT / "overlay/production/ownCloud/Resources/Theming/branding-assets"
STAGING = REPO_ROOT / "overlay/staging/ownCloud/Resources/Theming/branding-assets"

BRAND_RED = (184, 8, 24, 255)  # red-600 #b80818, meta/brand/README.md
WHITE = (255, 255, 255, 255)

BADGE_FONTS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
]


def render_mark(size: int) -> Image.Image:
    """Rasterise the brand mark to a size x size RGBA image."""
    png_bytes = cairosvg.svg2png(
        url=str(LOGO_SVG), output_width=size, output_height=size
    )
    return Image.open(io.BytesIO(png_bytes)).convert("RGBA")


def mark_on_canvas(canvas_size: int, mark_ratio: float, background=None) -> Image.Image:
    """The mark centred on a square canvas; transparent unless background given."""
    canvas = Image.new("RGBA", (canvas_size, canvas_size), background or (0, 0, 0, 0))
    mark_size = int(canvas_size * mark_ratio)
    mark = render_mark(mark_size)
    offset = (canvas_size - mark_size) // 2
    canvas.paste(mark, (offset, offset), mark)
    return canvas


def badge_font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in BADGE_FONTS:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    print(
        "generate-assets: no bold TTF found for the STG badge "
        f"(looked at {BADGE_FONTS})",
        file=sys.stderr,
    )
    sys.exit(1)


def staging_icon(size: int) -> Image.Image:
    """The staging app icon: mark above a brand-red STG band.

    A band (not a tiny corner pip) so it survives every icon size down to
    the 29pt settings icon - the point of the badge is telling the two
    Environment builds apart on one homescreen (meta/brand/README.md).
    The mark is scaled and re-centred into the area above the band so the
    band never covers the wordmark.
    """
    icon = Image.new("RGBA", (size, size), WHITE)
    band_height = int(size * 0.28)
    free_height = size - band_height

    mark_size = int(size * 0.56)
    mark = render_mark(mark_size)
    icon.paste(
        mark,
        ((size - mark_size) // 2, (free_height - mark_size) // 2),
        mark,
    )

    width, height = icon.size
    draw = ImageDraw.Draw(icon)
    draw.rectangle([(0, height - band_height), (width, height)], fill=BRAND_RED)

    font = badge_font(int(band_height * 0.62))
    text = "STG"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    draw.text(
        (
            (width - text_w) / 2 - bbox[0],
            height - band_height + (band_height - text_h) / 2 - bbox[1],
        ),
        text,
        font=font,
        fill=WHITE,
    )
    return icon


def save(image: Image.Image, path: Path, opaque: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if opaque:
        image = image.convert("RGB")  # app-icon sources must not carry alpha
    image.save(path, format="PNG", optimize=True)
    print(f"generate-assets: wrote {path.relative_to(REPO_ROOT)} {image.size}")


def main() -> None:
    if not LOGO_SVG.exists():
        print(f"generate-assets: brand master not found at {LOGO_SVG}", file=sys.stderr)
        sys.exit(1)

    # Login / brand view and splashscreen logos: generous whitespace, the
    # app scales them into its BrandView. OPAQUE WHITE, not transparent
    # (decision 2026-08-27): a transparent mark inherits whatever the theme
    # puts behind it, which is how the logo went missing on a surface that
    # is not white. The sidebar link icon stays transparent deliberately -
    # it is composited onto the app's own accent bar, where a white square
    # would be the defect rather than the fix.
    logo = mark_on_canvas(2048, 0.72, background=WHITE)
    save(logo, COMMON / "branding-logo.png", opaque=True)
    save(logo, COMMON / "branding-splashscreen-logo.png", opaque=True)
    save(mark_on_canvas(2048, 0.72), COMMON / "branding-sidebar-link-icon.png")

    background = Image.new("RGBA", (1280, 1920), WHITE)
    save(background, COMMON / "branding-background.png", opaque=True)
    save(Image.new("RGBA", (1, 1), WHITE), COMMON / "branding-splashscreen-background.png", opaque=True)

    # App icon source: opaque, mark at ~64% on white.
    save(mark_on_canvas(1024, 0.64, background=WHITE), PRODUCTION / "branding-icon.png", opaque=True)
    save(staging_icon(1024), STAGING / "branding-icon.png", opaque=True)


if __name__ == "__main__":
    main()
