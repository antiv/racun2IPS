# Bezbednost i prijava ranjivosti (Security Policy)

Bezbednost podataka korisnika i zaštita privatnosti su na prvom mestu u aplikaciji **Invoice2IPS**.

## Arhitektura privatnosti

- Aplikacija **ne čuva i ne šalje podatke na sopstvene servere**.
- Ako račun na sebi ima odštampan NBS IPS QR kod, on se čita **100% lokalno na uređaju**.
- Ako se koristi lokalni OCR (Google ML Kit), tekst se obrađuje **isključivo on-device**.
- Samo u slučaju neuspeha lokalnih metoda, slika ili tekst računa se prosleđuje na Google Gemini API radi ekstrakcije strukturiranih podataka.
- Svi sačuvani šabloni i kodovi se čuvaju isključivo u lokalnoj memoriji uređaja (`SharedPreferences`).

## Prijava bezbednosnih propusta

Ako otkrijete bilo kakav bezbednosni problem ili ranjivost:
1. **Molimo vas da ga NE prijavljujete javno kroz GitHub Issues.**
2. Pošaljite poverljivu poruku na email adresu: `iantonijevic@gmail.com` sa detaljnim opisom problema i koracima za reprodukciju.
3. Odgovorićemo u najkraćem mogućem roku i objaviti ispravku pre javnog objavljivanja detalja.
