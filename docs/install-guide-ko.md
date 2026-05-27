# ClCoBar 팀 배포 / 설치 가이드 (한글)

이 문서는 **팀원에게 ClCoBar 슬림 빌드를 배포하고 설치하는 방법** 을 안내합니다.

- macOS 14 (Sonoma) 이상이면 누구나 설치 가능
- Xcode 나 개발 도구 설치 필요 없음 (받아서 드래그하면 끝)
- Apple Developer 계정 없이 ad-hoc 서명만으로 동작

---

## 1. 배포자(빌드 담당) 가 한 번 해야 할 일

### 1-1. 배포용 zip 만들기

```bash
cd /Users/madup/Developer/CodexBar
./Scripts/build_for_distribution.sh
```

성공하면:

```
✅ Distribution build ready:
   dist/ClCoBar-1.3.2-arm64.zip  (5.4M)
```

기본은 **현재 빌드 머신 아키텍처만** 빌드합니다 (대부분 `arm64`).

### 1-2. (선택) Universal 빌드 — Intel + Apple Silicon 모두

```bash
ARCHES="arm64 x86_64" ./Scripts/build_for_distribution.sh
```

회사에 Intel Mac 사용자가 섞여 있다면 이걸로. 빌드는 약 2 배 걸립니다.

### 1-3. 팀에 공유

`dist/ClCoBar-<version>-<arch>.zip` 파일을 다음 중 하나로 공유:

- 사내 Slack / 채팅 채널에 직접 업로드
- Google Drive / Dropbox / Notion 첨부
- 사내 파일 서버 / S3 / Artifactory
- GitHub Release (회사 GitHub 가 있다면)

함께 이 가이드 (`docs/install-guide-ko.md`) 의 **2. 설치자 절차** 부분 링크나 사본을 같이 전달하세요.

### 1-4. 새 버전 빌드할 때 버전 번호 올리기

`version.env` 파일을 수정:

```
MARKETING_VERSION=1.2.4
BUILD_NUMBER=72
```

수정 후 `./Scripts/build_for_distribution.sh` 다시 실행.

---

## 2. 설치자(팀원) 절차

### 방법 A — 드래그 앤 드롭 (가장 쉬움) ⭐

**3 단계로 끝:**

1. **zip 다운로드** — 받은 `ClCoBar-*.zip` 을 더블클릭해서 압축 풀기 (`ClCoBar.app` 이 생김)

2. **응용 프로그램 폴더로 드래그** — `ClCoBar.app` 을 `Applications` 폴더로 끌어다 놓기

3. **첫 실행** — 응용 프로그램에서 ClCoBar 우클릭 → "**열기**" → 보안 경고 창이 뜨면 "**열기**" 한 번 더 클릭
   - ⚠️ 그냥 더블클릭하면 "확인되지 않은 개발자" 라며 차단됩니다. **반드시 첫 실행은 우클릭 → 열기**.
   - 한 번만 이렇게 열면 그 다음부터는 일반적으로 더블클릭으로 실행됩니다.

성공하면 메뉴바 우측 상단에 **Claude / Codex 두 개의 pill 아이콘** 이 나란히 나타납니다. 각 pill 은 배터리처럼 잔여량(또는 사용량) 을 시각화하고 옆에 다음 리셋까지 남은 시간(예: `5h`) 을 표시합니다.

### 방법 B — 터미널 한 번에 (편한 사람용)

zip 을 `~/Downloads` 에 받은 후, 터미널에서:

```bash
# 다운로드 받은 zip 이름은 환경에 맞게 변경
ZIP="$HOME/Downloads/ClCoBar-1.3.2-arm64.zip"
bash <(cat <<'INSTALL'
set -e
ZIP="${ZIP:?}"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto -x -k "$ZIP" "$STAGE"
pkill -x CodexBar 2>/dev/null || true
rm -rf /Applications/ClCoBar.app
mv "$STAGE/ClCoBar.app" /Applications/
xattr -dr com.apple.quarantine /Applications/ClCoBar.app 2>/dev/null || true
codesign --force --deep --sign - /Applications/ClCoBar.app 2>/dev/null || true
open /Applications/ClCoBar.app
echo "✅ 설치 완료. 메뉴바 아이콘을 확인하세요."
INSTALL
)
```

### 방법 C — 빌드 담당이 같이 보낸 설치 스크립트 사용 (있다면)

배포자가 zip 옆에 `install_for_team.sh` 도 같이 보냈다면:

```bash
chmod +x ~/Downloads/install_for_team.sh
~/Downloads/install_for_team.sh ~/Downloads/ClCoBar-1.3.2-arm64.zip
```

스크립트 없이 zip 만 받았는데 터미널을 쓰고 싶다면 **방법 B** 사용.

---

## 3. 설치 후 첫 설정

### 3-1. Claude 로그인

가장 쉬운 방법은 터미널에서 `claude` CLI 한 번 실행해 OAuth 로그인하기 — ClCoBar 가 macOS Keychain 의 `Claude Code-credentials` 를 자동으로 읽습니다.

만약 ad-hoc 서명 빌드라 Keychain 접근이 거부되면:
1. 메뉴바 pill 클릭 → "**환경설정...**" 또는 ⌘,
2. 좌측 **Providers → Claude** 선택
3. 인증 경로 중 하나 선택:
   - **OAuth** *(권장)* — Sign in 버튼으로 브라우저 OAuth (ClCoBar 자체 캐시)
   - **Web cookies (Automatic)** — claude.ai 브라우저 쿠키 자동 import
   - **CLI fallback** — `claude` CLI 가 설치되어 있으면 자동 fallback
