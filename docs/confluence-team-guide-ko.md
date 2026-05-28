# ClCoBar 사용 가이드

> Claude + Codex 의 사용량과 리셋까지 남은 시간을 macOS 메뉴바에서 한눈에 보여주는 도구입니다.
> 한국어 전용 · macOS 14 (Sonoma) 이상 · Apple Silicon 기본.

## 버전 히스토리

| 버전 | 날짜 | 주요 변경 |
|---|---|---|
| **1.5.8** | 2026-05-28 | 사용자 토글 OFF/ON 으로도 사용량 pill 복구가 안 되던 케이스 근본 수정. 1.5.7 까진 `handleSettingsChange` 의 토글 ON 경로가 `isVisible=true` 만 set 하고 instance health check 안 함 → unhealthy stuck 상태가 토글로 안 풀림 (점심시간 1시간 후 자리 돌아왔는데 토글로도 복구 안 되는 케이스). 4-track 보강: (1) `handleSettingsChange` 끝에 즉시 `recoverInvisibleOrBlockedStatusItemsIfNeeded` 호출 — 사용자 토글로 직접 health check + 단일 provider 재생성 트리거. self-recovery 라 cross-broker false-positive 없음. (2) Heartbeat 30s → 15s 단축 — 더 빠른 자동 복구. (3) 60초 이상 stuck 시 `MenuBarVisibilityWatcher.presentGuidance` alert — macOS Tahoe "메뉴 막대에서 허용" 자동 OFF 같은 OS-level 케이스 사용자에게 안내 (우리 recovery 의 한계 인정). (4) CLAUDE.md lesson 보강 — "사용자 토글 ON 경로에서 즉시 health check 필수". |
| **1.5.7** | 2026-05-28 | 절전 없이 갑자기 사용량 pill 만 사라지는 케이스 수정. 1.5.6 에서 Companion 에만 적용한 health check (button.image 의 nil / zero-size 검증) 를 사용량 pill 에도 동일 적용. `StatusItemVisibilitySnapshot` 에 `hasImage` 필드 추가, `isBlockedSnapshot` 이 image 도 검증. 추가로 blocked 감지 시 destructive 전체 wipe (`recreateStatusItemsForVisibilityRecovery`) 대신 **단일 provider 만** 재생성 (`recreateProviderStatusItem`) 으로 깜빡임 + cross-effect 위험 최소화. 30초 heartbeat 가 이제 image 깨진 status item 도 잡음. |
| **1.5.6** | 2026-05-28 | Display sleep (화면만 끔, system sleep 아님) 후 캐릭터가 사라진 채 안 돌아오는 케이스 근본 수정. 1.5.5 의 instance lifetime 영구 유지 패턴이 macOS 가 NSStatusItem 의 button image / window 를 reject 한 unhealthy stuck 상태도 같이 살리면서 사용자가 메뉴에서 OFF/ON 토글해도 복구 안 되는 문제가 있었음. 3-track 보호: (1) SF Symbol fallback chain 강화 (dog → pawprint.fill → pawprint → circle.fill) + 모두 실패 시 코드로 그린 placeholder dot — zero-size image 절대 안 반환, (2) `setVisible(true)` 시 statusItem health check (button.window / image.size 검증), unhealthy 면 강제 재생성 — 사용자 메뉴 토글로 직접 복구 가능, (3) `screensDidWake` / `didWake` 시 무조건 stop+start (Companion 만, 사용량 pill 안 건드림) — display sleep 후 자동 복구 강화. |
| **1.5.5** | 2026-05-28 | 사용량 pill ↔ Companion 토글 cross-effect 진짜 root cause 제거. 기존엔 토글 OFF 시 `statusBar.removeStatusItem` 으로 NSStatusItem 인스턴스 자체 제거 → 다시 ON 시 새 인스턴스 생성 패턴이었음. macOS 의 status bar 는 짧은 시간 안의 add → remove → add sequence 에 race 가 있고 이게 다른 NSStatusItem 의 visibility 까지 깨뜨리는 진짜 원인. 1.5.5 부터 Apple 권장 패턴 (`isVisible` 토글로 hide/show, 인스턴스 lifetime 유지) 적용 — provider toggle 도 Companion toggle 도 인스턴스 lifetime 절대 안 건드림. Companion 에는 `setVisible(_:)` + `userEnabled` flag 추가해 사용자 OFF 와 macOS evict 를 watchdog 이 구분. 두 토글이 진짜로 독립 동작. |
| **1.5.4** | 2026-05-28 | 사용량 pill 과 Companion 캐릭터 두 토글이 서로에게 영향을 주던 cross-effect 완전 제거. 1.5.2 / 1.5.3 의 양방향 broker (Companion stop/start → 사용량 pill 강제 복구, provider 토글 → Companion 강제 복구, settings change → self 강제 복구) 가 토글마다 destructive `recreateStatusItemsForVisibilityRecovery` 를 발화시켜 다른 status item 까지 wipe → 신생 status item 의 width=0 false-positive 로 또 recreate → 무한 loop 의 root cause. 모든 cross-broker 제거하고 `MenuBarVisibilityWatcher.isBlockedSnapshot` 의 `buttonWidth ≤ 0` false-positive 조건도 제거 (window/screen nil 만으로 evict 판정). 진짜 evict 는 wake observer cascade (1.5s + 5s + 15s) + 30초 heartbeat 가 잡음. 두 토글은 이제 완전 독립. |
| **1.5.3** | 2026-05-28 | 1.5.2 의 visibility recovery 가 한 방향만 (Companion → 사용량 pill) 처리해서 발생한 cross-toggle 문제 수정. provider 토글 ON/OFF 가 Companion 의 visibility 를 깨거나, 빠른 토글 시퀀스에서 양쪽이 서로 evict 시키는 케이스. `CompanionStatusItemController` 에 public `requestVisibilityRecovery(reason:)` 추가 (cascade 즉시 + 1s). `StatusItemController.handleSettingsChange` 끝에 자기 자신 visibility recovery 도 호출. `AppDelegate` 가 `.codexbarProviderConfigDidChange` notification 받으면 Companion 의 recovery 도 broker. 추가로 빠른 토글 시퀀스에서 fetch task 가 hang 한 채 `refreshingProviders` 에 stuck 되어 heartbeat retry 도 영원히 skip 되는 "Not fetched yet" 보험성 fix — 새로 enabled 된 provider 의 stuck 상태 강제 클리어 후 fresh fetch. |
| **1.5.2** | 2026-05-28 | 두 가지 status item 사라짐 케이스 근본 수정. (1) 장시간 sleep 후 wake 시 캐릭터가 사라진 채 한참 안 돌아오던 문제 — wake recovery 가 1.5초 단발이라 macOS 가 status bar 재배치하는 시간 안에 evict 가 못 잡혔던 문제. 1.5s + 5s + 15s cascade 로 변경. (2) Companion 토글 OFF→ON 직후 사용량 pill 이 사라지던 문제 — Companion 의 새 NSStatusItem 추가가 macOS status bar 재배치를 유발해 이미 evict 상태였던 사용량 pill 의 invisible 이 가시화되던 race. `StatusItemControlling.requestVisibilityRecovery(reason:)` 추가하고 AppDelegate 가 Companion stop/start 시 즉시 + 500ms 후 cascade 호출. |
| **1.5.1** | 2026-05-27 | Companion 캐릭터 (메뉴바 강아지/고양이/토끼/...) 가 신규 설치 사용자에게도 기본 ON 으로 노출되도록 변경. 기존에 사용자가 명시적으로 OFF 한 경우엔 그대로 OFF 유지 (`UserDefaults` 의 `companion.enabled` 키가 nil 일 때만 true 반환). 1.5.0 까진 기본 OFF 라 강아지를 못 보고 지나치는 케이스가 있었음. |
| **1.5.0** | 2026-05-27 | 메뉴바 Companion 캐릭터 전면 재설계. 기존 4종(고양이·강아지 × 픽셀·라인) 절차적 NSBezierPath 드로잉 + 5종 sprite atlas 파일 + 별도 IconRenderer 를 모두 폐기하고 Apple SF Symbols vector 기반으로 통합. **8 종 캐릭터** picker 추가 — 강아지 / 고양이 / 토끼 / 거북이 / 새 / 달리는 사람 / 불꽃 / 번개. 모두 5 프레임 동일 transform cycle (회전 ±10°, 점프 -5px) 로 통통 튀는 motion. `CompanionAnimationDriver` 도 phase 기반 → frame index 기반으로 단순화 (RunCat 방식 cycling). **Stage 임계값을 시간당 % 기준으로 재정의**: idle (0~0.6%/hr) · slow (0.6~10%/hr) · normal (10~20%/hr) · fast (20~30%/hr) · burst (≥30%/hr). 일상 사용 범위에 전환점이 집중되어 stage 변화가 자주 가시화됨. 기존 catPixel/catLine/dogPixel/dogLine 저장값은 자동으로 `.dog` 로 fallback (재설치만 하면 됨, 별도 설정 불필요). |
| **1.4.1** | 2026-05-27 | 메뉴바 캐릭터 + 사용량 pill 이 원인 모르게 사라지던 문제 근본 수정. wake notification 직후 1.5초 단발 체크만으로는 long-uptime / display-only sleep / 장시간 idle 후의 NSStatusItem evict 를 못 잡던 문제 — `StatusItemController` heartbeat 를 30초 주기로 줄이고 매 주기마다 blocked/missing 자동 복구, `screensDidWake` + `didBecomeActive` 알림에도 동일 복구 wire, `CompanionStatusItemController` 의 30초 observation 루프에도 같은 watchdog 추가. 사용자가 토글을 끄지 않는 이상 메뉴바 아이콘은 절대 사라지지 않습니다. |
| **1.4.0** | 2026-05-27 | 새 버전 출시 시 메뉴에 "🆕 X.Y.Z 사용 가능 — 설치 안내" 한 줄로 알림 추가. 1시간마다 `https://raw.githubusercontent.com/vectorKim3333/CodexBar/main/version.env` 를 익명으로 polling, 현재 버전보다 높으면 표시. 클릭하면 Confluence 설치 가이드 페이지가 열립니다. 메뉴 외 토스트/뱃지 알림 없음 — 거슬리지 않는 단일 surface. |
| **1.3.6** | 2026-05-27 | Claude/Codex 카드에 raw 에러(예: `HTTP 429 – { rate_limit_error ... }`)가 그대로 노출되던 문제 수정. 자주 발생하는 HTTP 429 / 401 / 5xx / 네트워크 오류를 한국어 친화 메시지(원인 + 해결방안)로 자동 변환. 매핑되지 않은 오류는 기존처럼 raw 메시지 유지. |
| **1.3.5** | 2026-05-27 | Companion 메뉴 상태 라인에서 "tok/분" 표시 및 관련 로직 전체 제거. burn rate 는 세션 % 단일 신호로만 분류. 토큰 카운트 자체는 메뉴의 "오늘 X tokens" 줄에 그대로 표시. |
| **1.3.4** | 2026-05-27 | Companion 메뉴 "기준시간" 이 30초마다 갱신되어 항상 "방금 전" 으로 표시되던 버그 수정 (이제 UsageStore snapshot 의 실제 업데이트 시각 표시, "HH:mm · X분 전" 형식). 활발하게 Claude 사용 중에도 휴식 상태에 머물던 문제 추가 보완 — Anthropic OAuth 의 `usedPercent` 가 캐싱되어 변하지 않을 때 로컬 token log (`.jsonl`) 의 tok/분 활동량을 fallback 으로 사용. |
| **1.3.3** | 2026-05-27 | Companion 캐릭터가 활발한 사용 중에도 휴식 상태에 머물던 문제 수정. burn rate 계산을 주간(weekly) 사용량 대신 **세션(5시간)** 사용량으로 변경. 주간은 변화율이 너무 작아(분당 0.01% 미만) 모든 활동이 idle 임계값 아래로 분류되던 근본 원인. |
| **1.3.2** | 2026-05-27 | Companion 슬림 메뉴 글자색 정상화 (회색→가독성 좋은 진한 색), 캐릭터가 180° 뒤집혀 렌더링되던 버그 수정 (CG 좌표계 vs sprite 좌표계 불일치), 모델명 표시 단축 (`claude-opus-4-7` → `Opus 4.7`). |
| **1.3.1** | 2026-05-27 | 메뉴바 Companion UX 개선. status item 너비를 다른 pill 과 동일하게 자동 축소. 4종 캐릭터(고양이/강아지 × 픽셀/라인) silhouette 재설계 — 귀·꼬리·snout 가 명확히 인식됨. Companion 클릭 시 통합 메뉴 대신 전용 슬림 메뉴 표시 (세션%·리셋·주간·오늘 토큰·주요 모델). burn rate 를 "시간당 %" + "tok/분" 형식으로 직관화. |
| **1.3.0** | 2026-05-27 | 메뉴바에 캐릭터 컴패니언 추가. 환경설정 → 표시 → 캐릭터에서 4종(고양이·강아지 × 픽셀·라인) 중 선택. Claude 또는 Codex 의 토큰 사용 속도(burn rate)에 따라 5단계(휴식/느림/보통/빠름/폭주)로 자동 변속. Reduce Motion / rate-limit backoff / 절전 복구 자동 처리. |
| **1.2.3** | 2026-05-27 | 장시간 절전 후 메뉴바 아이콘 자체가 사라지던 문제 수정. macOS Tahoe 가 deep sleep 중 NSStatusItem window 를 evict 하면 wake 후 `isVisible` 토글만으론 복구가 안 되던 케이스 — wake notification 1.5 초 뒤 blocked snapshot (`isVisible=true` 인데 button/window/screen 이 nil) 을 감지하면 statusBar 에서 통째로 재등록. |
| **1.2.2** | 2026-05-21 | 장시간 사용 후 메뉴바에서 Claude 가 사라지거나 "Not fetched yet" 에 갇히던 문제 자가 복구 강화. 토글 OFF → ON 직후 즉시 fetch 트리거, heartbeat 주기에 stale provider 자동 재시도, wake 시 visibility 까지 함께 동기화. |
| **1.2.1** | 2026-05-20 | 시스템 슬립에서 깬 직후 Claude 등에서 "Not fetched yet" 에 갇히던 문제 수정. wake 이벤트에 자동 새로고침이 자연스럽게 트리거되도록 보강. |
| **1.2.0** | 2026-05-19 | 프로바이더 detail 우측 "설정 / 옵션" 섹션 숨김 (자동 동작). 문서·배포 안내 정비. |
| **1.1.0** | 2026-05-19 | 메뉴바 표시 항목 4 토글 (아이콘 / 퍼센트 / 배터리 / 시간) 도입. 시간 형식 기본값 "정확". 그래프 카드 영역 한국어화. 스위처 탭 사용량 게이지 제거. |
| **1.0.0** | 2026-05-19 | 첫 팀 배포 빌드. 한국어 전용 UI, ClCoBar 리브랜드, ad-hoc 서명 zip 배포 흐름. |

