#!/usr/bin/env bash
# Copies the App Store screenshots and icon from an iOS-branch checkout and
# downloads the three open-source (OFL) fonts the video uses.
set -euo pipefail
cd "$(dirname "$0")"
IOS="${STRINGMAP_IOS:-../../../stringmap-ios}"
S="$IOS/docs/store/screenshots"
mkdir -p assets fonts
cp "$S/tutorial-expansion/iphone-6.9/02-learn.png" assets/learn.png
cp "$S/tutorial-expansion/iphone-6.9/04-chord-shape.png" assets/chord-shape.png
cp "$S/tutorial-expansion/iphone-6.9/06-free-practice.png" assets/free-practice.png
cp "$S/tutorial-expansion/iphone-6.9/01-home.png" assets/home.png
cp "$S/tutorial-expansion/iphone-6.9/07-play.png" assets/play.png
cp "$S/songbook/iphone-6.9/07-songbook-home.png" assets/songbook-home.png
cp "$S/songbook/iphone-6.9/08-songbook-library.png" assets/library.png
cp "$S/songbook/iphone-6.9/09-songbook-melody.png" assets/melody.png
cp "$S/songbook/iphone-6.9/10-songbook-chords.png" assets/chords.png
cp "$S/songbook/ipad-13/10-songbook-chords.png" assets/ipad-chords.png
cp "$S/iphone-6.9-dark/trace.png" assets/trace-dark.png
cp "$S/iphone-6.9-dark/arrangements.png" assets/arrangements-dark.png
cp "$IOS/apps/ios/StringMap/Assets.xcassets/AppIcon.appiconset/StringMap-AppIcon.png" assets/icon.png
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
curl -sS -A "$UA" "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=Fraunces:opsz,wght@9..144,500;9..144,600;9..144,700&family=JetBrains+Mono:wght@400;600&display=block" -o fonts/fonts.css
python3 - <<'PY'
import re, subprocess
css = open('fonts/fonts.css').read()
faces = []
for n, (subset, body) in enumerate(re.findall(r'/\* ([^*]+) \*/\s*@font-face \{([^}]*)\}', css)):
    if subset.strip() != 'latin':
        continue
    url = re.search(r'url\((https://[^)]+)\)', body).group(1)
    family = re.search(r"font-family: '([^']+)'", body).group(1).replace(' ', '')
    weight = re.search(r'font-weight: ([^;]+);', body).group(1).replace(' ', '_')
    name = f'{family}-{weight}-{n}.woff2'
    subprocess.run(['curl', '-sS', '-o', f'fonts/{name}', url], check=True)
    faces.append('@font-face {' + body.replace(url, name) + '}')
open('fonts/local.css', 'w').write('\n'.join(faces))
PY
echo "assets and fonts ready"
