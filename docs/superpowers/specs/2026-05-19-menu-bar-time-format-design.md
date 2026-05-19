# 메뉴바 시간 표시 포맷 선택 옵션

작성일: 2026-05-19
작성자: sh.kim@madup.com

## 1. 목적

메뉴바 pill 우측에 표시되는 "다음 리셋까지 남은 시간" 텍스트의 표기 방식을 사용자가 고를 수 있게 한다.

현재 동작은 `IconRenderer.shortResetText` 가 **floor(버림)** 으로 시간을 자른다. 잔여 시간이 1시간 45분이면 `1h` 로 표시되어 임박해 보인다. 다른 메뉴바 도구는 ceiling(올림) 으로 `~2h` 처럼 표시해 시각적으로 더 자연스럽다.

### 비목표
- 시간대(timezone) 처리 변경 없음.
- pill 의 채움 비율(`fillFraction`) 계산은 그대로.
- Display Pane 의 다른 항목 변경 없음.

## 2. 사전 결정 사항

| 항목 | 결정 |
|---|---|
| 노출 위치 | Preferences → 디스플레이 → 메뉴바 섹션, Show Percent 토글 아래 |
| 포맷 종류 | 3 가지 — 근사치(ceiling) / 정확(precise) / 올림(`+` suffix) |
| 기본값 | 근사치(`~2h`) |
| 단위 표기 | 영어 단위 `m/h/d` 유지 (한글 단위 안 씀; 영문 호환·기존 폰트와 어울림) |
| 5 분 단위 반올림 | 근사치 모드에서만 적용 |

## 3. UI

Preferences → 디스플레이 → 메뉴바 섹션:

```
시간 표시
다음 리셋까지 남은 시간을 표시하는 방식
  [ 근사치 (~2h)  ▼ ]
     • 근사치 (~2h)         ← 기본
     • 정확 (1h 45m)
     • 올림 (1h+)
```

- Picker 컴포넌트는 `Display` 의 기존 picker 들과 동일 스타일 (`.pickerStyle(.menu)`, `.frame(maxWidth: 200)`).
- 라벨/설명은 `Localizable.strings` 의 ko/en 양쪽에 추가.

## 4. 포맷 정의

잔여 시간 = `interval = resetsAt - now` (양수일 때만 텍스트 생성).

### 4-1. 근사치 (approximate) — 기본

| 잔여 시간 | 표시 |
|---|---|
| `< 1m` | `<1m` |
| `1m ≤ < 56m` | `~Nm` (5분 단위 올림: 1~5분 → "~5m", 6~10분 → "~10m", …, 51~55분 → "~55m") |
| `56m ≤ < 60m` | `~1h` (5분 ceiling 이 60m 에 도달하면 시간으로 승격) |
| `1h ≤ < 24h` | `~Nh` (분 단위 올림, e.g. 1h 45m → "~2h") |
| `≥ 24h` | `~Nd` (시간 단위 올림) |

### 4-2. 정확 (precise)

| 잔여 시간 | 표시 |
|---|---|
| `< 1m` | `<1m` |
| `< 60m` | `Nm` (분, floor) |
| `1h ≤ < 24h` 시간 분 모두 있음 | `Nh Mm` (e.g. "1h 45m") |
| `1h ≤ < 24h` 분 = 0 | `Nh` |
| `≥ 24h` 일과 시간 모두 있음 | `Nd Nh` |
| `≥ 24h` 시간 = 0 | `Nd` |

### 4-3. 올림 (floor + suffix)

| 잔여 시간 | 표시 |
|---|---|
| `< 1m` | `<1m` |
| `< 60m` | `Nm` (floor — `+` 안 붙임. 분 자체가 작은 단위라 잘림 체감 거의 없음) |
| `1h ≤ < 24h` | `Nh+` |
| `≥ 24h` | `Nd+` |

## 5. 영향 범위

### 5-1. 신규
- `Sources/CodexBar/MenuBarTimeFormat.swift` — `enum MenuBarTimeFormat: String, CaseIterable, Identifiable` (`approximate` / `precise` / `floor`). `label` 은 `L("time_format_approximate")` 등을 통해 현지화.