> 새 빌드를 받으면 응용 프로그램의 기존 `ClCoBar.app` 을 교체 후 다시 실행하세요. 설정값은 유지됩니다.

---

## 1. 설치

1. 공유받은 **`ClCoBar-<버전>-arm64.zip`** 을 더블클릭해 압축 해제 → `ClCoBar.app` 이 생깁니다.
2. `ClCoBar.app` 을 **응용 프로그램** 폴더로 드래그.
3. 응용 프로그램에서 ClCoBar **우클릭 → "열기"** → 보안 경고 창이 뜨면 **"열기"** 한 번 더.

> ⚠️ **첫 실행은 반드시 우클릭 → 열기.** 그냥 더블클릭하면 "확인되지 않은 개발자" 라며 차단됩니다. 한 번만 이렇게 열면 그 다음부터는 더블클릭으로도 열립니다.

📷 **[이미지 1]:** Finder 에서 `ClCoBar.app` 을 응용 프로그램 폴더로 드래그하는 모습, 또는 우클릭 → "열기" 컨텍스트 메뉴.

---

## 2. 첫 실행

성공하면 메뉴바 우측 상단에 **Claude / Codex 두 개의 배터리 모양 아이콘** 이 나타납니다. 인증은 자동입니다:

- **Claude** — Claude CLI 의 OAuth 자격 또는 `claude.ai` 브라우저 쿠키(Safari/Chrome/Firefox)를 자동으로 가져옵니다.
- **Codex** — Codex CLI 의 `~/.codex/auth.json` 또는 ChatGPT 웹 세션을 자동으로 사용합니다.

