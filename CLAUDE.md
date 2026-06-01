# ClCoBar — Claude Notes

Personal fork of `steipete/CodexBar`. Tracks **only Claude + Codex** usage in the macOS menu bar. UI is Korean-only.

## 핵심 규칙

- **표시명 ClCoBar**, **내부명 CodexBar 유지**. Info.plist `CFBundleDisplayName/Name` 만 ClCoBar. Swift 모듈명 (`CodexBar`, `CodexBarCore`, `CodexBarClaudeWatchdog`, `CodexBarClaudeWebProbe`, `CodexBarMacros`, `CodexBarMacroSupport`) · 파일 경로 (`/Applications/ClCoBar.app`, `~/.codexbar/`, `~/Library/Application Support/CodexBar/`) · UserDefaults suite · Keychain entry 는 전부 `CodexBar`. 변경 시 Keychain ACL / 캐시가 풀린다.
- **한국어 전용.** `Sources/CodexBar/Localization.swift` 가 항상 `ko.lproj` 우선, `en.lproj` 폴백. 언어 picker UI 없음. `CodexbarApp.applyLanguagePreference` 가 `AppleLanguages=["ko"]` 강제. 영어로 둘 용어: `Claude`, `Codex`, `ClCoBar`, `API`, `OAuth`, `CLI`, `PTY`, `Cookie`, `Token`, `Keychain`, `MCP`, `Chrome/Safari/Firefox`, `GitHub`, 플랜명 `Pro/Max/Team/Enterprise`.

## 빌드 / 배포

- **Xcode 없이도 빌드 가능.** `./Scripts/build_for_distribution.sh` 가 자동으로 KeyboardShortcuts/Recorder.swift 의 `#Preview` 블록을 패치(매크로 플러그인 회피) 후 ad-hoc 서명 zip 생성 → `dist/ClCoBar-<ver>-<arch>.zip`. SKIP_TEST=1 로 swift test 건너뛰기 (PreviewsMacros 가 test 도 막음).
- **배포된 zip 내부 .app 이름은 `ClCoBar.app`** (Finder 에서는 ClCoBar 로 표시). 팀원 안내: `docs/install-guide-ko.md`. 첫 실행은 우클릭→열기 (ad-hoc 서명이라 Gatekeeper 경고).
- **사용자 코드 변경 후 재설치**: `pkill -x CodexBar; rm -rf /Applications/ClCoBar.app; ditto -x -k dist/ClCoBar-*.zip /tmp/cb && mv /tmp/cb/ClCoBar.app /Applications/ && xattr -dr com.apple.quarantine /Applications/ClCoBar.app && open /Applications/ClCoBar.app`.

## 버전 관리 (자동)

코드 작업이 끝나면 변경 범위를 보고 **`version.env`** 의 `MARKETING_VERSION` 을 다음 기준으로 올린다. `BUILD_NUMBER` 는 항상 +1.

- **PATCH (1.1.0 → 1.1.1)** — 버그 수정 / 문구·번역 변경 / 로컬라이제이션 / 작은 UI 보정 / 리팩토링만. 외부에서 보이는 동작이 거의 그대로일 때.
- **MINOR (1.1.0 → 1.2.0)** — 새 기능·옵션·토글 추가 / 메뉴 항목 추가 / 설정 화면에 새 섹션 / 의미 있는 UX 변화. 호환은 깨지 않는 추가성 변경.
- **MAJOR (1.1.0 → 2.0.0)** — 설정/UserDefaults 키 구조 변경으로 마이그레이션 필요 / 모듈/타겟 추가·제거 / 기능 대규모 재설계나 제거. 팀원이 재설치 후 설정을 다시 해야 하는 수준일 때.

판단 애매하면 보수적으로 한 단계 아래(예: MINOR ↔ PATCH 사이면 PATCH).

