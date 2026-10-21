#!/usr/bin/env bash
#
# deploy.sh — podiže verziju, bilduje release artefakt i kopira ga u root projekta.
# deploy.sh — podiže verziju, bilduje release artefakt i kopira ga u root projekta,
# uz opcioni automatski upload AAB paketa na Google Play Console.
#
# Podrazumevano: AAB (za Play Store), uz bump verzije (patch + build broj).
#   pubspec  version: X.Y.Z+N  ->  X.Y.(Z+1)+(N+1)
# Izlaz: invoice2ips-<versionName>.aab (ili .apk) u root-u projekta.
#
# Upotreba:
#   ./deploy.sh                 # AAB, sa bump-om verzije
#   ./deploy.sh apk             # APK umesto AAB
#   ./deploy.sh                 # AAB, sa bump-om verzije (samo lokalni build)
#   ./deploy.sh --upload        # AAB, bump verzije + upload na Google Play
#   ./deploy.sh apk             # APK umesto AAB (bez uploada)
#   ./deploy.sh --no-bump       # bez podizanja verzije
#   ./deploy.sh apk --no-bump   # APK, bez bump-a (flegovi bilo kojim redosledom)
#   ./deploy.sh --upload --no-bump # upload bez podizanja verzije
#
set -euo pipefail

# --- Lokacija projekta (skript radi i ako se pozove iz drugog dir-a) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PUBSPEC="pubspec.yaml"
ENV_FILE="android/deploy.env"
PLAY_UPLOAD="tool/play_upload.py"
PACKAGE="rs.antonijevic.invoice2ips"

# --- Parsiranje argumenata (flegovi, bilo kojim redosledom) ---
FORMAT="aab"
BUMP=true
UPLOAD=false
for arg in "$@"; do
  case "$arg" in
    apk)          FORMAT="apk" ;;
    aab)          FORMAT="aab" ;;
    --upload)     UPLOAD=true ;;
    --no-upload)  UPLOAD=false ;;
    --no-bump)    BUMP=false ;;
    -h|--help)
      sed -n '10,19p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'
      exit 0 ;;
    *)
      echo "Nepoznat argument: $arg" >&2
      echo "Dozvoljeno: apk | aab | --no-bump | --help" >&2
      echo "Dozvoljeno: apk | aab | --upload | --no-upload | --no-bump | --help" >&2
      exit 64 ;;
  esac
done

# --- FVM Flutter (sve komande kroz FVM, po konvenciji projekta) ---
export PATH="/opt/homebrew/bin:$PATH"
FLUTTER="fvm flutter"

# --- GEMINI_API_KEY iz .env (obavezan za AI ekstrakciju) ---
if [[ ! -f ".env" ]]; then
  echo "Nedostaje .env sa GEMINI_API_KEY — kopiraj .env.example i popuni." >&2
  exit 1
fi

# --- Pre-flight provere za Google Play upload ---
if $UPLOAD; then
  if [[ "$FORMAT" != "aab" ]]; then
    echo "Greška: Google Play upload podržava samo AAB format (izabran je $FORMAT)." >&2
    exit 1
  fi
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Nedostaje $ENV_FILE — kopiraj android/deploy.env.example i popuni." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  if [[ -z "${PLAY_SERVICE_ACCOUNT_JSON:-}" ]]; then
    echo "PLAY_SERVICE_ACCOUNT_JSON nije postavljen u $ENV_FILE" >&2
    exit 1
  fi
  if [[ ! -f "$PLAY_SERVICE_ACCOUNT_JSON" ]]; then
    echo "JSON ključ servisnog naloga nije pronađen na putanji: $PLAY_SERVICE_ACCOUNT_JSON" >&2
    exit 1
  fi
  if ! python3 -c 'import googleapiclient, google.oauth2' 2>/dev/null; then
    echo "python3 nema Google Play API biblioteke: pip3 install google-api-python-client google-auth" >&2
    exit 1
  fi
  if [[ ! -f "$PLAY_UPLOAD" ]]; then
    echo "Skripta za upload nije pronađena: $PLAY_UPLOAD" >&2
    exit 1
  fi
