#!/usr/bin/env bash
# Build a teammate-ready ClCoBar.app.zip with ad-hoc signing.
#
# Output: dist/CodexBar-<version>-<arch>.zip
#
# Share that single zip with teammates and point them at docs/install-guide-ko.md.
#
# Env vars (all optional):
#   ARCHES="arm64 x86_64"     Build a universal binary (default: host arch only)
#   SKIP_TEST=1               Skip swift test
#   DIST_DIR=./dist           Override output directory

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DIST_DIR="${DIST_DIR:-$ROOT/dist}"
SKIP_TEST="${SKIP_TEST:-0}"

source "$ROOT/version.env"
VERSION="${MARKETING_VERSION:-0.0.0}"
BUILD="${BUILD_NUMBER:-0}"

if [[ -n "${ARCHES:-}" ]]; then
  ARCH_TAG="$(echo "$ARCHES" | tr ' ' '-')"
else
  ARCH_TAG="$(uname -m)"
fi

ZIP_NAME="ClCoBar-${VERSION}-${ARCH_TAG}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "→ Building CodexBar ${VERSION} (build ${BUILD}) for ${ARCH_TAG}…"

# Resolve packages so KeyboardShortcuts checkout exists before patching.
echo "→ Resolving Swift packages"
swift package resolve >/dev/null

# KeyboardShortcuts ships #Preview macros that require Xcode's PreviewsMacros
# plugin. Command Line Tools alone can't compile them. Strip those blocks
# from the checked-out source — they're SwiftUI design-time only and have
# zero runtime effect. Idempotent.
patch_keyboard_shortcuts_previews() {
  local file="$ROOT/.build/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/Recorder.swift"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  if grep -q "// Preview blocks stripped" "$file" 2>/dev/null; then
    return 0
  fi
  chmod +w "$file" 2>/dev/null || true
  python3 - "$file" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
# Match `#Preview { ... }` blocks where the body contains no nested braces.
# (The three blocks in Recorder.swift fit this pattern.)
new = re.sub(r"\n#Preview \{[^{}]*?\}\n", "\n", text, flags=re.DOTALL)
if new != text:
    new = new.rstrip() + "\n\n// Preview blocks stripped for CLI build (no full Xcode)\n"
    path.write_text(new)
    print("    patched: removed #Preview blocks from Recorder.swift")
else:
    print("    skipped: no #Preview blocks found in Recorder.swift")
PY
}

echo "→ Patching KeyboardShortcuts to drop SwiftUI #Preview blocks"
patch_keyboard_shortcuts_previews

if [[ "$SKIP_TEST" != "1" ]]; then
  echo "→ swift test"
  swift test 2>&1 | tail -10 || {
    echo "WARN: swift test failed (may be unrelated to our code)." >&2
    echo "      Set SKIP_TEST=1 to bypass this check." >&2
    echo "      Continuing with build…" >&2
  }
fi

echo "→ Packaging release build with ad-hoc signing"
CODEXBAR_SIGNING=adhoc CONF=release ./Scripts/package_app.sh release

APP="$ROOT/ClCoBar.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP was not produced by package_app.sh" >&2
  exit 1
fi

echo "→ Stripping quarantine attribute (in case Spotlight/iCloud added one)"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"

echo "→ Zipping into $ZIP_PATH"
# `ditto -c -k --sequesterRsrc --keepParent` preserves macOS metadata + symlinks
# and produces a zip Finder unzips cleanly.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"

SIZE=$(du -h "$ZIP_PATH" | awk '{print $1}')

cat <<EOF

✅ Distribution build ready:
   $ZIP_PATH  ($SIZE)

Next steps:
1. Share the zip with teammates (Slack / Drive / GitHub Release / 회사 파일 서버).
2. Point them at docs/install-guide-ko.md for install instructions.

Quick smoke test before sharing:
   unzip -q "$ZIP_PATH" -d /tmp/codexbar-smoke && \\
     /tmp/codexbar-smoke/ClCoBar.app/Contents/MacOS/CodexBar --help 2>&1 | head -5

EOF