**버전을 올리면 같이 갱신해야 하는 파일** (한 군데라도 빠지면 안내가 어긋남):
- `version.env` — `MARKETING_VERSION`, `BUILD_NUMBER`
- `docs/install-guide-ko.md` — zip 파일명 예시 (`ClCoBar-<v>-arm64.zip`) + 1-4 절의 "다음 버전 예시" 도 한 칸씩 위로
- `docs/confluence-team-guide-ko.md` — "버전 히스토리" 표 맨 위에 새 행 추가 (버전 · 날짜 · 주요 변경 한 줄 요약). 팀원이 보는 가장 가시성 높은 문서라 빠뜨리면 즉시 티남.
- `Scripts/install_for_team.sh` — 주석의 사용 예시

버전 올린 후엔 기존 `dist/ClCoBar-<이전버전>-arm64.zip` 을 지우고 `./Scripts/build_for_distribution.sh` 로 새 zip 만든 뒤 본인 환경에도 재설치(`pkill ... && ditto ... && open ...`)까지 한 번에 끝낸다.

## 알려진 함정

- **`@Observable` nested-struct setter 버그.** `SettingsStore.defaultsState.X = newValue` 직접 변형은 `withMutation` 을 발화시키지 못해 SwiftUI 관찰자가 못 본다. 새 setter 추가 시 **반드시** copy-modify-reassign:
  ```swift
  var state = self.defaultsState
  state.X = newValue
  self.defaultsState = state
  ```