> 둘 중 하나라도 미리 CLI 나 브라우저 로그인이 되어 있어야 사용량이 표시됩니다.

📷 **[이미지 2]:** 메뉴바에 Claude · Codex 두 개의 pill 아이콘이 나란히 보이는 캡처.

---

## 3. 메뉴 살펴보기

메뉴바 아이콘을 클릭하면 통합 메뉴가 펼쳐집니다. 상단의 **Claude / Codex / Overview** 탭으로 카드를 전환할 수 있습니다.

- **세션 / 주간 / Sonnet** 등 사용량 게이지와 리셋 시각
- **페이스** — 정상 페이스 / 초과 사용 / 여유, 리셋까지 유지 여부, 소진 예상 시점
- **30 일 비용 / 토큰** 차트와 KPI (오늘 / 7일 지출 / 30일 지출 등)

📷 **[이미지 3]:** Claude 또는 Codex 카드가 펼쳐진 메뉴 모습 (사용량 게이지 + 그래프).

---

## 4. 메뉴바 표시 항목 커스터마이징

`환경설정 → 표시` 탭에서 메뉴바에 보일 항목을 자유롭게 조합합니다.

| 옵션 | 기본값 | 설명 |
|---|---|---|
| **아이콘** | ON | Claude / Codex 브랜드 글리프 |
| **퍼센트** | OFF | 남은(또는 사용한) 사용량 % 숫자 |
| **배터리** | ON | 사용량을 배터리 모양 게이지로 |
| **시간** | ON | 리셋까지 남은 시간 |

