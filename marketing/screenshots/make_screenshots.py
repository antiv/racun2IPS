#!/usr/bin/env python3
"""Pravi store screenshot-ove sa natpisima od sirovih snimaka ekrana.

Natpisi su ranking signal, ne ukras: Apple od juna 2025. OCR-uje tekst sa
prva tri screenshot-a. Zato je redosled fiksiran i najvažniji rezultat
(generisani IPS QR kod) ide prvi — to je primarna funkcionalnost aplikacije.

Upotreba:
    python3 make_screenshots.py                 # svi jezici, obe platforme
    python3 make_screenshots.py --locale sr
    python3 make_screenshots.py --platform ios

Ulaz:  marketing/screenshots/raw/<slug>.png
Izlaz: marketing/screenshots/out/<platform>/<locale>/<n>-<slug>.png

Sirovi snimci se imenuju po slug-u iz SLIDES: result, scan, saved, share.
Slajd "privacy" nema snimak ekrana — generiše se iz ikonice aplikacije.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
OUT = ROOT / "out"
ICON = ROOT.parent.parent / "assets" / "icon" / "appstore.png"

# --- Brend (racun2IPS Emerald paleta) ------------------------------------
# Smaragdna nijansa iz lib/theme.dart (emerald600: #059669);
# donja je tamnija varijanta za vertikalni gradijent podloge.
EMERALD = (0x05, 0x96, 0x69)
DEEP_EMERALD = (0x04, 0x4E, 0x3A)
INK = (0xFF, 0xFF, 0xFF)

# --- Dimenzije -----------------------------------------------------------
# iOS: 6.9" je format koji App Store Connect danas traži za iPhone.
# Play: 9:16 unutar dozvoljenog opsega, 1080x1920 je siguran izbor.
PLATFORMS = {
    "ios": (1320, 2868),
    "play": (1080, 1920),
}

# --- Slajdovi ------------------------------------------------------------
# Redosled slajdova: prva tri se vide direktno u pretrazi.
SLIDES = [
    "result",   # IPS QR kod + očitani podaci (glavni rezultat)
    "scan",     # Skeniranje uplatnice kamerom/galerijom
    "privacy",  # tekstualni slajd o privatnosti i lokalnom radu bez naloga
    "saved",    # Sačuvani kodovi za uplate i prilive
    "share",    # Deljenje QR koda i izvoz/uvoz
]

CAPTIONS = {
    "sr": {
        "result": "Skeniraj račun i plati u sekundi\nAutomatski IPS QR kod za m-banking",
        "scan": "AI sama čita uplatnicu\nIznos, žiro račun i poziv na broj",
        "privacy": "Bez registracije.\nBez pretplate.\nVaši podaci ostaju privatni.",
        "saved": "Sačuvani kodovi za redovne račune\nNapravite i svoj kod za uplate",
        "share": "Podelite QR kod ili izvezite bazu\nBrzo slanje i rezervna kopija",
    },
    "en": {
        "result": "Scan bills & pay in seconds\nInstant NBS IPS QR code for m-banking",
        "scan": "AI extracts payment details\nAmount, recipient, account & reference",
        "privacy": "No registration.\nNo subscription.\n100% private data.",
        "saved": "Save recurring bill codes\nGenerate your own QR to get paid",
        "share": "Share QR code or backup codes\nEasy sharing and offline export",
    },
}

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/System/Library/Fonts/HelveticaNeue-Bold.ttf",
]


def load_font(size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    raise SystemExit(
        "Nije nađen nijedan font iz FONT_CANDIDATES — dopuni listu putanjom "
        "do .ttf fajla koji podržava dijakritike."
    )


def gradient(size: tuple[int, int]) -> Image.Image:
    """Vertikalni gradijent u brend bojama (Emerald -> Deep Emerald)."""
    w, h = size
    base = Image.new("RGB", (1, h))
    px = base.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        px[0, y] = tuple(
            round(EMERALD[i] + (DEEP_EMERALD[i] - EMERALD[i]) * t) for i in range(3)
        )
    return base.resize(size, Image.LANCZOS)


def wrap(draw: ImageDraw.ImageDraw, text: str, font, max_w: int) -> list[str]:
    """Prelama tekst na zadatu širinu, uz poštovanje ručnih \\n."""
    lines: list[str] = []
    for paragraph in text.split("\n"):
        words, current = paragraph.split(), ""
        for word in words:
            trial = f"{current} {word}".strip()
            if draw.textlength(trial, font=font) <= max_w or not current:
                current = trial
            else:
                lines.append(current)
                current = word
        lines.append(current)
    return lines


def rounded(img: Image.Image, radius: int) -> Image.Image:
    """Zaobljeni uglovi — spriječava da snimak ekrana izgleda zalepljeno."""
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (img.size[0] - 1, img.size[1] - 1)], radius=radius, fill=255
    )
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def shadow_behind(canvas: Image.Image, box: tuple[int, int, int, int], radius: int):
    """Meka senka ispod uređaja za odvajanje od pozadine."""
    x, y, w, h = box
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        [(x, y + h // 60), (x + w, y + h + h // 60)], radius=radius, fill=(0, 0, 0, 90)
    )
    layer = layer.filter(ImageFilter.GaussianBlur(canvas.size[0] // 45))
    canvas.alpha_composite(layer)


def build_slide(slug: str, caption: str, size: tuple[int, int]) -> Image.Image:
    w, h = size
    canvas = gradient(size).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    margin = round(w * 0.08)
    font = load_font(round(w * 0.062))
    line_h = round(font.size * 1.22)

    lines = wrap(draw, caption, font, w - 2 * margin)
    y = round(h * 0.055)
    for line in lines:
        tw = draw.textlength(line, font=font)
        draw.text(((w - tw) / 2, y), line, font=font, fill=INK)
        y += line_h

    top_of_device = y + round(h * 0.035)
    avail_h = h - top_of_device - round(h * 0.05)
    avail_w = w - 2 * margin

    source = RAW / f"{slug}.png"
    if slug == "privacy" or not source.exists():
        # Tekstualni slajd: samo ikonica, bez snimka ekrana.
        if ICON.exists():
            icon = Image.open(ICON).convert("RGBA")
            side = min(avail_w, avail_h) // 2
            icon = icon.resize((side, side), Image.LANCZOS)
            icon_radius = round(side * 0.22)
            icon = rounded(icon, icon_radius)
            canvas.alpha_composite(
                icon, ((w - side) // 2, top_of_device + (avail_h - side) // 2)
            )
        return canvas.convert("RGB")

    shot = Image.open(source).convert("RGB")
    scale = min(avail_w / shot.width, avail_h / shot.height)
    new = (round(shot.width * scale), round(shot.height * scale))
    shot = shot.resize(new, Image.LANCZOS)
    radius = round(new[0] * 0.055)
    x = (w - new[0]) // 2

    shadow_behind(canvas, (x, top_of_device, new[0], new[1]), radius)
    canvas.alpha_composite(rounded(shot, radius), (x, top_of_device))
    return canvas.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--locale", choices=sorted(CAPTIONS), action="append")
    ap.add_argument("--platform", choices=sorted(PLATFORMS), action="append")
    args = ap.parse_args()

    locales = args.locale or sorted(CAPTIONS)
    platforms = args.platform or sorted(PLATFORMS)

    if not RAW.exists() or not any(RAW.glob("*.png")):
        print(f"Nema sirovih snimaka u {RAW}", file=sys.stderr)
        print(
            "Ubaci snimke ekrana imenovane: "
            + ", ".join(f"{s}.png" for s in SLIDES if s != "privacy"),
            file=sys.stderr,
        )
        return 1

    missing = [s for s in SLIDES if s != "privacy" and not (RAW / f"{s}.png").exists()]
    if missing:
        print(f"Upozorenje: nedostaju {', '.join(missing)} — ti slajdovi se preskaču.")

    total = 0
    for platform in platforms:
        size = PLATFORMS[platform]
        for locale in locales:
            dest = OUT / platform / locale
            dest.mkdir(parents=True, exist_ok=True)
            n = 0
            for slug in SLIDES:
                if slug != "privacy" and not (RAW / f"{slug}.png").exists():
                    continue
                n += 1
                img = build_slide(slug, CAPTIONS[locale][slug], size)
                path = dest / f"{n}-{slug}.png"
                img.save(path, "PNG", optimize=True)
                total += 1
            print(f"{platform}/{locale}: {n} slika -> {dest}")

    print(f"\nUkupno {total} slika.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