fi

# --- Pročitaj trenutnu verziju iz pubspec: "version: X.Y.Z+N" ---
version_line="$(grep -E '^version:[[:space:]]*[0-9]' "$PUBSPEC" | head -1)"
if [[ -z "$version_line" ]]; then
  echo "Ne mogu da nađem 'version:' u $PUBSPEC" >&2
  exit 1
fi
current="$(echo "$version_line" | sed -E 's/^version:[[:space:]]*//' | tr -d '[:space:]')"
name="${current%%+*}"            # X.Y.Z
build="${current#*+}"            # N
# Ako nema "+N", tretiraj build kao 0
if [[ "$build" == "$current" ]]; then build=0; fi

IFS='.' read -r major minor patch <<< "$name"

if $BUMP; then
  patch=$((patch + 1))
  build=$((build + 1))
  new_name="${major}.${minor}.${patch}"
  new_version="${new_name}+${build}"
  # Zameni version liniju u pubspec-u (in-place, BSD/sed kompatibilno).
  sed -i.bak -E "s/^version:[[:space:]]*.*/version: ${new_version}/" "$PUBSPEC"
  rm -f "${PUBSPEC}.bak"
  echo "Verzija: ${current}  ->  ${new_version}"
else
  new_name="$name"
  new_version="$current"
  echo "Verzija (bez promene): ${new_version}"
fi

# --- Build ---
# Dart obfuskacija + native debug simboli (čitljivi crash izveštaji na Play Console).
SYMBOLS_DIR="build/debug-symbols/${new_name}"
mkdir -p "$SYMBOLS_DIR"
BUILD_ARGS=(--obfuscate --split-debug-info="$SYMBOLS_DIR" --dart-define-from-file=.env)

echo "Bildujem ${FORMAT} (release, sa debug simbolima)..."
if [[ "$FORMAT" == "apk" ]]; then
  $FLUTTER build apk --release "${BUILD_ARGS[@]}"
  src="build/app/outputs/flutter-apk/app-release.apk"
  ext="apk"
else
  $FLUTTER build appbundle --release "${BUILD_ARGS[@]}"
  src="build/app/outputs/bundle/release/app-release.aab"
  ext="aab"
fi

if [[ ! -f "$src" ]]; then
  echo "Build nije proizveo očekivani fajl: $src" >&2
  exit 1
fi

# --- Kopiraj u root kao invoice2ips-<verzija>.<ext> ---
dest="invoice2ips-${new_name}.${ext}"
cp "$src" "$dest"

size="$(du -h "$dest" | cut -f1)"
echo ""
echo "✓ Gotovo: ${dest} (${size})"
echo "  Izvor:  ${src}"
echo "  Debug simboli: ${SYMBOLS_DIR}/"
if [[ "$FORMAT" == "aab" ]]; then
  echo ""
  echo "  Play Console: ako vidiš upozorenje za simbole, otpremi native debug simbole"
  echo "  (App bundle explorer → Downloads → Upload). Sadržaj: ${SYMBOLS_DIR}"
fi

# --- Upload na Google Play ---
if $UPLOAD; then
  TRACK="${PLAY_TRACK:-internal}"
  echo ""
  echo "==> Otpremam ${dest} na Google Play (${PACKAGE}, track: '${TRACK}')..."
  python3 "$PLAY_UPLOAD" "$dest" "$PACKAGE" --track "$TRACK" --key "$PLAY_SERVICE_ACCOUNT_JSON"
  echo ""
  echo "✓ Otpremljeno na Google Play! Obrada traje nekoliko minuta,"
  echo "  nakon čega će build biti vidljiv pod Testing → ${TRACK} track."
fi