**시간 표시 옵션 (시간 토글 ON 일 때만):**
- **정확 (기본)** — `2시간 14분 후`
- **근사치** — `~2h`
- **올림** — `2h+`

> 퍼센트와 시간을 동시에 켜면 `47% · 2시간 14분 후` 처럼 합쳐서 표시됩니다.
> 모두 끄면 클릭 영역만 남으니 최소 하나는 켜두세요.

📷 **[이미지 4]:** 환경설정 → 표시 탭 — 4 개 토글 + 시간 형식 picker 가 모두 보이는 스크린샷.

📷 **[이미지 5]:** 토글 조합별 메뉴바 결과 비교 (예: ① 아이콘 + 배터리 + 시간 (기본) / ② 아이콘 + 퍼센트 + 시간 / ③ 배터리 + 시간만 / ④ 시간만). 3 ~ 4 가지 조합을 옆으로 나열.

---

## 5. 그 외 환경설정

- **일반** — 로그인 시 시작 / 비용 요약 표시 / 자동 새로고침 주기 / 세션 한도 알림
- **표시** — 위 메뉴바 옵션 + 사용한 만큼으로 보기 / 리셋 시각 표시 / 크레딧·추가 사용량 표시
- **고급** — 메뉴 열기 단축키 / 개인 정보 숨김 / Keychain 접근 비활성화 (디버그용)

