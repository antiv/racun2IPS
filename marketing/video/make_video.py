#!/usr/bin/env python3
"""Promo video (YouTube Short, 1080x1920) iz dizajna ekrana, bez snimanja telefona.

Ekrani se renderuju istim HTML-om kao store screenshot-ovi
(marketing/screenshots/render_raw.py), uz kameru sa demo uplatnicom i ekran
obrade. Svaki ekran postaje slajd u stilu store slika (podloga, natpis,
zaobljen „telefon“), a ffmpeg ih spaja sa blagim zumiranjem i prelazima.
Video se završava na QR kodu — bankarske aplikacije se ne prikazuju.

    python3 marketing/video/make_video.py              # -> marketing/video/out/invoice2ips-sr.mp4
    python3 marketing/video/make_video.py --locale en

Potrebni su Google Chrome, ffmpeg i Pillow; demo QR kodovi su u
marketing/screenshots/design/qr.json.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "marketing/screenshots"))

import make_screenshots as ms  # noqa: E402
import render_raw as rr  # noqa: E402

SIZE = (1080, 1920)
FPS = 30
FADE = 0.45  # trajanje prelaza u sekundama
WORK = ROOT / "build/video"

rr.ICON.update({"bot": 57787, "sparkles": 58386, "alert": 57463, "zap_off": 57781})

TEXT = {
    "sr": {
        "tagline": "Od računa do IPS QR koda\nza nekoliko sekundi",
        "home": "Slikajte račun, otvorite PDF\nili ga podelite iz druge aplikacije",
        "camera": "Uperite kameru u račun",
        "processing": "Podaci se čitaju na telefonu,\nAI samo kao rezerva",
        "result": "IPS QR kod je spreman\nza vašu m-banking aplikaciju",
        "saved": "Sačuvajte redovne račune",
        "share": "Sledeći put — jednim dodirom",
        "end": "Skenirajte u aplikaciji\nsvoje banke",
        "platforms": "Android  ·  iPhone  ·  iPad",
        "analyzing": "Analiziranje računa",
        "step": "Provera QR koda i teksta...",
        "disclaimer": "Napomena: Uvek proverite pročitane podatke! AI ponekad može da pogreši.",
        "slip": {"title": "NALOG ZA UPLATU", "payer": "Platilac", "purpose": "Svrha uplate",
                 "recipient": "Primalac", "code": "Šifra plaćanja", "currency": "Valuta",
                 "amount": "Iznos", "account": "Račun primaoca", "model": "Model",
                 "reference": "Poziv na broj", "purpose_value": "Račun za električnu energiju"},
    },
    "en": {
        "tagline": "From a bill to an IPS QR code\nin seconds",
        "home": "Snap a bill, open a PDF\nor share it from another app",
        "camera": "Point the camera at the bill",
        "processing": "Read on your phone,\nAI only as a fallback",
        "result": "Your IPS QR code is ready\nfor your banking app",
        "saved": "Save your recurring bills",
        "share": "Next time — just one tap",
        "end": "Scan it in your\nbank's app",
        "platforms": "Android  ·  iPhone  ·  iPad",
        "analyzing": "Analyzing Invoice",
        "step": "Checking QR code & text...",
        "disclaimer": "Note: Always verify the extracted data! AI can sometimes make mistakes.",
        "slip": {"title": "NALOG ZA UPLATU", "payer": "Platilac", "purpose": "Svrha uplate",
                 "recipient": "Primalac", "code": "Šifra plaćanja", "currency": "Valuta",
                 "amount": "Iznos", "account": "Račun primaoca", "model": "Model",
                 "reference": "Poziv na broj", "purpose_value": "Račun za električnu energiju"},
    },
}


def paper_slip(s) -> str:
    """Demo uplatnica (izmišljeni podaci) — ono što kamera „vidi“."""
    box = lambda label, value, w="100%", big=False: (
        f'<div style="width:{w}"><div style="font-size:7px;color:#57534E">{label}</div>'
        f'<div style="border:1px solid #78716C;padding:4px 5px;font-size:{11 if big else 9}px;'
        f'font-weight:{700 if big else 500};min-height:18px;color:#1C1917">{value}</div></div>')
    return f"""<div style="width:360px;background:#FDFCF9;border-radius:3px;padding:12px 14px;
