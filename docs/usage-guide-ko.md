# ClCoBar 사용 가이드 (Claude + Codex slim fork)

> 이 문서는 슬림화된 개인 포크를 위한 빠른 사용 안내입니다. 원본의 다중 provider 안내는 모두 제거되었습니다.

---

## 1. 빌드 및 첫 실행

### 사전 요구사항

- macOS 14 (Sonoma) 이상
- Xcode 16 이상 (Swift 6 툴체인 포함)

### 첫 실행

```bash
cd /Users/madup/Developer/CodexBar
./Scripts/compile_and_run.sh
```

이 스크립트가 하는 일:

1. 기존에 떠 있는 `ClCoBar.app` 을 종료
2. `swift build` + `swift test`
3. `Scripts/package_app.sh` 로 `.app` 번들 생성
4. `ClCoBar.app` 재실행 + 정상 기동 확인

성공하면 메뉴바 우측 상단에 **ClCoBar 아이콘**이 보입니다.

### 디버그 빌드만 빠르게

```bash
swift build           # 디버그 빌드
swift build -c release  # 릴리스 빌드
swift test            # 테스트
```

> ⚠️ **알려진 툴체인 이슈**: 명령행 `swift build` 는 KeyboardShortcuts 패키지의 `#Preview` 매크로(`PreviewsMacros`) 를 못 찾아 마지막에 에러를 띄울 수 있습니다. 이는 Xcode 가 제공하는 매크로 플러그인을 CLI 가 못 찾기 때문이며 **앱 동작 자체에는 영향이 없습니다**. 우회: Xcode 앱에서 직접 빌드하거나, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build` 를 시도해 보세요.

---

## 2. 메뉴바 아이콘 보는 법

메뉴바 아이콘은 **활성화된 provider 의 잔여량을 한 눈에** 보여주는 작은 게이지입니다.

- **막대 채워짐 비율** = 가장 임박한 reset window 의 사용률
- **숫자/텍스트 라벨** (Preferences → 디스플레이에서 켤 수 있음) = 남은 % 또는 reset 까지 시간
- **희미해진 아이콘** = 데이터가 stale 하거나 오류 상태
- **빨간 점/배지** = provider 서비스 인시던트 감지됨

아이콘을 **클릭** 하면 메뉴 팝오버가 열립니다. 여기서 Claude / Codex 카드를 확인합니다.

---

## 3. Claude 사용량 추적

### 인증 경로

Claude 는 4 가지 데이터 경로를 자동 선택 (자동 우선순위: OAuth → CLI → Web):

| 경로 | 설명 | 설정 방법 |
|---|---|---|
| **OAuth API** *(권장)* | Claude OAuth 토큰을 그대로 사용해 공식 사용량 API 호출 | Preferences → Providers → Claude → "Sign in with OAuth" |
| **Web API (browser cookies)** | claude.ai 의 브라우저 세션 쿠키 재사용 | Preferences → Providers → Claude → Cookie source: Automatic 또는 Manual |
| **CLI PTY** | 로컬 `claude` CLI 를 PTY 로 띄워 `/usage` 결과 파싱 | `claude` CLI 가 PATH 에 있으면 자동 fallback |
| **Admin API** | Anthropic Admin API key 로 조직 사용량/비용 조회 | Preferences → Providers → Claude → Admin API key 입력 (`sk-ant-admin...`) |

### 시나리오별 권장 설정

- **개인 Pro/Max 플랜**: OAuth 만 켜 두면 충분. 5시간 세션 + 주간 + 모델별 사용량이 깔끔하게 표시됩니다.
- **claude.ai 만 쓰고 CLI 안 씀**: Web API (Cookie: Automatic) 만 켜기. 브라우저 로그인 상태를 자동 import.
- **회사/팀 조직 비용 추적**: Admin API key 추가. 일/주/월 spend + 메시지/토큰 카운트가 인라인 차트로 표시.

### Cookie source 모드 차이

- **Automatic** (기본): Safari → Chrome → Firefox 순서로 `claude.ai` 쿠키 자동 import. macOS Keychain 에 캐시.
- **Manual**: 브라우저 개발자 도구에서 `Cookie:` 헤더를 복사해 직접 붙여넣기. 다중 계정을 쓰거나 자동 import 가 안 될 때.

### Keychain 프롬프트 정책

Preferences → Providers → Claude → Keychain prompt policy:

- `Only on user action` (기본 권장): 사용자가 직접 액션할 때만 Keychain 프롬프트
- `Always allow`: 백그라운드 자동 갱신에도 프롬프트 허용 (Touch ID/암호 자주 뜸)
- `Never prompt`: 절대 안 띄움 (OAuth 가 풀리면 수동 재로그인 필요)

---

## 4. Codex 사용량 추적

### 인증 경로

Codex 는 3 가지 데이터 경로 (자동 우선순위: OAuth → CLI RPC → OpenAI Web extras):

| 경로 | 설명 | 설정 방법 |
|---|---|---|
| **OAuth API** *(앱 기본)* | `~/.codex/auth.json` 의 OAuth 토큰으로 ChatGPT backend usage API 직접 호출 | `codex` CLI 로 한 번 로그인하면 자동 인식 |
| **Codex CLI RPC** | 로컬 `codex app-server` JSON-RPC 호출 | `codex` CLI 가 PATH 에 있으면 자동 fallback |
| **OpenAI Web extras** *(선택)* | `chatgpt.com/codex/settings/usage` 페이지를 hidden WebView 로 스크랩 | Preferences → Providers → Codex → OpenAI web extras 활성화 |

### 시나리오별 권장 설정

- **일반 사용**: OAuth 만 켜 두면 됨. 5시간 / 주간 rate limit + credits 잔량이 표시됩니다.
- **대시보드 extras (code review remaining, usage breakdown, credits history) 가 보고 싶을 때**: OpenAI web extras 켜기. ⚠️ 배터리/네트워크 부담 증가 — "Battery saver" 옵션도 함께 켜기 권장.
- **OAuth 인증 안 되고 CLI 만 가능한 환경**: CLI RPC 가 자동으로 잡힙니다.

### OpenAI Web extras 활성화

1. Preferences → Providers → **Codex**
2. **OpenAI web extras** 토글 ON
3. **OpenAI cookies**: `Automatic` 권장
   - Automatic 모드는 Safari → Chrome → Firefox 순으로 `chatgpt.com`/`openai.com` 쿠키 import
   - Manual 모드는 브라우저에서 `Cookie:` 헤더 복사 후 붙여넣기
4. (선택) **Battery saver** 켜면 background refresh 가 가벼워짐, 수동 refresh 는 그대로 동작

### Codex CLI 미설치 시

Codex CLI 가 없으면 OAuth 만 동작합니다 (CLI RPC fallback 비활성). 대부분의 사용 케이스에는 OAuth 만 켜져 있으면 충분합니다.

---

## 5. Preferences 패널 안내

`Preferences...` 메뉴를 열면 좌측 사이드바에 다음 섹션이 있습니다:

| 패널 | 용도 |
|---|---|
| **General** | 메뉴바 텍스트 표시 모드, 시작 시 자동 실행, 알림 전반 |
| **Providers → Claude** | Claude 활성/비활성, 인증 소스 선택 (OAuth/Web/CLI), Cookie source, Admin API key, Keychain 정책 |
| **Providers → Codex** | Codex 활성/비활성, 인증 소스 선택, OpenAI web extras, OpenAI cookies (Automatic/Manual), Battery saver |
| **Display** | 메뉴바 아이콘 메트릭 표시 (% / time / 둘 다), 다크/라이트 모드 매핑 |
| **Advanced** | Keychain 접근 비활성화, 메뉴 새로고침 간격, 디버그 메뉴 활성화 등 |
| **Debug** *(Advanced 에서 활성 시)* | Provider 별 데이터 소스를 수동으로 강제 선택, raw 응답 보기 |
| **About** | 앱 버전 정보. (자동 업데이트는 제거됨) |

---

## 6. 자주 쓰는 시나리오

### 사용량 즉시 새로고침

- 메뉴바 아이콘 클릭 → 카드 헤더의 ⟳ 버튼 → 해당 provider 즉시 fetch
- 또는 메뉴 바닥의 "Refresh all" 클릭

### 5시간 세션 곧 리셋되는지 확인

각 카드의 "Session" 라인을 보면 남은 % + reset 까지 카운트다운이 표시됩니다. 메뉴바 아이콘 표시 모드를 "% remaining" 으로 설정하면 메뉴를 안 열어도 보입니다.

### 키보드 단축키로 메뉴 열기

Preferences → General → "Open menu shortcut" 에서 단축키 지정. (`KeyboardShortcuts` 라이브러리 사용 — 이 부분이 빌드 CLI 매크로 이슈를 일으키므로 Xcode 빌드를 권장)

### Claude 가 OAuth 실패할 때

1. Claude CLI 가 설치되어 있다면: 터미널에서 `claude` → 로그인 → 다시 ClCoBar 새로고침
2. 또는 Preferences → Claude → Cookie source: Automatic 으로 fallback 활성화 + claude.ai 브라우저 로그인
3. 최후 수단: Admin API key 발급해서 등록 (조직 단위 사용량만 보임)

### Codex 가 OAuth 인식 못 할 때

- `~/.codex/auth.json` 파일 존재 여부 확인 (`ls ~/.codex/`)
- 없으면 터미널에서 `codex` 한 번 실행 → 로그인 완료 후 ClCoBar 새로고침
- `auth.json` 의 `last_refresh` 가 8일 이상 지났으면 ClCoBar 가 자동 갱신 시도

---

## 7. 알려진 이슈 / 트러블슈팅

### `swift build` 가 `PreviewsMacros` 에러로 실패

CLI 가 Xcode 의 SwiftUI Preview 매크로 플러그인을 못 찾는 알려진 toolchain 이슈입니다. **앱 동작에는 영향 없음**. 우회:

```bash
# 옵션 1: Xcode 앱으로 직접 빌드
open Package.swift   # Xcode 에서 Run