### 5-2. 수정
- `Sources/CodexBar/IconRenderer.swift` — `shortResetText(_:format:now:)` 시그니처에 `format: MenuBarTimeFormat` 추가. 기존 호출자(2 곳)에 전달. 내부 분기 위 §4.
- `Sources/CodexBar/StatusItemController+Animation.swift` — `IconRenderer.shortResetText(...)` 호출 2 곳 (merged + per-provider) 에 `format: self.settings.menuBarTimeFormat` 전달.
- `Sources/CodexBar/SettingsStore+Defaults.swift` — 신규 `menuBarTimeFormat: MenuBarTimeFormat` getter/setter. **반드시 copy-modify-reassign 패턴** (`@Observable` nested-struct 버그 회피, 다른 setter 와 동일):
  ```swift
  var state = self.defaultsState
  state.menuBarTimeFormat = newValue
  self.defaultsState = state
  self.userDefaults.set(newValue.rawValue, forKey: "menuBarTimeFormat")
  ```
- `Sources/CodexBar/SettingsStoreState.swift` — `var menuBarTimeFormat: MenuBarTimeFormat` 추가, memberwise init 갱신.
- `Sources/CodexBar/SettingsStore.swift` — `loadDefaultsState` 에서 UserDefaults 읽기 + 기본값 `.approximate`.
- `Sources/CodexBar/SettingsStore+MenuObservation.swift` — `_ = self.menuBarTimeFormat` 추가 (포맷 변경 → 메뉴 invalidate → 아이콘 재렌더).
- `Sources/CodexBar/PreferencesDisplayPane.swift` — 메뉴바 섹션에 Picker 추가 (Show Percent 아래).
- `Sources/CodexBar/Resources/en.lproj/Localizable.strings`, `Sources/CodexBar/Resources/ko.lproj/Localizable.strings` — 5 개 키 추가:
  - `time_format_title`
  - `time_format_subtitle`
  - `time_format_approximate`
  - `time_format_precise`
  - `time_format_floor`

### 5-3. 손대지 않음
- `Sources/CodexBarCore/` provider 코어
- `OpenAIWeb/`, `OpenAIDashboardModels.swift`
- 다른 Preferences pane / 메뉴 로직

## 6. 단계별 작업 계획

1. **데이터 모델** — `MenuBarTimeFormat.swift` 작성 + `SettingsStoreState` 필드 추가 + `SettingsStore+Defaults` setter + `SettingsStore` load 경로 + `SettingsStore+MenuObservation` 등록. 빌드 통과.
2. **렌더링** — `IconRenderer.shortResetText` 시그니처 변경 + 분기 구현. 호출처 (`StatusItemController+Animation.swift` 2 곳) 수정. 빌드 통과.
3. **UI** — `PreferencesDisplayPane.swift` Picker 추가 + localization 5 키. 빌드 통과.
4. **수동 검증** — Picker 전환 시 메뉴바 pill 텍스트 즉시 갱신 확인, 세 포맷 모두 다음 케이스 검증:
   - <1m (`<1m`)
   - 분 단위 (예: 30분)
   - 시간+분 (예: 1h 45m)
   - 정수 시간 (예: 정확히 2h)
   - 24h 이상 (예: 2d 5h)
   - 24h 정수 (예: 2d)

## 7. 위험 요소 및 대응

| # | 위험 | 대응 |
|---|---|---|
| R1 | `@Observable` 전파 버그 재발 | setter 가 copy-modify-reassign 패턴을 따랐는지 코드 리뷰에서 점검 — 이미 4 개 setter 가 같은 패턴이므로 참고 가능. |
| R2 | `IconRenderer.shortResetText` 의 기존 default 인자가 다른 모듈에서 호출되어 컴파일 깨짐 | `format` 파라미터에 `.approximate` 기본값 부여하여 source-compatibility 유지. 호출처 명시 호출하는 게 더 깔끔하므로 본 단계에서 갱신. |
| R3 | "근사치 5분 단위" 가 사용자에게 어색 | 첫 출시 후 피드백 모니터링 후 1분 단위 ceiling 으로 단순화 옵션 고려. 지금은 5분 단위 채택. |
| R4 | swift test 가 PreviewsMacros 이슈로 막혀 자동 검증 불가 | 단순 텍스트 포맷팅 함수라 수동 검증 6 케이스 (§6.4) 로 충분. 추후 SwiftTesting 활성화 시 단위 테스트 추가. |

## 8. 미해결 사항
- 없음. 결정사항 모두 확정.
