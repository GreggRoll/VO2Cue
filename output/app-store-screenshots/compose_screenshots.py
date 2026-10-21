from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
SOURCES = ROOT / "sources"
FINAL = ROOT / "final"
PHONE_OUT = FINAL / "iphone-1242x2688"
PHONE_UPLOAD_OUT = FINAL / "iphone-1206x2622"
PHONE_UPLOAD_SIZE = (1206, 2622)
WATCH_OUT = FINAL / "watch-422x514"
IPAD_OUT = FINAL / "ipad-2064x2752"

FONT_REGULAR = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

WHITE = (250, 250, 252, 255)
MUTED = (204, 210, 221, 255)
ORANGE = (255, 106, 0, 255)
RED = (255, 59, 48, 255)
BLUE = (72, 148, 255, 255)


def font(size: int, rounded: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_ROUNDED if rounded else FONT_REGULAR, size=size)


def cover(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    image = image.convert("RGB")
    scale = max(size[0] / image.width, size[1] / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1])).convert("RGBA")


def make_background(size: tuple[int, int], tint: tuple[int, int, int], crop_bias: int = 0) -> Image.Image:
    texture = Image.open(SOURCES / "energy-background.png").convert("RGB")
    scale = max(size[0] / texture.width, size[1] / texture.height)
    resized = texture.resize((round(texture.width * scale), round(texture.height * scale)), Image.Resampling.LANCZOS)
    left = max(0, min(resized.width - size[0], (resized.width - size[0]) // 2 + crop_bias))
    top = max(0, resized.height - size[1])
    bg = resized.crop((left, top, left + size[0], top + size[1])).convert("RGBA")
    bg = ImageEnhance.Brightness(bg).enhance(0.72)

    overlay = Image.new("RGBA", size, tint + (50,))
    bg = Image.alpha_composite(bg, overlay)

    # Keep headline copy crisp while preserving the generated energy in the lower field.
    shade = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shade)
    for y in range(size[1]):
        alpha = int(205 * max(0, 1 - y / (size[1] * 0.58)))
        draw.line((0, y, size[0], y), fill=(3, 7, 16, alpha))
    return Image.alpha_composite(bg, shade)


def add_headline(
    canvas: Image.Image,
    eyebrow: str,
    headline: str,
    subhead: str,
    *,
    x: int,
    y: int,
    max_width: int,
    headline_size: int,
    subhead_size: int,
    line_gap: int = 10,
) -> int:
    draw = ImageDraw.Draw(canvas)
    eyebrow_font = font(max(26, subhead_size - 10), rounded=True)
    draw.text((x, y), eyebrow, font=eyebrow_font, fill=ORANGE)
    y += eyebrow_font.size + 34

    head_font = font(headline_size, rounded=True)
    for line in headline.split("\n"):
        draw.text((x, y), line, font=head_font, fill=WHITE, stroke_width=1, stroke_fill=(255, 255, 255, 40))
        y += headline_size + line_gap

    y += 18
    sub_font = font(subhead_size)
    words = subhead.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textlength(candidate, font=sub_font) <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    for line in lines:
        draw.text((x, y), line, font=sub_font, fill=MUTED)
        y += subhead_size + 14
    return y


def rounded_paste(
    canvas: Image.Image,
    image: Image.Image,
    box: tuple[int, int, int, int],
    *,
    radius: int,
    border: int = 0,
    shadow: int = 26,
    shadow_alpha: int = 115,
) -> None:
    x, y, w, h = box
    image = image.convert("RGBA").resize((w, h), Image.Resampling.LANCZOS)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w, h), radius=radius, fill=255)

    if shadow:
        shadow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        shadow_mask = Image.new("L", canvas.size, 0)
        ImageDraw.Draw(shadow_mask).rounded_rectangle((x, y + shadow // 2, x + w, y + h + shadow // 2), radius=radius, fill=shadow_alpha)
        shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(shadow))
        shadow_layer.putalpha(shadow_mask)
        canvas.alpha_composite(shadow_layer)

    if border:
        frame = Image.new("RGBA", (w + 2 * border, h + 2 * border), (7, 9, 14, 255))
        frame_mask = Image.new("L", frame.size, 0)
        ImageDraw.Draw(frame_mask).rounded_rectangle((0, 0, frame.width, frame.height), radius=radius + border, fill=255)
        canvas.paste(frame, (x - border, y - border), frame_mask)

    canvas.paste(image, (x, y), mask)


def load_phone(name: str) -> Image.Image:
    return Image.open(SOURCES / "iphone" / name).convert("RGBA")


def load_ipad(name: str) -> Image.Image:
    return Image.open(SOURCES / "ipad" / name).convert("RGBA")


def load_watch(name: str) -> Image.Image:
    return Image.open(SOURCES / "watch" / name).convert("RGBA")


def phone_canvas(tint: tuple[int, int, int], crop_bias: int = 0) -> Image.Image:
    return make_background((1242, 2688), tint, crop_bias)


def add_phone_screen(canvas: Image.Image, source: Image.Image, *, width: int = 870, y: int = 770, x: int | None = None) -> None:
    height = round(width * source.height / source.width)
    if x is None:
        x = (canvas.width - width) // 2
    rounded_paste(canvas, source, (x, y, width, height), radius=78, border=17, shadow=35)


def add_pill(canvas: Image.Image, text: str, x: int, y: int, color: tuple[int, int, int, int]) -> int:
    draw = ImageDraw.Draw(canvas)
    f = font(35, rounded=True)
    text_width = round(draw.textlength(text, font=f))
    width = text_width + 54
    draw.rounded_rectangle((x, y, x + width, y + 70), radius=35, fill=(9, 13, 23, 220), outline=color, width=2)
    draw.text((x + 27, y + 15), text, font=f, fill=WHITE)
    return width


def compose_phones() -> None:
    PHONE_OUT.mkdir(parents=True, exist_ok=True)

    specs = [
        (
            "01-train-without-the-clock.png",
            (42, 4, 0),
            0,
            "APPLE WATCH HEART-RATE GUIDANCE",
            "Find your range.\nOwn your effort.",
            "Live heart rate, a clear range slider and spoken guidance for hard efforts and recovery.",
            "heart-rate-work.png",
        ),
        (
            "02-your-workout-your-way.png",
            (31, 15, 0),
            -90,
            "CUSTOM WORKOUTS",
            "Your workout.\nYour way.",
            "Tune warm-up, work, recovery, rounds and the cues that keep you moving.",
            "profile.png",
        ),
        (
            "03-built-for-your-cardio.png",
            (0, 24, 44),
            80,
            "RUN • SWIM • RIDE • ROW",
            "One coach for\nevery cardio day.",
            "Create profiles for the pool, treadmill, bike and every hard session between.",
            "workouts.png",
        ),
    ]

    for filename, tint, crop_bias, eyebrow, headline, subhead, source_name in specs:
        canvas = phone_canvas(tint, crop_bias)
        add_headline(canvas, eyebrow, headline, subhead, x=84, y=112, max_width=1070, headline_size=108, subhead_size=45)
        add_phone_screen(canvas, load_phone(source_name), width=872, y=785)
        canvas.convert("RGB").save(PHONE_OUT / filename, quality=96)

    # Real simulator UI with representative heart-rate data on both devices.
    canvas = phone_canvas((17, 5, 28), -45)
    add_headline(
        canvas,
        "IPHONE + APPLE WATCH",
        "Every interval.\nEvery heartbeat.",
        "Follow your heart-rate line through hard and recovery cycles, with target guidance on both screens.",
        x=84,
        y=112,
        max_width=1060,
        headline_size=96,
        subhead_size=43,
    )
    # Focus on the complete native graph card, omitting the scrolled status bar
    # and workout controls. Crop only; no UI text or readings are altered.
    phone = load_phone("heart-rate-timeline.png").crop((24, 900, 1182, 1910))
    phone_w = 1074
    phone_h = round(phone_w * phone.height / phone.width)
    rounded_paste(canvas, phone, (84, 800, phone_w, phone_h), radius=45, border=8, shadow=35)

    watch = load_watch("heart-rate-work.png")
    watch_w = 422
    watch_h = round(watch_w * watch.height / watch.width)
    rounded_paste(canvas, watch, (736, 1920, watch_w, watch_h), radius=105, border=14, shadow=42)
    draw = ImageDraw.Draw(canvas)
    draw.text((84, 1920), "ON YOUR WRIST", font=font(31, rounded=True), fill=ORANGE)
    for index, line in enumerate(("Hard efforts.", "Recovery cycles.", "Clear targets.")):
        draw.text((84, 2010 + index * 65), line, font=font(48, rounded=True), fill=WHITE)
    add_pill(canvas, "LIVE BPM", 84, 2270, ORANGE)
    canvas.convert("RGB").save(PHONE_OUT / "04-apple-watch-parity.png", quality=96)

    # Progress and privacy in a single closing promise.
    canvas = phone_canvas((0, 25, 28), 25)
    add_headline(
        canvas,
        "PRIVATE BY DEFAULT",
        "Progress that\nstays yours.",
        "Weekly goals, actual active minutes, and eight weeks of training. No account, ads or tracking.",
        x=84,
        y=112,
        max_width=1060,
        headline_size=103,
        subhead_size=44,
    )
    x = 84
    for label, color in [("NO ACCOUNT", BLUE), ("NO ADS", ORANGE), ("NO TRACKING", RED)]:
        x += add_pill(canvas, label, x, 665, color) + 18
    add_phone_screen(canvas, load_phone("progress.png"), width=870, y=800)
    canvas.convert("RGB").save(PHONE_OUT / "05-private-progress.png", quality=96)

    canvas = phone_canvas((31, 15, 0), -50)
    add_headline(
        canvas,
        "HOME SCREEN WIDGETS",
        "Your goal.\nOne tap closer.",
        "See your weekly progress. Start your next workout right from the medium widget.",
        x=84, y=112, max_width=1070, headline_size=108, subhead_size=45,
    )
    small = load_widget("small")
    medium = load_widget("medium")
    rounded_paste(canvas, small, (84, 780, 485, 485), radius=105, shadow=35)
    draw = ImageDraw.Draw(canvas)
    draw.text((620, 850), "SMALL", font=font(31, rounded=True), fill=ORANGE)
    draw.text((620, 914), "Your weekly", font=font(45, rounded=True), fill=WHITE)
    draw.text((620, 974), "effort, at a", font=font(45, rounded=True), fill=WHITE)
    draw.text((620, 1034), "glance.", font=font(45, rounded=True), fill=WHITE)
    draw.text((84, 1390), "MEDIUM • READY TO MOVE", font=font(31, rounded=True), fill=ORANGE)
    rounded_paste(canvas, medium, (84, 1480, 1074, 505), radius=112, shadow=35)
    rounded_paste(canvas, load_widget("complete"), (84, 2130, 290, 290), radius=65, shadow=25)
    draw.text((420, 2190), "Celebrate a goal met.", font=font(43, rounded=True), fill=WHITE)
    draw.text((420, 2270), "Start fresh each week.", font=font(40), fill=MUTED)
    canvas.convert("RGB").save(PHONE_OUT / "06-weekly-goal-widgets.png", quality=96)


def load_widget(size: str) -> Image.Image:
    # Crop the real widget from its native 1206 × 2622 Home Screen capture.
    # Keep all UI pixels and text; the compositor masks the rounded corners.
    source = load_phone(f"widget-{size}-home.png")
    if source.size != (1206, 2622):
        raise ValueError(f"Unexpected widget capture dimensions: {source.size}")
    box = (79, 872, 1128, 1365) if size == "medium" else (635, 872, 1128, 1365)
    return source.crop(box)


def export_web_assets() -> None:
    assets = ROOT.parents[1] / "docs" / "demo" / "assets"
    for name in ("workouts", "progress"):
        screen = load_phone(f"{name}.png")
        screen.resize((600, round(600 * screen.height / screen.width)), Image.Resampling.LANCZOS).convert("RGB").save(assets / f"{name}.jpg", quality=88, optimize=True)
    for size in ("small", "medium", "complete"):
        widget = load_widget(size)
        mask = Image.new("L", widget.size)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, widget.width, widget.height), radius=110, fill=255)
        widget.putalpha(mask)
        widget.save(assets / f"widget-{size}.png", optimize=True)