# 옵션 2: DEVELOPER_DIR 명시
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
```

### Keychain 프롬프트가 자꾸 뜸

Preferences → Providers → Claude → Keychain prompt policy 를 `Only on user action` 으로. 그래도 뜨면 Advanced → "Disable Keychain access" 임시 활성화 후 다시 끄기.

### 메뉴바 아이콘이 안 보임

1. 메뉴바 공간 부족 — 시계나 알림 옆 아이콘을 정리
2. `ClCoBar.app` 이 정말 실행 중인지 확인: `pgrep -lf CodexBar`
3. 강제 재실행:
   ```bash
   pkill -x CodexBar || pkill -f ClCoBar.app || true
   open -n /path/to/ClCoBar.app
   ```

### 사용량이 갱신 안 됨

1. 메뉴 바닥 "Refresh all" 한 번 클릭
2. 인증 상태 확인 — 카드에 "Login required" 또는 비슷한 배지 떠 있으면 해당 provider 의 인증 경로 재설정 필요
3. macOS 네트워크 권한 확인 — 시스템 설정 → 개인정보 보호 → 네트워크에서 ClCoBar 가 차단되어 있는지

### 비용/시간 계산이 이상함

Preferences → Advanced → Debug → "Force source" 로 OAuth / Web / CLI 를 각각 강제해서 어느 경로에서 문제 생기는지 격리. raw 응답은 Debug 패널에서 확인.

---

## 8. 개발자용 빠른 참조

### 코드 수정 후 검증

```bash
swift build
swift test
make check       # swiftformat + swiftlint --strict
./Scripts/compile_and_run.sh   # UI 회귀 확인
```

### 핵심 모듈 위치

| 위치 | 내용 |
|---|---|
| `Sources/CodexBarCore/Providers/Claude/` | Claude OAuth / CLI / Web fetcher |
| `Sources/CodexBarCore/Providers/Codex/` | Codex OAuth / CLI RPC / OpenAI dashboard 스크래퍼 |
| `Sources/CodexBarCore/OpenAIWeb/` | OpenAI 웹 대시보드 공통 모듈 (Codex 가 사용) |
| `Sources/CodexBar/` | macOS 앱 본체 (메뉴, Preferences, StatusItem) |
| `Sources/CodexBarClaudeWatchdog/` | Claude CLI 워치독 데몬 |
| `Sources/CodexBarClaudeWebProbe/` | Claude 웹 세션 헬스체크 |
| `Tests/CodexBarTests/` | XCTest + SwiftTesting 스위트 |

### 자주 쓰는 grep

```bash
# Claude 인증/사용량 관련 코드 찾기
grep -rn "ClaudeOAuth\|ClaudeUsage\|ClaudeStatusProbe" Sources/

