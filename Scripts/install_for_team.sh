#!/usr/bin/env bash
# Install ClCoBar.app from a downloaded zip.
#
# Usage:
#   curl -L <link> -o ~/Downloads/CodexBar.zip
#   bash <(curl -fsSL <link-to-this-script>) ~/Downloads/CodexBar.zip
#
# Or after downloading the zip manually:
#   ./install_for_team.sh ~/Downloads/CodexBar-1.5.8-arm64.zip
#
# If no path is given, scans ~/Downloads for the newest CodexBar-*.zip.

set -euo pipefail

ZIP_PATH="${1:-}"

if [[ -z "$ZIP_PATH" ]]; then
  ZIP_PATH=$(ls -t "$HOME/Downloads"/CodexBar-*.zip 2>/dev/null | head -1 || true)
  if [[ -z "$ZIP_PATH" ]]; then
    echo "ERROR: zip 파일을 찾지 못했습니다." >&2
    echo "사용법: $0 <path-to-CodexBar.zip>" >&2
    echo "또는 다운로드 폴더(~/Downloads)에 'CodexBar-*.zip' 을 두고 다시 실행하세요." >&2
    exit 1
  fi
  echo "→ 다운로드 폴더에서 발견: $ZIP_PATH"
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "ERROR: 파일이 없습니다: $ZIP_PATH" >&2
  exit 1
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

echo "→ 압축 풀기"
ditto -x -k "$ZIP_PATH" "$STAGE"

APP_PATH=$(find "$STAGE" -maxdepth 3 -name 'ClCoBar.app' -type d | head -1)
if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: zip 안에서 ClCoBar.app 을 못 찾았습니다." >&2
  exit 1
fi

if [[ -d /Applications/ClCoBar.app ]]; then
  echo "→ 기존 /Applications/ClCoBar.app 종료 시도"
  pkill -x CodexBar 2>/dev/null || true
  sleep 1
  echo "→ 기존 앱 제거"
  rm -rf /Applications/ClCoBar.app
fi

echo "→ /Applications 로 이동"
mv "$APP_PATH" /Applications/ClCoBar.app

echo "→ Gatekeeper quarantine 속성 제거 (서명되지 않은 앱이라도 바로 실행 가능하게)"
xattr -dr com.apple.quarantine /Applications/ClCoBar.app 2>/dev/null || true

echo "→ Ad-hoc 재서명 (개발자 ID 없이도 macOS Gatekeeper 통과)"
codesign --force --deep --sign - /Applications/ClCoBar.app 2>/dev/null || \
  echo "  WARN: codesign 실패 — 보안 정책에 따라 첫 실행 시 우클릭→열기 가 필요할 수 있습니다."

echo "→ 실행"
open /Applications/ClCoBar.app

cat <<'EOF'

✅ 설치 완료!

확인 사항:
- 메뉴바 상단에 CodexBar 아이콘이 보이는지 확인
- 첫 실행 시 macOS 보안 경고가 뜨면:
  1) 시스템 설정 → 개인정보 보호 및 보안 → "확인 없이 열기" 클릭
  2) 또는 Finder → 응용 프로그램 → CodexBar 우클릭 → 열기 → "열기" 클릭

다음 단계:
- 아이콘 클릭 → Preferences → Providers → Claude / Codex 로그인
- 자세한 사용법: README.md 또는 docs/install-guide-ko.md 참조

EOF