def ipad_canvas(tint: tuple[int, int, int], crop_bias: int = 0) -> Image.Image:
    return make_background((2064, 2752), tint, crop_bias)


def add_ipad_screen(
    canvas: Image.Image,
    source: Image.Image,
    *,
    width: int,
    y: int,
    crop_height: int | None = None,
) -> None:
    if crop_height is not None:
        source = source.crop((0, 0, source.width, min(crop_height, source.height)))
    height = round(width * source.height / source.width)
    x = (canvas.width - width) // 2
    rounded_paste(canvas, source, (x, y, width, height), radius=62, border=16, shadow=42)


def compose_ipads() -> None:
    IPAD_OUT.mkdir(parents=True, exist_ok=True)
    specs = [
        (
            "01-interval-command-center.png",
            (32, 11, 0),
            "WORKOUT LIBRARY",
            "Your interval command center.",
            "Build and organize sessions for running, swimming, cycling, rowing and HIIT.",
            "workouts.png",
            1780,
            980,
            1500,
        ),
        (
            "02-big-clear-live-timer.png",
            (42, 0, 0),
            "LIVE WORKOUT",
            "Big, clear, ready for hard efforts.",
            "The live timer makes every phase effortless to follow—even across the room.",
            "runtime-sprint.png",
            1480,
            720,
            None,
        ),
        (
            "03-momentum-you-can-measure.png",
            (0, 24, 40),
            "LOCAL HISTORY",
            "Momentum you can measure.",
            "See completed sessions and total active minutes, privately on your device.",
            "history.png",
            1780,
            980,
            1600,
        ),
    ]

    for filename, tint, eyebrow, headline, subhead, source_name, width, y, crop_height in specs:
        canvas = ipad_canvas(tint)
        add_headline(
            canvas,
            eyebrow,
            headline,
            subhead,
            x=150,
            y=120,
            max_width=1760,
            headline_size=126,
            subhead_size=55,
            line_gap=14,
        )
        add_ipad_screen(canvas, load_ipad(source_name), width=width, y=y, crop_height=crop_height)
        canvas.convert("RGB").save(IPAD_OUT / filename, quality=96)


