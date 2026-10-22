# Store screenshot-ovi sa natpisima za racun2IPS

`make_screenshots.py` automatski uzima sirove snimke ekrana i pravi gotove store slike sa brendiranim podlogama i natpisima za App Store i Google Play listinge na srpskom i engleskom jeziku.

## Upotreba

Sirovi snimci se ne prave na simulatoru/emulatoru, već iz dizajna:
`render_raw.py` ima HTML kopije ekrana aplikacije (iste boje, Inter font,
Lucide ikonice iz fonta koji koristi aplikacija, pravi IPS QR kodovi za demo
podatke) i renderuje ih headless Chrome-om u 1320 × 2868, na srpskom i
engleskom.

```sh
# samo kad se menjaju demo podaci u QR kodovima -> design/qr.json
fvm flutter test marketing/screenshots/qr_svg_test.dart

# sirovi snimci -> raw/<locale>/ (iPhone 1320 × 2868) i raw_ipad/<locale>/ (iPad 2064 × 2752)
python3 marketing/screenshots/render_raw.py
python3 marketing/screenshots/render_raw.py --device ipad --locale en   # samo deo

# gotove store slike sa natpisima -> out/<platform>/<locale>/
python3 marketing/screenshots/make_screenshots.py
python3 marketing/screenshots/make_screenshots.py --locale sr --platform play
```

Na iPad-u ekrani prate aplikaciju: početni ekran i rezultat su kolona od 448
(kao `HomeScreen`), sačuvani kodovi idu celom širinom, a brzi QR prikaz je
bottom sheet od najviše 640. Kad se promeni izgled ekrana u aplikaciji,
uskladi markup u `render_raw.py`.
Slajd `privacy` nema snimak ekrana, već se generiše iz ikonice aplikacije
(`assets/icon/appstore.png`).

Rezultat je numerisan redosledom za direktan upload:

```
out/ios/sr/1-result.png      1320 × 2868   (iPhone 6.9")
out/ipad/en/1-result.png     2064 × 2752   (iPad 13" — obavezno, aplikacija je univerzalna)
out/play/sr/2-scan.png       1080 × 1920   (Google Play 9:16)
```

## Racional i redosled slajdova

- **1. IPS QR kod (result.png):** Glavni rezultat aplikacije ide prvi jer Apple i Google prva tri slajda prikazuju u pretrazi. m-banking kompatibilnost i trenutno plaćanje su ključni razlog instalacije.
- **2. AI Čitanje (scan.png):** Prikazuje proces skeniranja i uvoza slika uplatnica sa automatskim izvlačenjem iznosa, računa i poziva na broj.
- **3. Privatnost (privacy - tekstualni slajd):** Naglašava rad bez registracije, pretplate i bez slanja privatnih podataka na spoljne servere van AI ekstrakcije.
- **4. Sačuvani kodovi (saved.png):** Organizacija redovnih računa i kreiranje sopstvenog IPS QR koda za uplate.
- **5. Deljenje (share.png):** Brzi QR prikaz sačuvanog računa sa kopiranjem, deljenjem i oznakom plaćanja.

## Dizajn i brending

- **Boje:** Gradijent je usklađen sa Emerald nijansama `racun2IPS` aplikacije (`lib/theme.dart`).
- **Fontovi:** Arial Bold / Supplemental Arial radi pouzdanog renderovanja dijakritika (č, ć, š, ž, đ) kroz Pillow biblioteku.
- **Okvir uređaja:** Slike se automatski centriraju, dobijaju meku senku i zaobljene uglove.

## Zavisnosti

Potrebni su Google Chrome (za `render_raw.py`) i biblioteka Pillow:

```sh
python3 -m pip install Pillow
```

`out/` se generiše ponovo posle svake promene; `raw/` i `design/qr.json` se zadržavaju u gitu.