- **PreviewsMacros 툴체인 이슈.** CLI 환경에선 SwiftUI `#Preview` 매크로 플러그인을 못 찾는다. `build_for_distribution.sh` 가 자동 패치. 새 외부 의존 추가 시 같은 매크로 쓰면 패치 함수 확장 필요.
- **Anthropic OAuth rate-limit (HTTP 429).** `UsageStore+Refresh.swift` 가 fetch 결과에서 429 / `rate_limit` 인지 시 `rateLimitBackoffUntil[provider] = now+600s` (10분) backoff 등록. 메뉴 열기는 추가로 120s cooldown (`StatusItemController+Menu.swift:menuOpenRefreshCooldown`).
- **NSMenu provider 등록.** 각 status item 의 메뉴는 `menuProviders[ObjectIdentifier(menu)] = provider` 등록되어 있고, `menuWillOpen` 에서 그걸로 `selectedMenuProvider` 를 강제 snap + `menuVersions[menu]` 캐시 무효화. Claude pill 클릭 → Claude 카드, Codex pill 클릭 → Codex 카드 보장.
- **NSStatusItem 토글 패턴 (1.5.5 사건, 사용자 4번 불쾌).** 토글 OFF/ON 시 **절대로** `statusBar.removeStatusItem(item)` + 새 인스턴스 생성 패턴 쓰지 말 것. macOS status bar 의 짧은 시간 안 add → remove → add sequence 에 race 가 있어 **다른 NSStatusItem 의 visibility 까지 깨뜨림** (사용량 pill 토글이 Companion 캐릭터를 evict 시키는 cross-effect 의 진짜 원인). **인스턴스는 앱 lifetime 동안 한 번만 만들고 `isVisible` 토글만** (Apple 권장 패턴). 사용자 OFF vs macOS evict 구분 위해 controller 에 `userEnabled` flag 두고 watchdog 이 그 flag 존중. `statusBar.removeStatusItem` 은 wake recovery `recreateStatusItemsForVisibilityRecovery` 같은 진짜 evict 케이스에서만 호출.
- **Cross-broker 안티패턴 (같은 사건).** "토글 A 변경 시 status item B 의 visibility 도 강제 복구하자" 는 발상 (NotificationCenter broker / cascade recovery 등) **절대 추가 금지**. false-positive recovery loop 일으킴 — 토글 1번 = recovery 호출 3번 = destructive `recreateStatusItemsForVisibilityRecovery` 발화 가능 = 신생 status item 의 width=0 false-positive 가 또 recreate 발화 = 무한 loop. 두 status item 은 진짜 독립 동작이어야 하고 macOS evict 는 각자의 wake observer / 30초 heartbeat 가 잡음.
- **`isBlockedSnapshot` 의 `buttonWidth ≤ 0` 금지.** 신생 NSStatusItem 은 image set 직전 잠시 buttonWidth=0 인 정상 상태. 이걸 evict 로 판정하면 destructive recreate → 또 신생 → 무한 loop. evict 판정은 `button.window / screen nil` 만으로.
- **Visibility/Recovery fix 전에 step-by-step 시뮬레이션 필수.** 사용자가 정확한 시나리오 보고하면 (예: "프 OFF → ON → OFF → ON → 캐 OFF") 단계별로 머릿속에서 시뮬레이션해 정상 동작 검증한 *뒤에* fix push. 우회 fix (broker / cascade) 부터 추가하면 root cause 못 잡고 새 bug 만 만들어 사용자가 같은 문제로 여러 번 보고하게 됨.
- **NSStatusItem 보호 fix 는 두 컨트롤러 모두에 적용 (1.5.6/1.5.7 사건).** Companion (`CompanionStatusItemController`) 과 사용량 pill (`StatusItemController`) 은 별개 클래스라 한쪽에만 health check / fallback / recovery 적용하면 곧 반대편이 같은 문제로 사라짐. NSStatusItem 관련 보호 (image fallback, health check, recovery cascade) 추가 시 **반드시 두 컨트롤러 모두 동등 적용** 여부 self-review. `isBlockedSnapshot` / `MenuBarVisibilityWatcher` 도 두 컨트롤러 공통 진단 채널이라 거기 강화하면 양쪽 다 자동 cover.
- **사용자 토글 ON 경로에서 즉시 health check 필수 (1.5.8 사건).** instance lifetime 영구 유지 패턴 (1.5.5+) 의 부작용: 한 번 unhealthy stuck 상태가 되면 `isVisible` 토글만으로 못 풀림. 사용자가 직접 토글 OFF/ON 했을 때 즉시 health check + 필요 시 instance 재생성 보장해야 사용자 자가 복구 가능. Companion `setVisible(_:)` 의 `isStatusItemHealthy` 가드 + StatusItemController `handleSettingsChange` 끝의 `recoverInvisibleOrBlockedStatusItemsIfNeeded` 호출 두 경로 모두 필요. self-recovery (자기 자신만 다룸) 는 cross-broker (다른 controller 강제 호출) 와 다르므로 안전 — 1.5.3 의 false-positive loop 와 혼동하지 말 것.
- **60초 이상 blocked stuck = OS-level 가능성, 사용자 안내.** 우리 recovery 가 못 풀리는 케이스 (macOS Tahoe "Allow in Menu Bar" 자동 OFF 등) 대비. `recoverInvisibleOrBlockedStatusItemsIfNeeded` 가 60초 이상 동일 provider 가 blocked 면 `MenuBarVisibilityWatcher.presentGuidance` 발화해 사용자에게 시스템 설정 안내. 무한히 stuck 인 채 두지 않음.
- **외장 모니터 연결/해제 시 status bar overflow (1.5.9/1.5.10 사건).** 사용자가 외장 모니터 ↔ 맥북 내장 화면 사이를 전환하면 메뉴바 폭이 변함. macOS 가 폭 부족 시 overflow 항목을 hide 하는데 모니터 다시 연결해도 자동으로 안 돌려놓음. `NSApplication.didChangeScreenParametersNotification` 옵저버는 둘 다 컨트롤러에 있어야 하고 (`StatusItemController` + `CompanionStatusItemController`), screen change 시점에 **detection 우회 강제 recreate** (`forceRecreateAllEnabledProviders`) 사용. user-perceived 깜빡임은 모니터 변경 시점에 자연스러운 일부로 인지됨. `isBlockedSnapshot` 의 detection 자체도 `hasImage && buttonWidth <= 0` 조합 추가 — image fallback chain 보장 (1.5.6) 후 image 정상인데 width=0 은 명백히 OS-level hide. 신생 instance race 우려는 fallback image 가 항상 보장하므로 false-positive 안 됨.
- **최종 escape = process restart (1.7.0 사건).** 사용자가 manual recover button 클릭해도 status item 이 안 돌아오는 케이스 = macOS-level stuck. 우리 코드가 새 NSStatusItem 만들어도 macOS 가 거부하는 상태 — 어떤 detection/recovery/cascade 도 못 풀림. 진짜 최종 해결은 **process 자체 재시작** (`open -n -a` + `exit(0)`): 새 process 가 NSStatusBar 에 다시 register 하면서 OS-level stuck 완전 reset. `AppDelegate.forceRecoverAllMenuBarItems` 가 manual recover 시 단순 recreate → 1초 후 health check → 여전히 unhealthy 면 사용자 confirmation alert + 동의 시 자동 restart. 그동안 쌓아온 cascade (1.5.2 wake cascade, 1.5.9 screen change cascade) 는 모두 단발 호출로 단순화 (1.7.0) — heartbeat 15초 + manual button → process restart 의 3단 escalation 으로 충분히 cover.
- **자동 process restart escalation (1.7.2 사건).** Manual button 도 안 통하는 stuck + 사용자가 자리 비운 케이스: heartbeat 가 stuck 을 감지해도 복구가 못 풀고, 사용자가 manual button 누를 기회도 없음. 1.7.2 부터 **heartbeat 가 자동 process restart escalation 호출**: 사용량 pill 또는 Companion 이 2분 이상 stuck 이면 시스템 알림 post 후 `relaunchApp()` 자동 실행. 1시간 cooldown 으로 너무 자주 발화 방지 (`UserDefaults` key `menubar.autoRestart.lastAt`). 사용자가 manual button 누를 필요 없이 자동 복구 보장 — "외출 다녀왔는데 사라져 있고 manual 복구도 안 되더라" 케이스의 진짜 fix. `StatusItemController.hasAnyEnabledStuckLongerThan(seconds:)` + `CompanionStatusItemController.stuckDuration()` 양쪽에서 stuck 지속 시간 추적.
- **진짜 root cause 는 macOS 다중 디스플레이+노치 배치 버그 (1.8.2 사건 — 실측으로 확정).** 1.5.5~1.8.0 의 모든 패치는 **사후 로그 없이 추론만** 했다는 게 근본 문제였다. 1.8.1 에서 파일 로그 강제 활성화 (`~/Library/Logs/CodexBar/CodexBar.log`) + status item 전체 geometry 덤프 (`MenuBarVisibilityWatcher.diagnosticDescription`) 를 넣고 실측하니 두 가지 실패 모드가 드러났다. **(중요: OSLog 는 이 LSUIElement 프로세스에서 unified log 에 안 잡히고 info 레벨은 보존도 안 됨 → 사후 분석은 반드시 파일 로그로.)** ① **orphan** — 사용량 pill/캐릭터는 서로 다른 화면에 호스팅될 수 있고 (pill=외장, 캐릭터=빌트인), 호스팅 화면이 사라지면 `button.window.screen == nil`. 우리 `.recreate` 가 감지는 하지만 **`removeStatusItem`+새 인스턴스로도 살아있는 화면에 재배치 안 됨** (새 항목도 `screen=nil`, stable 단일 화면에서조차). ② **hidden** — 항목이 `isVisible=true` + window/screen/`button.frame.width`>0 + 정상 image 인데 실제론 안 보임. **어떤 NSStatusItem 속성으로도 구분 불가** → detection 기반 자동/수동 복구가 원천 무력 (auto-restart 도 안 떠서 `menubar.autoRestart.lastAt` 키가 계속 없었던 이유). **교훈: NSStatusItem 속성 검사(`isBlockedSnapshot`/`recoveryAction`)로는 이 버그를 못 잡는다. in-process recreate 도 못 고친다. 유일하게 확실한 복구는 새 프로세스의 NSStatusBar 재등록 = process 재시작.** 1.8.2 fix: (A) 디스플레이 NSScreenNumber **집합이 실제로 바뀌면** (`AppDelegate.handleDisplayConfigurationChange`, screenParams+didWake 양쪽 관측, 해상도/배치만 바뀐 spurious 는 무시) 2.5초 정착 후 `relaunchApp()` 자동 재시작 — `canSafelyRelaunch` (메뉴 열림/로그인 중) 가드 + 15초 cooldown (`menubar.displayChangeRestart.lastAt`) 으로 loop 방지. baseline `lastDisplaySet` 을 launch 시 현재 집합으로 초기화해 재시작 직후 자기 재시작 loop 방지. (B) "메뉴바 아이콘 복구" 버튼 (`forceRecoverAllMenuBarItems`) 은 detection 없이 **항상 재시작** — hidden 모드도 100% 복구. 진단 계측 (파일 로그 + geometry 덤프) 은 fix 검증 위해 당분간 유지.
- **재시작마다 "다른 앱 데이터 접근" TCC 프롬프트 → 불필요한 브라우저 쿠키 스캔 게이팅 (1.8.4 사건).** 디스플레이 변경 자동 재시작(1.8.2)이 들어간 뒤 모니터 연결/분리마다 macOS Sequoia/Tahoe 의 **"'ClCoBar'이(가) 다른 앱의 데이터에 접근하려고 합니다"** 권한 창이 떴다. 원인: Claude 사용량 fetch 의 `.auto` plan 계산(`ClaudeProviderDescriptor.makePlanningInput` + `ClaudeUsageFetcher.makeAutoFetchPlan`)이 `hasWebSession` 을 구하려고 **매 refresh 마다 `ClaudeWebAPIFetcher.hasSessionKey(browserDetection:)` 로 브라우저(Chrome/Edge/ChatGPT Atlas) 쿠키를 스캔** — OAuth 로 동작하는데도. 브라우저 데이터 디렉토리 접근이 TCC "다른 앱 데이터" 프롬프트를 유발하고, **ad-hoc 서명 앱은 그 동의가 launch 간 유지 안 돼** 재시작(=`open -n` 새 프로세스)마다 다시 물었다. 장수 프로세스 시절엔 시작 시 1회뿐이라 안 보였는데 자동 재시작과 겹쳐 표면화. fix: **Web 단계가 실제로 쓰일 수 있을 때만 스캔** — 명시적 `.web` 소스 / manual cookie header(문자열 파싱, 스캔 아님) / `webExtras` 켜짐 / `!hasOAuth && !hasCLI`. OAuth·CLI 가 있으면 브라우저를 안 긁는다. 로그로 검증: 수정 후 OAuth fetch 2회 동안 `browser-cookie-gate` 0회. 교훈: 브라우저/타앱 데이터 접근은 Sequoia+ 에서 TCC 프롬프트 비용이 있으니 **꼭 필요할 때만** (provider 가 cookie 소스를 실제로 쓸 때만) 트리거할 것.
- **무조건 재시작 → 감지될 때만 재시작 (1.8.5 사건).** 1.8.4 로 CodexBar 자체 브라우저 스캔은 제거했지만 TCC "다른 앱 데이터" 프롬프트가 여전히 모니터 도킹/언도킹마다 떴다. 로그로 확인한 진짜 원인: ad-hoc 서명 앱은 TCC grant 가 launch 간 유지되지 않아, 자동 재시작(1.8.2)이 매 디스플레이 변경마다 새 프로세스 cold-start 를 만들고 그게 Claude 자격증명/CLI(`~/.claude`, `claude` PTY)에 접근할 때마다 macOS 가 다시 묻는 **구조적** 결과 (정식 서명 없이는 제거 불가). 트레이드오프(신뢰성↔프롬프트)에서 사용자가 "감지될 때만 재시작" 선택. fix: `relaunchForDisplayChangeIfSafe` 가 재시작 전에 `StatusItemController.hasAnyBlockedEnabledStatusItem()` + `CompanionStatusItemController.isStuckWhileUserEnabled()` 로 **실제 깨졌는지 확인** — 멀쩡하면 skip. 대부분의 도킹/언도킹은 아이콘이 멀쩡해 재시작·프롬프트 없음. 단 "정상 속성인데 안 보이는" 미감지 mode-2 (캐릭터 hidden 케이스)는 자동으로 못 잡으므로 수동 '메뉴바 아이콘 복구' 버튼(항상 재시작)이 escape. 2분 stuck auto-restart(1.7.2)는 detectable-stuck 안전망으로 유지.
- **디스플레이 변경 자동 재시작의 cold-start 거칠음 → warm-start 캐시 (1.8.3 사건).** 1.8.2 재시작은 새 프로세스라 in-memory `snapshots` 가 비어 첫 fetch 전까지 pill 이 빈 채로 보이고, cold-start 첫 fetch 가 자격증명 로드 전 transient 실패하면 "인증 만료" 문구가 잠깐 떴다 (사용자 보고). fix: `UsageSnapshotCache` (`~/Library/Caches/CodexBar/usage-snapshots-v1.json`) 에 성공한 `UsageSnapshot` 을 저장 (`saveUsageSnapshotCache()` — 개별 provider refresh 성공 시 + `persistWidgetSnapshot`) → `UsageStore.init` 에서 12시간 이내 캐시를 `self.snapshots` 로 복원. pill 즉시 렌더 + prior data 존재로 `ConsecutiveFailureGate` 가 cold-start 첫 에러 억제 (`UsageStore+Refresh` 의 `preservesPriorData && !shouldSurface` 경로) → 문구 flash 제거. 주의: persistWidgetSnapshot 은 전체 `refresh()` 후에만 호출되므로 startup 직후 누락을 막으려 개별 success 경로에도 save 를 걸어야 함. (별개 이슈: ad-hoc 서명은 재빌드마다 바뀌어 Keychain ACL 이 무효화 → 재설치 직후 Keychain 허용 창 1회. 안정 빌드 + "항상 허용" 이면 재발 안 함.)
- **복구 메커니즘 자체가 race 를 일으킨 진짜 root cause (1.8.0 사건 — 1.5.5~1.7.2 의 종착점, 단 1.8.2 에서 더 깊은 원인 발견).** 절전/모니터 재연결 시 사용량 pill·캐릭터가 사라지고 복구도 안 듣던 11개 패치의 누적 원인은 **복구 코드 자체**였다. wake (`didWake`/`screensDidWake`) 1.5s, screen-change 750ms 시점에 `StatusItemController` 와 `CompanionStatusItemController` 가 **둘 다 같은 지연으로 동시에 `removeStatusItem`+재생성**을 실행 → 위에 적은 1.5.5 의 add→remove→add race 를 매 이벤트마다 의도적으로 유발 → 한 status item 이 invisible 로 떨어짐. 자동/수동 복구 (`forceRecreateAllEnabledProviders`, heartbeat) 도 같은 racy 패턴이라 재유발 → 수렴 못 함 ("복구가 안 된다"의 정체). **핵심 교훈: 복구에 `removeStatusItem` 을 기본 경로로 쓰지 말 것.** 1.8.0 fix: (1) `MenuBarVisibilityWatcher.recoveryAction(snapshot:)` 가 복구를 4단계 (`none`/`reassertVisible`/`redraw`/`recreate`) 로 분류 — **`window`/`screen` 이 살아있는 overflow-hide (width=0/image 깨짐) 는 `removeStatusItem` 없이 image 재설정 + isVisible 재확정으로 비파괴 복구**, 진짜 evict (`window`/`screen` nil) 만 recreate. (2) wake/screen/active burst 를 컨트롤러당 **단일 coalescing task** (`requestStatusItemRecovery`/`requestRecovery`, cancel+reschedule) 로 합쳐 중복 recreate 제거. (3) recreate 는 `recreateCooldown` (30s) + `redrawEscalationThreshold` (비파괴로 20s 안 풀릴 때만 승격) 으로 gate. (4) 두 컨트롤러 복구 지연을 **stagger** (pill: active 0s/screen 0.75s/wake 1.5s, Companion: active 0.4s/screen 1.4s/wake 2.3s) 해 동시 `removeStatusItem` 을 구조적으로 차단. cross-broker 아님 (각자 자기 것만 복구, 단지 타이밍만 어긋나게). 60s guidance + 2분 auto-restart 사다리는 그대로 — 단 비파괴 우선이라 거기까지 갈 일이 급감.

