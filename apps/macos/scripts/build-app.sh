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

# Sign with a stable identity when there is one, so the Keychain keeps trusting im across rebuilds.
# Override with IM_CODESIGN_IDENTITY; create a local one with scripts/create-dev-certificate.sh.
identity="${IM_CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]] && security find-certificate -c "im Development" >/dev/null 2>&1; then
  identity="im Development"
fi
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" "$app"
else
  codesign --force --sign - "$app"
  echo "warning: ad-hoc signed; macOS will ask for Keychain access again after every rebuild." >&2
  echo "         Run scripts/create-dev-certificate.sh once to avoid that." >&2
fi

echo "Built $(pwd)/$app"