font-family:Arial,sans-serif;box-shadow:0 18px 40px rgba(0,0,0,.55)">
  <div style="font-size:12px;font-weight:700;letter-spacing:.5px;color:#1C1917;margin-bottom:8px">{s["title"]}</div>
  <div style="display:flex;gap:12px">
    <div style="flex:1;display:flex;flex-direction:column;gap:6px">
      {box(s["payer"], "Petar Petrović<br>Glavna 12, Beograd")}
      {box(s["purpose"], s["purpose_value"])}
      {box(s["recipient"], "ELEKTRO SNABDEVANJE DOO")}
    </div>
    <div style="flex:1.15;display:flex;flex-direction:column;gap:6px">
      <div style="display:flex;gap:5px">{box(s["code"], "189", "30%")}{box(s["currency"], "RSD", "28%")}{box(s["amount"], "4.820,00", "42%", True)}</div>
      {box(s["account"], "160-0000000012345-95", big=True)}
      <div style="display:flex;gap:5px">{box(s["model"], "97", "24%")}{box(s["reference"], "92-1234567890", "76%", True)}</div>
    </div>
  </div>
</div>"""


def camera(t) -> str:
    white_bars = ('<style>.status .sig b{background:#fff}.status .bat{border-color:#fff}'
                  '.status .bat b{background:#fff}</style>')
    round_btn = lambda icon: (f'<div class="tile" style="width:52px;height:52px;border-radius:50%;'
                              f'background:rgba(255,255,255,.16)">{rr.i(icon, 22, "#fff")}</div>')
    return f"""{white_bars}<div class="screen" style="background:#0B0B0C">