## 메뉴바 아이콘

`IconRenderer.makeBatteryPillIcon(remaining:resetText:stale:brand:)` 가 그린다. **`remaining` 은 0~1 fraction**. `IconRemainingResolver.resolvedPercents` 가 `showUsed` 기반으로 used/remaining 중 적절한 percent 를 이미 반환하므로 **call site 에서 절대 다시 뒤집지 말 것** (이전에 double-flip 버그). 그냥 `primary.map { $0 / 100 }`.

## 제거된 기능 (다시 추가하지 말 것)

- 모든 다른 AI provider (41 개)
- Merge Icons 모드 + 다중 계정 layout picker
- CLI 타겟 (`CodexBarCLI`) + Widget 타겟 (`CodexBarWidget`)
- Sparkle 자동 업데이트 + Vortex 컨페티 + Commander dep
- Debug 탭 / PreferencesDebugPane
- Display: 할당량 경고 마커, 프로바이더 변경 이력 링크, 다중 계정 layout
- Advanced: 놀라게 해줘(`randomBlinkEnabled`), 주간 한도 컨페티, 프로바이더 저장소 사용량
- General: 프로바이더 상태 확인(statusChecksEnabled), 할당량 경고 알림(`quotaWarningNotificationsEnabled`)
- 메뉴 항목: Add Account... / Switch Account... / Changelog
- 카드 호버 강조 (배경 tint + 차트 바 화이트 플립)
- 자동 업데이트 / 언어 picker UI