# Codex OAuth 토큰 처리
grep -rn "auth.json\|ChatGPT-Account-Id" Sources/

# 메뉴 카드 렌더링
grep -rn "MenuCardView\|UsageMenuCardView" Sources/
```

### 빌드 산출물

- 디버그: `.build/debug/ClCoBar.app` (스크립트가 패키징)
- 릴리스: `.build/release/ClCoBar.app`
- 메인 실행파일: `Sources/CodexBar/` 타겟 → `.build/<config>/ClCoBar`

---

## 9. 슬림화로 변경된 부분 요약

원본 `steipete/ClCoBar` 대비:

| 항목 | 상태 |
|---|---|
| Claude / Codex provider | ✅ 유지 (변경 없음) |
| OpenAI 웹 대시보드 (Codex 의존) | ✅ 유지 |
| Claude Watchdog / WebProbe | ✅ 유지 |
| 41 개 다른 provider | ❌ 제거 |
| CLI 타겟 (`codexbar config ...`) | ❌ 제거 |
| WidgetKit 위젯 | ❌ 제거 |
| Sparkle 자동 업데이트 | ❌ 제거 |
| 멀티-provider 가정 UI | ✅ 단순화됨 |
| 다른 provider 안내 문서 | ❌ 제거 |
| `appcast.xml`, `CHANGELOG.md`, 홈페이지 자산 | ❌ 제거 |
| GitHub Actions CI | ❌ 제거 |

**즉, 메뉴바 앱은 그대로 잘 동작하지만 코드베이스가 ~10만 줄 가벼워졌고, 빌드/유지보수가 훨씬 쉬워졌습니다.**

---

## 10. 추가 자료

- 깊이 있는 Claude 데이터 흐름: [`docs/claude.md`](claude.md), [`docs/CLAUDE.md`](CLAUDE.md), [`docs/refactor/`](refactor/)
- Codex OAuth 내부 구조: [`docs/codex.md`](codex.md), [`docs/codex-oauth.md`](codex-oauth.md)
- 아키텍처 개요: [`docs/architecture.md`](architecture.md)
- 개발 환경 셋업: [`docs/DEVELOPMENT.md`](DEVELOPMENT.md), [`docs/DEVELOPMENT_SETUP.md`](DEVELOPMENT_SETUP.md)
- Keychain 트러블슈팅: [`docs/KEYCHAIN_FIX.md`](KEYCHAIN_FIX.md)
- 리포 컨벤션 (포매팅/린팅/테스트 규칙): [`AGENTS.md`](../AGENTS.md)