📷 **[이미지 6]:** 환경설정 창의 탭 바 (일반 / 표시 / 프로바이더 / 고급 / 정보) 가 보이는 캡처.

---

## 6. 자주 묻는 질문

**Q. 두 번째 실행부터도 우클릭 → 열기 해야 하나요?**
아니요. 첫 실행만 그렇게 하면 그 후부터는 일반 더블클릭이나 로그인 시 자동 실행이 가능합니다.

**Q. 권한 허용 / 비밀번호 입력 창이 떠요.**
정상입니다. 첫 실행 시 macOS 가 다음 두 종류의 프롬프트를 띄울 수 있습니다.

- **자동화·파일 접근 권한** — Claude/Codex 의 자격 파일이나 브라우저 쿠키를 읽기 위해 필요합니다. **"허용"** 을 누르면 사용량을 정상적으로 가져올 수 있습니다.
- **Keychain 접근 (비밀번호 입력)** — Claude OAuth 토큰이 Keychain 에 저장되어 있을 때 macOS 가 잠금 해제용으로 **로그인 비밀번호** 를 요구합니다. **"항상 허용"** 을 누르면 다음부턴 다시 묻지 않습니다.

> 거부하면 해당 소스에서 사용량을 못 가져옵니다. 거부한 뒤 다시 허용하려면 `시스템 설정 → 개인정보 보호 및 보안 → 자동화 / 파일 및 폴더` 에서 ClCoBar 를 켜 주세요.

📷 **[이미지 7]:** 권한 허용 프롬프트와 Keychain 비밀번호 입력 창의 캡처 (둘 중 하나만 있어도 됩니다).

**Q. 사용량이 갱신이 안 돼요.**
환경설정 → 일반 → 새로고침 주기를 확인하고, 메뉴를 한 번 열었다 닫아 보세요. 일시적으로 Anthropic / OpenAI 가 rate-limit (HTTP 429) 을 걸면 자동으로 10 분 백오프됩니다.

**Q. Claude 사용량 소스를 바꾸고 싶어요 (OAuth / CLI / Web).**
현재는 자동 (Auto) 으로 고정되어 있습니다. 기본 소스가 실패하면 자동으로 다음 소스(OAuth → CLI → Web) 로 폴백합니다.

**Q. 메뉴바 아이콘이 두 개로 보여요.**
응용 프로그램 폴더 외부(예: `dist/` 또는 `~/Downloads`) 에 풀어둔 또 다른 `ClCoBar.app` 이 실행 중일 수 있습니다. 응용 프로그램 폴더 외의 사본은 모두 삭제해 주세요.

---

## 7. 업데이트

새 버전의 zip 을 받으면:

1. 메뉴바 아이콘 → 종료
2. 응용 프로그램에서 기존 `ClCoBar.app` 삭제
3. 새 zip 압축 해제 → 응용 프로그램으로 드래그
4. 우클릭 → "열기" (새 버전 첫 실행이라 한 번 필요)

설정값은 그대로 유지됩니다.

---

문의 / 제보: `#팀-채널` 또는 담당자(`sh.kim@madup.com`).
