#!/usr/bin/env bash
# Builds im.app into apps/macos/build/.
#   scripts/build-app.sh             release build for this Mac's architecture
#   scripts/build-app.sh --universal release build for Apple silicon + Intel
set -euo pipefail

cd "$(dirname "$0")/.."

arch_flags=()
if [[ "${1:-}" == "--universal" ]]; then
  arch_flags=(--arch arm64 --arch x86_64)
fi

swift build -c release "${arch_flags[@]+"${arch_flags[@]}"}"
bin_dir="$(swift build -c release "${arch_flags[@]+"${arch_flags[@]}"}" --show-bin-path)"

app="build/im.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/IM" "$app/Contents/MacOS/IM"
cp Resources/Info.plist "$app/Contents/Info.plist"
# The .lproj folders tell AppKit which languages im supports, so its own strings follow the chosen one.
mkdir -p "$app/Contents/Resources"
cp -R Resources/*.lproj "$app/Contents/Resources/"

# Ad-hoc signature so the app runs locally; distribution builds need a Developer ID.
codesign --force --sign - "$app"

echo "Built $(pwd)/$app"