<div style="position:absolute;inset:0;background:radial-gradient(circle at 50% 42%,#4a4038,#1d1915 75%)"></div>
<div style="position:absolute;left:50%;top:44%;transform:translate(-50%,-50%) rotate(-3deg) scale(1.08)">{paper_slip(t["slip"])}</div>
<div style="position:relative;color:#fff">{rr.status_bar("iphone", t)}</div>
<div style="position:absolute;left:26px;right:26px;top:110px;bottom:180px;border:2px dashed rgba(255,255,255,.85);border-radius:16px">
  <div style="position:absolute;left:12px;right:12px;top:46%;height:2px;border-radius:2px;
  background:linear-gradient(90deg,transparent,#34D399,transparent);box-shadow:0 0 14px 2px rgba(52,211,153,.4)"></div>
</div>
<div style="position:absolute;left:0;right:0;bottom:46px;display:flex;align-items:center;justify-content:center;gap:34px">
  {round_btn("back")}
  <div style="width:78px;height:78px;border-radius:50%;background:#fff;box-shadow:0 0 0 6px rgba(255,255,255,.25);
  display:flex;align-items:center;justify-content:center"><div style="width:62px;height:62px;border-radius:50%;border:4px solid #1C1917"></div></div>
  {round_btn("zap_off")}
</div></div>"""


def processing(t) -> str:
    header = f"""<div style="display:flex;align-items:center;gap:8px;padding:10px 16px 6px 8px">
  <div class="tile" style="width:44px;height:44px">{rr.i("back", 22, "#292524")}</div>
  <div style="font-size:18px;font-weight:700;letter-spacing:-.4px"><span style="color:#059669">Invoice</span>2IPS</div>
</div>"""
    thumb = (f'<div style="width:128px;height:128px;border-radius:20px;border:4px solid #fff;overflow:hidden;'
             f'position:relative;box-shadow:0 6px 16px rgba(0,0,0,.18);background:#3a332c">'
             f'<div style="position:absolute;left:50%;top:50%;transform:translate(-50%,-50%) scale(.34)">'
             f'{paper_slip(t["slip"])}</div>'
             f'<div style="position:absolute;left:0;right:0;top:55%;height:28px;'
             f'background:linear-gradient(transparent,rgba(52,211,153,.55),transparent)"></div></div>')
    body = f"""{header}
<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:0 24px 60px">
  <div style="position:relative;width:132px;height:132px;display:flex;align-items:center;justify-content:center">
    <div style="position:absolute;width:122px;height:122px;border-radius:50%;background:rgba(52,211,153,.18)"></div>
    <div style="position:absolute;width:100px;height:100px;border-radius:50%;background:#ECFDF5;box-shadow:0 0 0 1px #D1FAE5"></div>
    <div style="position:relative">{rr.i("bot", 52, "#059669")}</div>
    <div style="position:absolute;right:16px;top:14px">{rr.i("sparkles", 22, "#FBBF24")}</div>
  </div>
  <div style="margin-top:30px;font-size:21px;font-weight:700">{t["analyzing"]}</div>
  <div style="margin-top:8px;font-size:14px;color:#78716C">{t["step"]}</div>
  <div style="margin-top:30px;width:100%;display:flex;gap:11px;padding:14px 16px;border-radius:18px;
  background:#FFFBEB;border:1px solid #FEF3C7;font-size:12.5px;line-height:1.6;font-weight:500;color:#B45309">
    <span style="flex:none">{rr.i("alert", 20, "#F59E0B")}</span>{t["disclaimer"]}</div>
  <div style="margin-top:30px">{thumb}</div>
</div>"""
    return rr.frame(body, "iphone", t)


def slide(caption: str, shot: Path) -> Image.Image:
    """Isti raspored kao store slajd: natpis gore, zaobljen ekran ispod."""
    w, h = SIZE
    canvas = ms.gradient(SIZE).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    margin = round(w * 0.08)
    font = ms.load_font(round(w * 0.062))
    y = round(h * 0.055)
    for line in ms.wrap(draw, caption, font, w - 2 * margin):
        draw.text(((w - draw.textlength(line, font=font)) / 2, y), line, font=font, fill=ms.INK)
        y += round(font.size * 1.22)
    top = y + round(h * 0.035)
    avail_h, avail_w = h - top - round(h * 0.05), w - 2 * margin
    img = Image.open(shot).convert("RGB")
    scale = min(avail_w / img.width, avail_h / img.height)
    new = (round(img.width * scale), round(img.height * scale))
    img = img.resize(new, Image.LANCZOS)
    radius = round(new[0] * 0.055)
    x = (w - new[0]) // 2
    ms.shadow_behind(canvas, (x, top, new[0], new[1]), radius)
    canvas.alpha_composite(ms.rounded(img, radius), (x, top))
    return canvas.convert("RGB")


def centered(draw, text, font, y, fill=ms.INK) -> int:
    for line in text.split("\n"):
        draw.text(((SIZE[0] - draw.textlength(line, font=font)) / 2, y), line, font=font, fill=fill)
        y += round(font.size * 1.25)
    return y


def intro(t) -> Image.Image:
    canvas = ms.gradient(SIZE).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    side = 300
    icon = ms.rounded(Image.open(ms.ICON).convert("RGBA").resize((side, side), Image.LANCZOS), 66)
    top = 560
    ms.shadow_behind(canvas, ((SIZE[0] - side) // 2, top, side, side), 66)
    canvas.alpha_composite(icon, ((SIZE[0] - side) // 2, top))
    y = centered(draw, "Invoice2IPS", ms.load_font(100), top + side + 70)
    centered(draw, t["tagline"], ms.load_font(56), y + 30, fill=(220, 252, 231))
    return canvas.convert("RGB")


def qr_image(svg: str, size: int) -> Image.Image:
    n = int(re.search(r'viewBox="0 0 (\d+)', svg).group(1))
    quiet = 3
    cell = size / (n + 2 * quiet)
    img = Image.new("RGB", (size, size), "white")
    draw = ImageDraw.Draw(img)
    for x, y in re.findall(r"M(\d+) (\d+)h1v1h-1z", svg):
        x0, y0 = (int(x) + quiet) * cell, (int(y) + quiet) * cell
        draw.rectangle([x0, y0, x0 + cell, y0 + cell], fill=(0x1A, 0x1B, 0x19))
    return img


def end_card(t, qr_svg: str) -> Image.Image:
    canvas = ms.gradient(SIZE).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    side = 560
    top = 360
    card = ms.rounded(qr_image(qr_svg, side).convert("RGBA"), 48)
    ms.shadow_behind(canvas, ((SIZE[0] - side) // 2, top, side, side), 48)
    canvas.alpha_composite(card, ((SIZE[0] - side) // 2, top))
    y = centered(draw, t["end"], ms.load_font(78), top + side + 90)
    y = centered(draw, "Invoice2IPS", ms.load_font(64), y + 70)
    centered(draw, t["platforms"], ms.load_font(42), y + 14, fill=(220, 252, 231))
    return canvas.convert("RGB")


def build_video(slides: list[tuple[Path, float, str]], out: Path) -> None:
    """Svaki slajd: blago zumiranje; između slajdova xfade prelaz."""
    cmd = ["ffmpeg", "-y", "-loglevel", "error"]
    for path, _, _ in slides:
        cmd += ["-i", str(path)]
    parts = []
    for k, (_, duration, _) in enumerate(slides):
        frames = round(duration * FPS)
        parts.append(
            f"[{k}:v]scale=2160:-2,zoompan=z='1+0.035*on/{frames}':x='iw/2-(iw/zoom/2)':"
            f"y='ih/2-(ih/zoom/2)':d={frames}:s={SIZE[0]}x{SIZE[1]}:fps={FPS},setsar=1,format=yuv420p[v{k}]")
    last, offset = "v0", 0.0
    for k in range(1, len(slides)):
        offset += slides[k - 1][1] - FADE
        parts.append(f"[{last}][v{k}]xfade=transition={slides[k][2]}:duration={FADE}:"
                     f"offset={offset:.3f}[x{k}]")
        last = f"x{k}"
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd += ["-filter_complex", ";".join(parts), "-map", f"[{last}]", "-c:v", "libx264",
            "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            str(out)]
    subprocess.run(cmd, check=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--locale", choices=sorted(TEXT), default="sr")
    args = ap.parse_args()
    t, ui = TEXT[args.locale], rr.T[args.locale]
    qr = json.loads((ROOT / "marketing/screenshots/design/qr.json").read_text())
    work = WORK / args.locale
    work.mkdir(parents=True, exist_ok=True)

    screens = {
        "home": rr.home(ui, "iphone"),
        "camera": camera({**ui, **t}),
        "processing": processing({**ui, **t}),
        "result": rr.result(ui, qr["result"], "iphone"),
        "saved": rr.saved(ui, "iphone"),
        "share": rr.share(ui, qr["share"], "iphone"),
    }
    for name, html in screens.items():
        rr.render(html, work / f"screen-{name}.png", "iphone")

    plan = [  # (slajd, trajanje u sekundama, prelaz KA tom slajdu)
        ("intro", 2.6, "fade"), ("home", 3.0, "fade"), ("camera", 3.0, "slideleft"),
        ("processing", 2.4, "fadewhite"), ("result", 3.6, "fade"), ("saved", 3.0, "slideleft"),
        ("share", 3.0, "slideleft"), ("end", 3.6, "fade"),
    ]
    slides = []
    for name, duration, transition in plan:
        if name == "intro":
            img = intro(t)
        elif name == "end":
            img = end_card(t, qr["result"])
        else:
            img = slide(t[name], work / f"screen-{name}.png")
        path = work / f"slide-{name}.png"
        img.save(path)
        slides.append((path, duration, transition))

    out = HERE / "out" / f"invoice2ips-{args.locale}.mp4"
    build_video(slides, out)
    total = sum(d for _, d, _ in slides) - FADE * (len(slides) - 1)
    print(f"✓ {out.relative_to(ROOT)} ({total:.1f} s, {out.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
