#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
source_dir="$repo_root/node_modules/@coderline/alphatab"
target_dir="$repo_root/apps/ios/StringMap/Resources/AlphaTab"

if [ ! -d "$source_dir/dist" ]; then
  echo "alphaTab is not installed. Run npm install from $repo_root first." >&2
  exit 1
fi

mkdir -p "$target_dir/font" "$target_dir/soundfont"
cp "$source_dir/dist/alphaTab.min.js" "$target_dir/alphaTab.min.js"
cp "$source_dir/dist/font/Bravura.woff2" "$target_dir/font/Bravura.woff2"
cp "$source_dir/LICENSE" "$target_dir/LICENSE-MPL-2.0.txt"

echo "Synced alphaTab assets into $target_dir"

cp "$source_dir/dist/font/Bravura-OFL.txt" "$target_dir/font/Bravura-OFL.txt"
cp "$source_dir/dist/font/Bravura-FONTLOG.txt" "$target_dir/font/Bravura-FONTLOG.txt"

# The independently licensed guitar bank is tracked separately from alphaTab.
# Never restore the package's SONiVOX bank during an asset sync.
printf '%s  %s\n' 'c5aaed6f4e1782ae11a6c783a92c9522d32b46bb8c6828afc7bb4db32e8a9ec5' "$target_dir/soundfont/stringmap-guitar.sf2" | shasum -a 256 -c -
