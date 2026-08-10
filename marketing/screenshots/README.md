# Store screenshot-ovi sa natpisima za racun2IPS

`make_screenshots.py` automatski uzima sirove snimke ekrana i pravi gotove store slike sa brendiranim podlogama i natpisima za App Store i Google Play listinge na srpskom i engleskom jeziku.

## Upotreba

**1.** Napravi snimke ekrana na telefonu ili simulatoru i ubaci ih ovde:

```
marketing/screenshots/raw/result.png
marketing/screenshots/raw/scan.png
marketing/screenshots/raw/saved.png
marketing/screenshots/raw/share.png
```

Imena moraju biti tačno ovakva — po njima se biraju odgovarajući natpisi. Slajd `privacy` nema zaseban snimak ekrana, već se automatski generiše iz ikonice aplikacije (`assets/icon/appstore.png`).

**2.** Pokreni generator:

```sh
python3 marketing/screenshots/make_screenshots.py
```

Možeš filtrirati po jeziku i platformi:

```sh
python3 marketing/screenshots/make_screenshots.py --locale sr --platform ios
python3 marketing/screenshots/make_screenshots.py --locale en --platform play
```

**3.** Rezultat je u `out/<platform>/<locale>/`, numerisan redosledom za direktan upload:

```
out/ios/sr/1-result.png      1320 × 2868   (iPhone 6.9")
out/play/sr/2-scan.png       1080 × 1920   (Google Play 9:16)
```

## Racional i redosled slajdova

- **1. IPS QR kod (result.png):** Glavni rezultat aplikacije ide prvi jer Apple i Google prva tri slajda prikazuju u pretrazi. m-banking kompatibilnost i trenutno plaćanje su ključni razlog instalacije.
- **2. AI Čitanje (scan.png):** Prikazuje proces skeniranja i uvoza slika uplatnica sa automatskim izvlačenjem iznosa, računa i poziva na broj.
- **3. Privatnost (privacy - tekstualni slajd):** Naglašava rad bez registracije, pretplate i bez slanja privatnih podataka na spoljne servere van AI ekstrakcije.
- **4. Sačuvani kodovi (saved.png):** Organizacija redovnih računa i kreiranje sopstvenog IPS QR koda za uplate.
- **5. Deljenje i Backup (share.png):** Slanje kodova drugima i rezervne kopije podataka.

## Dizajn i brending

- **Boje:** Gradijent je usklađen sa Emerald nijansama `racun2IPS` aplikacije (`lib/theme.dart`).
- **Fontovi:** Arial Bold / Supplemental Arial radi pouzdanog renderovanja dijakritika (č, ć, š, ž, đ) kroz Pillow biblioteku.
- **Okvir uređaja:** Slike se automatski centriraju, dobijaju meku senku i zaobljene uglove.

## Zavisnosti

Potrebna je biblioteka Pillow (Python Imaging Library):

```sh
python3 -m pip install Pillow
```

`out/` folder se ne commit-uje u Git (generisani fajlovi), dok se sirovi snimci u `raw/` zadržavaju za kasnija ažuriranja.
