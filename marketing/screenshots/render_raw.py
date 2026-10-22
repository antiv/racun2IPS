#!/usr/bin/env python3
"""Sirovi store snimci ekrana iz dizajna, bez simulatora.

Ekrani aplikacije (početni, rezultat, sačuvani kodovi, brzi QR prikaz) su
HTML kopije Flutter ekrana — iste boje (lib/theme.dart), Inter font
(assets/fonts), Lucide ikonice iz fonta koji koristi aplikacija i pravi IPS
QR kodovi za demo podatke (design/qr.json, iz qr_svg_test.dart). Headless
Chrome ih renderuje za iPhone 6.9" (1320x2868, raw/) i iPad 13" (2064x2752,
raw_ipad/), a make_screenshots.py dodaje podloge i natpise. Na iPad-u, kao u
aplikaciji, početni ekran i rezultat su kolona od 448, sačuvani kodovi celom
širinom, a bottom sheet najviše 640 (Material 3).

    fvm flutter test marketing/screenshots/qr_svg_test.dart   # samo kad se menjaju demo podaci
    python3 marketing/screenshots/render_raw.py               # -> raw[_ipad]/<locale>/<slug>.png
    python3 marketing/screenshots/make_screenshots.py

Kad se menja izgled ekrana u aplikaciji, ovde treba uskladiti markup.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# (širina, visina, skala, folder): logičke tačke uređaja i izlaz u pikselima.
DEVICES = {
    "iphone": (440, 956, 3, HERE / "raw"),        # 1320 x 2868
    "ipad": (1032, 1376, 2, HERE / "raw_ipad"),   # 2064 x 2752
}
COLUMN = 448  # maxWidth kolone u HomeScreen-u
SHEET = 640   # Material 3 maksimalna širina bottom sheet-a

# Lucide kodovi (lucide_icons_flutter, LucideIcons.<ime>).
ICON = {
    "qr": 57823, "more": 57527, "camera": 57444, "image": 57590, "file": 57548,
    "clipboard": 57477, "chevron": 57455, "receipt": 58323, "user": 57759,
    "pin": 57945, "back": 57416, "upload": 57758, "download": 57522,
    "search": 57681, "plus": 57661, "check": 57452, "check_circle": 57894,
    "share": 57686, "copy": 57502, "bookmark": 57440, "rotate": 57672,
    "x": 57778, "chevron_down": 57453,
}

T = {
    "sr": {
        "scan_title": "Skenirajte račun",
        "scan_desc": "Fotografišite račun i dobijte IPS QR kod za vašu bankarsku aplikaciju.",
        "open_camera": "Otvori kameru", "gallery": "Galerija", "pdf": "PDF račun",
        "paste": "Nalepi tekst", "saved": "Sačuvani kodovi", "show_all": "Prikaži sve",
        "paid": "Plaćeno", "open_amount": "Otvoren iznos", "ready": "IPS kod je spreman",
        "invoice": "Račun", "share": "Podeli", "copy": "Kopiraj IPS",
        "details": "Podaci za plaćanje", "source": "Pročitano sa računa",
        "recipient": "Primalac", "account": "Račun", "amount": "Iznos (RSD)",
        "code": "Šifra plaćanja", "purpose": "Svrha", "reference": "Poziv na broj",
        "save_invoice": "Sačuvaj račun", "new_invoice": "Novi račun",
        "instruction": "Skenirajte ovaj kod svojom mobilnom bankarskom aplikacijom za trenutno plaćanje.",
        "search": "Pretraga po primaocu ili računu", "all": "Svi", "bills": "Računi",
        "own": "Moji kodovi", "pinned": "Prikačeno", "others": "Ostalo",
        "show_qr": "Prikaži QR", "mark_paid": "Označi plaćeno", "add": "Dodaj",
        "paid_month": "Plaćeno ovog meseca",
        "c_power": "Struja", "c_utils": "Komunalije", "c_net": "Internet",
        "c_own": "Moj tekući račun", "p_power": "Račun za električnu energiju",
        "date": "Uto 22. okt",
    },
    "en": {
        "scan_title": "Scan Your Invoice",
        "scan_desc": "Snap your invoice and get an IPS QR code for your banking app.",
        "open_camera": "Open Camera", "gallery": "Gallery", "pdf": "PDF invoice",
        "paste": "Paste text", "saved": "Saved codes", "show_all": "See all",
        "paid": "Paid", "open_amount": "Open amount", "ready": "IPS code is ready",
        "invoice": "Invoice", "share": "Share", "copy": "Copy IPS",
        "details": "Payment details", "source": "Read from invoice",
        "recipient": "Recipient", "account": "Account", "amount": "Amount (RSD)",
        "code": "Payment Code", "purpose": "Purpose", "reference": "Reference",
        "save_invoice": "Save invoice", "new_invoice": "New invoice",
        "instruction": "Scan this code with your mobile banking app to pay instantly.",
        "search": "Search by recipient or account", "all": "All", "bills": "Bills",
        "own": "My codes", "pinned": "Pinned", "others": "Others",
        "show_qr": "Show QR", "mark_paid": "Mark paid", "add": "Add",
        "paid_month": "Paid this month",
        "c_power": "Electricity", "c_utils": "Utilities", "c_net": "Internet",
        "c_own": "My current account", "p_power": "Electricity bill",
        "date": "Tue Oct 22",
    },
}


def i(name: str, size: int = 20, color: str = "currentColor") -> str:
    return (f'<span class="i" style="font-size:{size}px;color:{color}">'
            f'&#{ICON[name]};</span>')


def lucide_font() -> Path:
    lock = (ROOT / "pubspec.lock").read_text()
    version = re.search(r"lucide_icons_flutter:.*?version: \"([^\"]+)\"", lock, re.S).group(1)
    path = Path.home() / f".pub-cache/hosted/pub.dev/lucide_icons_flutter-{version}/assets/lucide.ttf"
    if not path.exists():
        sys.exit(f"Lucide font nije pronađen: {path} (pokreni fvm flutter pub get)")
    return path


def css(width: int, height: int) -> str:
    fonts = ROOT / "assets/fonts"
    faces = "".join(
        f"@font-face{{font-family:Inter;font-weight:{w};src:url('{(fonts / f).as_uri()}')}}"
        for w, f in [(400, "Inter-Regular.ttf"), (500, "Inter-Medium.ttf"),
                     (600, "Inter-SemiBold.ttf"), (700, "Inter-Bold.ttf")])
    return faces + f"""