## 유지된 기능

- Claude / Codex provider 코어 (OAuth/CLI PTY/Web cookies/Admin API for Claude; OAuth/CLI RPC/OpenAI web extras for Codex)
- `OpenAIWeb/` + `OpenAIDashboardModels` (Codex 가 의존)
- Display: 사용량을 사용한 만큼 표시 / 리셋 시간을 시각으로 / 크레딧·추가 사용량 표시
- General: 로그인 시 시작 / 비용 요약 표시 / 새로고침 주기 / 세션 할당량 알림 / 종료
- Advanced: 메뉴 열기 단축키 / 개인 정보 숨김 / Keychain 접근 비활성화
- 메뉴 status item 1 개씩 (Claude pill + Codex pill), 클릭 시 통합 메뉴 (Claude 카드 + Codex 카드 + Overview)

## 디렉토리 가이드

```
Sources/
  CodexBar/                  앱 본체 (StatusItem, Preferences, Menu)
  CodexBarCore/              provider 코어 (Claude/Codex 폴더 + OpenAIWeb)
  CodexBarClaudeWatchdog/    Claude CLI 워치독 데몬
  CodexBarClaudeWebProbe/    Claude 웹 세션 헬스체크
  CodexBarMacros/            매크로 정의
  CodexBarMacroSupport/      매크로 wrappers
docs/
  CLAUDE.md                  Claude provider 데이터 경로 상세
  codex.md / codex-oauth.md  Codex provider 데이터 경로
  install-guide-ko.md        팀원용 설치 가이드
  usage-guide-ko.md          한글 사용법
  refactor/                  Claude refactor 베이스라인
  superpowers/               spec/plan 문서
Scripts/
  build_for_distribution.sh  배포용 zip 빌드 (권장)
  compile_and_run.sh         로컬 개발 빌드+실행 (Xcode 필요)
  install_for_team.sh        팀원이 zip 받아 설치
```

## 외부 자료

- Claude 데이터 흐름 / OAuth scope / Cookie 자동 import 순서: [`docs/CLAUDE.md`](docs/CLAUDE.md)
- Codex `~/.codex/auth.json` 구조 / ChatGPT backend usage API: [`docs/codex.md`](docs/codex.md), [`docs/codex-oauth.md`](docs/codex-oauth.md)
- 팀 빌드/배포 흐름: [README.md](README.md) + [`docs/install-guide-ko.md`](docs/install-guide-ko.md)