def compose_watch() -> None:
    WATCH_OUT.mkdir(parents=True, exist_ok=True)
    mapping = {
        "01-heart-rate-hard.png": "heart-rate-work.png",
        "02-heart-rate-recovery.png": "heart-rate-recovery.png",
        "03-heart-rate-timeline.png": "heart-rate-timeline.png",
    }
    for retired in ("01-workout-library.png", "02-live-interval.png", "03-workout-controls.png"):
        (WATCH_OUT / retired).unlink(missing_ok=True)
    for destination, source in mapping.items():
        image = load_watch(source)
        if image.size != (422, 514):
            raise ValueError(f"Watch captures must be native 422 × 514: {source} is {image.size}")
        image.convert("RGB").save(WATCH_OUT / destination)


def validate(paths: Iterable[Path], size: tuple[int, int]) -> None:
    for path in paths:
        with Image.open(path) as image:
            if image.size != size:
                raise ValueError(f"{path}: expected {size}, got {image.size}")


def export_phone_uploads() -> None:
    """Export the six slides for the iPhone 6.1/6.3-inch upload slot."""
    PHONE_UPLOAD_OUT.mkdir(parents=True, exist_ok=True)
    sources = sorted(PHONE_OUT.glob("*.png"))
    if len(sources) != 6:
        raise ValueError(f"Expected six iPhone screenshots, found {len(sources)}")
    for path in sources:
        with Image.open(path) as source:
            image = source.convert("RGB")
            # Scale the full composition uniformly, extending only the tiny
            # background margin caused by the different target aspect ratio.
            scale = min(PHONE_UPLOAD_SIZE[0] / image.width, PHONE_UPLOAD_SIZE[1] / image.height)
            artwork = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
            canvas = cover(image, PHONE_UPLOAD_SIZE).convert("RGB")
            canvas.paste(artwork, ((canvas.width - artwork.width) // 2, (canvas.height - artwork.height) // 2))
            canvas.save(PHONE_UPLOAD_OUT / path.name, optimize=True)
    validate(PHONE_UPLOAD_OUT.glob("*.png"), PHONE_UPLOAD_SIZE)
    with ZipFile(ROOT / "vo2cue-iphone-widgets.zip", "w", compression=ZIP_DEFLATED) as archive:
        for path in sorted(PHONE_UPLOAD_OUT.glob("*.png")):
            archive.write(path, arcname=f"vo2cue-iphone-widgets/{path.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Compose the canonical App Store screenshot sets.")
    parser.add_argument("--platforms", nargs="+", choices=("iphone", "watch", "ipad", "web"),
                        default=("iphone", "watch", "ipad", "web"))
    platforms = parser.parse_args().platforms
    if "iphone" in platforms:
        compose_phones()
        export_phone_uploads()
        validate(PHONE_OUT.glob("*.png"), (1242, 2688))
    if "watch" in platforms:
        compose_watch()
        validate(WATCH_OUT.glob("*.png"), (422, 514))
    if "ipad" in platforms:
        compose_ipads()
        validate(IPAD_OUT.glob("*.png"), (2064, 2752))
    if "web" in platforms:
        export_web_assets()


if __name__ == "__main__":
    main()
