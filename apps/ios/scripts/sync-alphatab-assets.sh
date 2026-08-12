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
cp "$source_dir/dist/soundfont/sonivox.sf2" "$target_dir/soundfont/sonivox.sf2"
cp "$source_dir/LICENSE" "$target_dir/LICENSE-MPL-2.0.txt"

echo "Synced alphaTab assets into $target_dir"
