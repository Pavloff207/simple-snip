#!/bin/zsh
# Builds the demo renderer from the app's sources and writes demo.gif, snip.png, editor.png
# and social-preview.png.
# Usage: Tools/demo/make_demo.sh [output folder]   (default: docs/images)
set -euo pipefail

root="${0:A:h:h:h}"
out="${1:-$root/docs/images}"
work="$(mktemp -d)"
mkdir -p "$out"

app_sources=("${(@f)$(find "$root/SimpleSnip" -name '*.swift' ! -name 'SimpleSnipApp.swift')}")
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos26.0" \
  -o "$work/demo" "$root/Tools/demo/main.swift" "${app_sources[@]}"

"$work/demo" "$root/Tools/demo/demo.html" "$out" \
  "$root/SimpleSnip/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png"
echo "Wrote demo images to $out"