@font-face{{font-family:Lucide;src:url('{lucide_font().as_uri()}')}}
*{{box-sizing:border-box}}
html,body{{margin:0;width:{width}px;height:{height}px;overflow:hidden;background:#FAFAF9}}
body{{font-family:Inter,sans-serif;color:#1C1917;-webkit-font-smoothing:antialiased}}
.i{{font-family:Lucide;font-style:normal;line-height:1;display:inline-flex}}
.screen{{position:relative;width:{width}px;height:{height}px;display:flex;flex-direction:column;overflow:hidden}}
.content{{position:relative;flex:1;min-height:0;display:flex;flex-direction:column;width:100%;margin:0 auto}}
.status{{height:54px;flex:none;display:flex;align-items:flex-end;justify-content:space-between;padding:0 34px 10px 42px;font-weight:600;font-size:16px}}
.status.pad{{height:24px;align-items:center;padding:0 44px;font-size:13px}}
.bars{{display:flex;gap:6px;align-items:center}}
.sig{{display:flex;gap:2px;align-items:flex-end}}.sig b{{width:3.5px;background:#1C1917;border-radius:1px}}
.bat{{width:25px;height:12px;border:1.5px solid #1C1917;border-radius:4px;padding:1.5px;opacity:.9}}.bat b{{display:block;height:100%;width:80%;background:#1C1917;border-radius:1.5px}}
.card{{background:#fff;border:1px solid #E7E5E4;border-radius:20px;box-shadow:0 1px 2px rgba(28,25,23,.04)}}
.tile{{width:40px;height:40px;border-radius:12px;display:flex;align-items:center;justify-content:center;flex:none}}
.row{{display:flex;align-items:center;gap:12px;padding:12px 12px 12px 14px}}
.row+.row{{border-top:1px solid #F5F5F4}}
.title{{font-size:14.5px;font-weight:600;display:flex;align-items:center;gap:6px;white-space:nowrap}}
.sub{{font-size:12.5px;color:#78716C;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}
.badge{{font-size:10.5px;font-weight:600;color:#047857;background:#D1FAE5;border-radius:999px;padding:1.5px 7px}}
.btn{{display:flex;align-items:center;justify-content:center;gap:7px;font-weight:600;border-radius:14px}}
.label{{font-size:11.5px;font-weight:600;color:#78716C}}
.qr{{background:#fff;border:1px solid #F5F5F4;border-radius:18px;padding:12px;display:inline-flex}}
.qr svg{{width:176px;height:176px;display:block}}
"""


def status_bar(device: str, t) -> str:
    bars = ('<span class="sig"><b style="height:4px"></b><b style="height:6px"></b>'
            '<b style="height:8px"></b><b style="height:10px"></b></span>'
            '<span class="bat"><b></b></span>')
    if device == "ipad":
        return (f'<div class="status pad"><span>9:41&nbsp;&nbsp;{t["date"]}</span>'
                f'<span class="bars">{bars}</span></div>')
    return f'<div class="status"><span>9:41</span><span class="bars">{bars}</span></div>'


def frame(body: str, device: str, t, column: bool = True, overlay: str = "") -> str:
    """Status bar + sadržaj ekrana; na iPad-u kolona od 448 kao u HomeScreen-u."""
    width = f"max-width:{COLUMN}px" if column and device == "ipad" else ""
    return (f'<div class="screen">{status_bar(device, t)}'
            f'<div class="content" style="{width}">{body}</div>{overlay}</div>')


def saved_tile(icon_bg, icon, icon_color, title, sub, trailing="", extra=""):
    return f"""<div class="row">
<div class="tile" style="background:{icon_bg}">{i(icon, 18, icon_color)}</div>
<div style="flex:1;min-width:0"><div class="title">{title}{extra}</div><div class="sub">{sub}</div></div>
{trailing}</div>"""


def home_body(t) -> str:
    qr_btn = (f'<div class="tile" style="width:44px;height:44px;background:#ECFDF5">'
              f'{i("qr", 20, "#047857")}</div>')
    pin = i("pin", 13, "#059669")
    src = lambda icon, label: (
        f'<div class="btn" style="height:64px;flex:1;flex-direction:column;gap:5px;border:1px solid #E7E5E4;'
        f'background:#FAFAF9;font-size:12px;color:#44403C">{i(icon, 20, "#57534E")}{label}</div>')
    return f"""<div style="display:flex;align-items:center;gap:10px;padding:10px 8px 8px 20px">
  <div class="tile" style="width:32px;height:32px;border-radius:9px;background:#059669">{i("qr", 18, "#fff")}</div>
  <div style="flex:1;font-size:18px;font-weight:700;letter-spacing:-.4px"><span style="color:#059669">Invoice</span>2IPS</div>
  <div class="tile" style="width:44px;height:44px">{i("more", 22, "#57534E")}</div>
</div>
<div style="padding:4px 16px 0;display:flex;flex-direction:column;gap:22px">
  <div class="card" style="border-radius:24px;padding:20px;display:flex;flex-direction:column;gap:16px">
    <div style="display:flex;gap:14px;align-items:center">
      <div class="tile" style="width:56px;height:56px;border-radius:18px;background:#ECFDF5">{i("camera", 28, "#059669")}</div>
      <div><div style="font-size:20px;font-weight:700;letter-spacing:-.4px">{t["scan_title"]}</div>
      <div style="font-size:13.5px;line-height:1.45;color:#78716C;margin-top:4px">{t["scan_desc"]}</div></div>
    </div>
    <div class="btn" style="height:52px;border-radius:16px;background:#059669;color:#fff;font-size:15.5px">{i("camera", 20, "#fff")}{t["open_camera"]}</div>
    <div style="display:flex;gap:8px">{src("image", t["gallery"])}{src("file", t["pdf"])}{src("clipboard", t["paste"])}</div>
  </div>
  <div>
    <div style="display:flex;align-items:center;gap:8px;padding:0 0 6px 4px">
      <span style="font-size:16px;font-weight:700;letter-spacing:-.2px">{t["saved"]}</span>
      <span style="font-size:12px;font-weight:600;color:#57534E;background:#F5F5F4;border-radius:999px;padding:2px 8px">4</span>
      <span style="margin-left:auto;font-size:13.5px;font-weight:600;color:#047857;display:flex;align-items:center;gap:2px;height:44px">{t["show_all"]}{i("chevron", 16)}</span>
    </div>
    <div class="card" style="overflow:hidden">
      {saved_tile("#F5F5F4", "receipt", "#57534E", t["c_power"], "Elektro Snabdevanje · 4.820,00 RSD", qr_btn, pin)}
      {saved_tile("#F5F5F4", "receipt", "#57534E", t["c_utils"], "JKP Grad Servis · 6.312,40 RSD", qr_btn, f'<span class="badge">{t["paid"]}</span>')}
      {saved_tile("#ECFDF5", "user", "#059669", t["c_own"], f'Petar Petrović · {t["open_amount"]}', qr_btn)}
    </div>
  </div>
</div>
<div style="margin-top:auto;padding:14px 0 30px;text-align:center">
  <img src="{(ROOT / "assets/images/ant-biocode.png").as_uri()}" style="height:15px;opacity:.4;filter:grayscale(1)">
</div>"""


def home(t, device) -> str:
    return frame(home_body(t), device, t)


def result(t, qr, device) -> str:
    field = lambda label, value, counter="": f"""<div style="padding:11px 14px;border-top:1px solid #F5F5F4">
<div style="display:flex;justify-content:space-between"><span class="label">{label}</span>
<span style="font-size:10px;color:#D6D3D1">{counter}</span></div>
<div style="font-size:14.5px;font-weight:500;margin-top:2px">{value}</div></div>"""
    body = f"""<div style="display:flex;align-items:center;gap:8px;padding:10px 16px 6px 8px">
  <div class="tile" style="width:44px;height:44px">{i("back", 22, "#292524")}</div>
  <div style="flex:1;font-size:16px;font-weight:600">{t["ready"]}</div>
  <div class="btn" style="height:36px;padding:0 12px;border-radius:999px;border:1px solid #E7E5E4;background:#fff;font-size:12.5px;color:#44403C;gap:6px">{i("image", 15, "#57534E")}{t["invoice"]}</div>
</div>
<div style="padding:6px 16px 0;display:flex;flex-direction:column;flex:1;min-height:0;overflow:hidden">
  <div class="card" style="border-radius:24px;padding:20px;display:flex;flex-direction:column;align-items:center">
    <div class="qr">{qr}</div>
    <div style="margin-top:14px;font-size:30px;font-weight:700;letter-spacing:-.8px">4.820,00 <span style="font-size:16px;font-weight:600;color:#78716C;letter-spacing:0">RSD</span></div>
    <div style="margin-top:2px;font-size:13px;line-height:1.4;color:#78716C;text-align:center">{t["instruction"]}</div>
    <div style="display:flex;gap:8px;width:100%;margin-top:14px">
      <div class="btn" style="flex:1;height:46px;background:#059669;color:#fff;font-size:14px">{i("share", 17, "#fff")}{t["share"]}</div>
      <div class="btn" style="flex:1;height:46px;border:1px solid #E7E5E4;background:#fff;color:#44403C;font-size:14px">{i("copy", 17)}{t["copy"]}</div>
    </div>
  </div>
  <div style="display:flex;align-items:center;padding:14px 4px 8px">
    <span style="flex:1;font-size:15px;font-weight:700">{t["details"]}</span>
    <span style="font-size:11.5px;font-weight:600;color:#047857;background:#ECFDF5;border-radius:999px;padding:3px 9px">{t["source"]}</span>
  </div>
  <div class="card" style="overflow:hidden">
    <div style="padding:11px 14px"><div style="display:flex;justify-content:space-between"><span class="label">{t["recipient"]}</span>
      <span style="font-size:10px;color:#D6D3D1">26/70</span></div>
      <div style="font-size:14.5px;font-weight:500;margin-top:2px">Elektro Snabdevanje d.o.o.</div></div>
    {field(t["account"], "160000000001234595")}
    <div style="padding:12px 14px;border-top:1px solid #F5F5F4;display:flex;align-items:baseline">
      <span class="label" style="flex:1">{t["amount"]}</span>
      <span style="font-size:20px;font-weight:700;color:#059669">4820</span>
      <span style="font-size:12px;font-weight:700;color:#A8A29E;margin-left:4px">RSD</span></div>
    <div style="padding:12px 14px;border-top:1px solid #F5F5F4;display:flex;align-items:center;gap:8px">
      <span class="label">{t["code"]}</span>
      <span style="flex:1;text-align:right;font-size:14.5px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">289 - Transakcije po nalogu građana</span>
      {i("chevron_down", 18, "#A8A29E")}</div>
    {field(t["purpose"], t["p_power"])}
    {field(t["reference"], "97921234567890")}
  </div>
</div>
<div style="padding:12px 16px 30px;display:flex;gap:8px;background:#FAFAF9">
  <div class="btn" style="flex:1;height:50px;border-radius:16px;border:1px solid #E7E5E4;background:#fff;color:#44403C;font-size:14.5px">{i("bookmark", 18)}{t["save_invoice"]}</div>
  <div class="btn" style="flex:1;height:50px;border-radius:16px;background:#F5F5F4;color:#292524;font-size:14.5px">{i("rotate", 18)}{t["new_invoice"]}</div>
</div>"""
    return frame(body, device, t)


def saved(t, device) -> str:
    chevron = i("chevron", 18, "#A8A29E")
    seg = lambda label, on: (
        f'<div class="btn" style="flex:1;height:36px;border-radius:9px;font-size:13px;'
        f'{"background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.08);color:#1C1917" if on else "color:#78716C"}">{label}</div>')
    group = lambda label: (f'<div style="font-size:11.5px;font-weight:700;letter-spacing:.8px;'
                           f'color:#78716C;padding:6px 4px 8px">{label.upper()}</div>')
    body = f"""<div style="display:flex;align-items:center;padding:4px 4px 0">
  <div class="tile" style="width:48px;height:48px">{i("back", 22, "#292524")}</div>
  <div style="flex:1"></div>
  <div class="tile" style="width:48px;height:48px">{i("upload", 20, "#57534E")}</div>
  <div class="tile" style="width:48px;height:48px">{i("download", 20, "#57534E")}</div>
</div>
<div style="padding:0 20px 14px;display:flex;flex-direction:column;gap:14px">
  <div style="font-size:28px;font-weight:700;letter-spacing:-.7px">{t["saved"]}</div>
  <div style="height:46px;border-radius:14px;border:1px solid #E7E5E4;background:#fff;display:flex;align-items:center;gap:12px;padding:0 14px;font-size:14px;color:#A8A29E">{i("search", 18, "#78716C")}{t["search"]}</div>
  <div style="display:flex;gap:4px;padding:4px;background:#F5F5F4;border-radius:12px">{seg(t["all"], True)}{seg(t["bills"], False)}{seg(t["own"], False)}</div>
</div>
<div style="padding:0 16px">
  {group(t["pinned"])}
  <div class="card" style="border-radius:18px;padding:14px;margin-bottom:8px">
    <div style="display:flex;align-items:center;gap:12px">
      <div class="tile" style="background:#F5F5F4">{i("receipt", 18, "#57534E")}</div>
      <div style="flex:1;min-width:0"><div class="title">{t["c_power"]}{i("pin", 13, "#059669")}</div><div class="sub">Elektro Snabdevanje</div></div>
      <div style="text-align:right"><div style="font-size:15px;font-weight:700">4.820,00</div><div style="font-size:11px;font-weight:600;color:#78716C">RSD</div></div>
    </div>
    <div style="display:flex;gap:8px;margin-top:12px">
      <div class="btn" style="flex:1;height:40px;border-radius:12px;background:#059669;color:#fff;font-size:13.5px">{i("qr", 16, "#fff")}{t["show_qr"]}</div>
      <div class="btn" style="flex:1;height:40px;border-radius:12px;border:1px solid #E7E5E4;background:#fff;color:#44403C;font-size:13.5px">{i("check", 16)}{t["mark_paid"]}</div>
    </div>
  </div>
  {group(t["others"])}
  <div class="card" style="border-radius:18px;overflow:hidden">
    {saved_tile("#F5F5F4", "receipt", "#57534E", t["c_utils"], "JKP Grad Servis · 6.312,40 RSD", chevron, f'<span class="badge">{t["paid"]}</span>')}
    {saved_tile("#F5F5F4", "receipt", "#57534E", t["c_net"], "NetLink d.o.o. · 2.499,00 RSD", chevron)}
    {saved_tile("#ECFDF5", "user", "#059669", t["c_own"], f'Petar Petrović · {t["open_amount"]}', chevron)}
  </div>
</div>
<div class="btn" style="position:absolute;right:20px;bottom:34px;height:56px;padding:0 22px 0 18px;border-radius:18px;background:#059669;color:#fff;font-size:15px;gap:8px;box-shadow:0 8px 20px -6px rgba(5,150,105,.45)">{i("plus", 20, "#fff")}{t["add"]}</div>"""
    # Sačuvani kodovi su zaseban route bez ograničenja širine.
    return frame(body, device, t, column=False)


def share(t, qr, device) -> str:
    sheet = f"""<div style="position:absolute;inset:0;background:rgba(28,25,23,.42)"></div>
<div style="position:absolute;left:0;right:0;bottom:0;margin:0 auto;max-width:{SHEET}px;background:#fff;border-radius:28px 28px 0 0;padding:10px 20px 34px">
  <div style="width:38px;height:5px;border-radius:3px;background:#E7E5E4;margin:0 auto 14px"></div>
  <div style="display:flex;align-items:center;gap:4px">
    <div style="flex:1"><div style="font-size:18px;font-weight:700;color:#292524">{t["c_utils"]}</div>
      <div style="font-size:12.5px;color:#A8A29E;margin-top:2px">JKP Grad Servis • •••• 9037</div></div>
    <div class="tile" style="width:44px;height:44px">{i("pin", 20, "#A8A29E")}</div>
    <div class="tile" style="width:44px;height:44px">{i("x", 20, "#A8A29E")}</div>
  </div>
  <div style="margin-top:12px;display:flex;justify-content:center">
    <div style="background:#FAFAF9;border:1px solid #F5F5F4;border-radius:20px;padding:16px;display:inline-flex">
      <div style="width:200px;height:200px">{qr.replace('<svg ', '<svg style="width:200px;height:200px;display:block" ', 1)}</div></div>
  </div>
  <div style="margin-top:14px;display:flex;align-items:center;padding:8px 16px;background:#FAFAF9;border:1px solid #E7E5E4;border-radius:16px">
    <span style="flex:1;font-size:11px;font-weight:700;letter-spacing:.8px;color:#78716C">{t["amount"].upper()}</span>
    <span style="font-size:18px;font-weight:700;color:#047857">6312.40</span>
    <span style="font-size:12px;font-weight:700;color:#78716C;margin-left:4px">RSD</span>
  </div>
  <div style="margin-top:12px;padding:10px 14px;background:#FAFAF9;border-radius:14px;font-size:12px">
    <div style="display:flex;justify-content:space-between"><span style="font-size:11.5px;color:#A8A29E">{t["account"]}</span><span style="font-weight:600;color:#44403C">265000000006789037</span></div>
    <div style="display:flex;justify-content:space-between;margin-top:4px"><span style="font-size:11.5px;color:#A8A29E">{t["reference"]}</span><span style="font-weight:600;color:#44403C">973020260930</span></div>
  </div>
  <div style="display:flex;gap:8px;margin-top:14px">
    <div class="btn" style="flex:1;height:46px;border:1px solid #E7E5E4;font-size:13px;color:#44403C">{i("copy", 17, "#57534E")}{t["copy"]}</div>
    <div class="btn" style="flex:1;height:46px;border:1px solid #E7E5E4;font-size:13px;color:#44403C">{i("share", 17, "#57534E")}{t["share"]}</div>
  </div>
  <div class="btn" style="margin-top:8px;height:46px;border-radius:999px;background:#ECFDF5;color:#047857;font-size:13.5px">{i("check_circle", 18, "#047857")}{t["paid_month"]}</div>
</div>"""
    return frame(home_body(t), device, t, overlay=sheet)


def render(html: str, out: Path, device: str) -> None:
    width, height, scale, _ = DEVICES[device]
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as f:
        f.write(f'<!doctype html><html><head><meta charset="utf-8"><style>{css(width, height)}</style></head>'
                f'<body>{html}</body></html>')
        page = Path(f.name)
    try:
        subprocess.run(
            [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
             "--allow-file-access-from-files", f"--window-size={width},{height}",
             f"--force-device-scale-factor={scale}", "--virtual-time-budget=2000",
             f"--screenshot={out}", page.as_uri()],
            check=True, capture_output=True)
    finally:
        page.unlink()
    print(f"  {out.relative_to(HERE)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--locale", choices=sorted(T), action="append")
    ap.add_argument("--device", choices=sorted(DEVICES), action="append")
    args = ap.parse_args()
    qr = json.loads((HERE / "design/qr.json").read_text())
    for device in args.device or sorted(DEVICES):
        raw = DEVICES[device][3]
        for locale in args.locale or sorted(T):
            t = T[locale]
            for slug, html in {
                "result": result(t, qr["result"], device),
                "scan": home(t, device),
                "saved": saved(t, device),
                "share": share(t, qr["share"], device),
            }.items():
                render(html, raw / locale / f"{slug}.png", device)
    return 0


if __name__ == "__main__":
    sys.exit(main())