4. 메뉴 다시 열어 Claude pill 이 잔여량을 표시하면 성공

### 3-2. Codex 로그인

1. 터미널에서 `codex` 한 번 실행해서 로그인 → `~/.codex/auth.json` 생성
2. ClCoBar 가 자동으로 인식 — 메뉴 바닥의 **"새로고침"** (⌘R) 한 번 클릭
3. Codex pill 이 잔여량을 표시하면 성공

### 3-3. 자동 시작 (선택)

매번 컴퓨터 켤 때 자동 실행되게 하려면:

- 환경설정 → **일반** → "**로그인 시 시작**" 체크

---

## 4. 알려진 이슈 / 자주 묻는 질문

### Q. "확인되지 않은 개발자라 열 수 없습니다" 가 뜸

A. 회사 내부 빌드라 Apple 정식 서명이 없어서 그렇습니다. **방법 A 의 3단계** 처럼 **우클릭 → 열기** 로 첫 실행하면 됩니다.

또는 시스템 설정 → 개인정보 보호 및 보안 → 맨 아래 "확인 없이 열기" 클릭.

### Q. "손상된 앱이라 휴지통으로 이동해야 합니다" 가 뜸

A. macOS Gatekeeper 의 quarantine 이 걸린 상태입니다. 터미널에서:

```bash
xattr -dr com.apple.quarantine /Applications/ClCoBar.app
```

실행 후 다시 시도. (방법 B / C 스크립트는 이걸 자동으로 해줍니다.)

### Q. 빌드 담당이 ARM 빌드만 줬는데 내 맥은 Intel 임

A. 빌드 담당에게 `ARCHES="arm64 x86_64"` 옵션으로 universal 빌드 요청. 또는 본인 머신에서 직접 빌드 (Xcode 정식판 없이 Command Line Tools + Swift 6 만 있어도 가능 — 스크립트가 KeyboardShortcuts 의 `#Preview` 매크로 이슈를 자동 패치):

```bash
git clone <repo-url> CodexBar && cd CodexBar
./Scripts/build_for_distribution.sh
```

### Q. 메뉴바에 아이콘이 안 보임

A. 다음 순서로 확인:
1. 메뉴바 공간 부족 — 시계나 시스템 아이콘 옆이 꽉 찼는지 확인 (control center 에서 정리)
2. 앱이 실행 중인지 확인: 터미널에서 `pgrep -lf CodexBar`
3. 강제 재시작:
   ```bash
   pkill -x CodexBar || true
   open -n /Applications/ClCoBar.app
   ```

### Q. 인증/Keychain 프롬프트가 자주 뜸

A. Preferences → Providers → Claude → **Keychain prompt policy** 를 `Only on user action` (기본값) 으로 두세요. 백그라운드 갱신 때마다 프롬프트가 뜬다면 `Always allow` 는 절대 선택하지 말고, 한 번 `Only on user action` 으로 바꾸고 Claude 인증을 다시 한 번 완료.

### Q. 사용량이 갱신 안 됨

A. 메뉴 바닥의 "**새로고침**" (⌘R) 클릭. 그래도 안 되면 해당 provider 의 인증이 만료된 것일 수 있으니 환경설정에서 재로그인.

### Q. 갑자기 사용량이 멈춰있고 "Rate limited" 비슷한 메시지가 보임

A. Anthropic OAuth API 의 rate limit (HTTP 429) 에 걸린 상태. ClCoBar 가 자동으로 **10 분 backoff** 를 적용하므로 그 사이 메뉴를 여러 번 열어도 추가 호출은 발생하지 않습니다. 10 분 후 자동으로 정상화됩니다. 자주 발생하면 환경설정 → 일반 → **새로고침 주기** 를 `15분` 또는 `30분` 으로 늘리세요.

### Q. 업데이트는 어떻게 받음?

A. 이 슬림 포크는 자동 업데이트(Sparkle) 가 비활성화되어 있습니다. 빌드 담당이 새 zip 을 공유하면 **방법 A / B / C** 중 하나로 다시 설치하면 됩니다 (기존 앱은 자동 교체됨).

---

## 5. 제거(uninstall) 방법

```bash
pkill -x CodexBar 2>/dev/null || true
rm -rf /Applications/ClCoBar.app
# (선택) 설정 / 캐시도 함께 삭제 — 내부 디렉토리명은 모두 CodexBar
rm -rf ~/Library/Application\ Support/CodexBar
rm -rf ~/Library/Caches/CodexBar
rm -rf ~/.codexbar
```

Keychain 항목까지 정리하려면 키체인 접근.app → "codexbar" 검색해서 항목 삭제.

---

## 6. 더 자세한 사용법

- 일반 사용법 / Claude·Codex 옵션 상세: [`docs/usage-guide-ko.md`](usage-guide-ko.md)
- Claude provider 데이터 흐름: [`docs/claude.md`](claude.md)
- Codex provider 데이터 흐름: [`docs/codex.md`](codex.md)
- 개발자 가이드 / 빌드 컨벤션: [`AGENTS.md`](../AGENTS.md)
