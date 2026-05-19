# ClCoBar (Claude + Codex Bar)

> Claude(`Cl`) + Codex(`Co`) 두 AI 의 사용량만 macOS 메뉴바에 표시하는 슬림 포크. 원본: [steipete/CodexBar](https://github.com/steipete/CodexBar).

## 요구사항

- macOS 14+ (Sonoma)
- Swift 6 toolchain (Xcode 16+ 또는 Command Line Tools)

## 빌드 & 실행

```bash
swift build -c release
./Scripts/compile_and_run.sh   # 빌드 → 패키징 → 재실행
```

> Xcode 가 설치되지 않은 환경에서는 `./Scripts/build_for_distribution.sh` 를 사용하세요 (KeyboardShortcuts `#Preview` 매크로 회피 패치 포함).

## 설정

- 첫 실행 → 메뉴바에 두 개의 pill 아이콘 (Claude / Codex).
- Preferences → Providers 에서 각각 인증 (OAuth, CLI, 브라우저 쿠키 중 택).
- Claude 데이터 흐름: [`docs/claude.md`](docs/claude.md)
- Codex 데이터 흐름: [`docs/codex.md`](docs/codex.md)
- 한글 사용법: [`docs/usage-guide-ko.md`](docs/usage-guide-ko.md)

## 팀 배포

ad-hoc 서명된 공유용 zip:

```bash
./Scripts/build_for_distribution.sh                          # 호스트 아키텍처
ARCHES="arm64 x86_64" ./Scripts/build_for_distribution.sh    # universal
```

`dist/ClCoBar-<version>-<arch>.zip` 이 만들어집니다 (내부 번들 이름은 `CodexBar` 유지, 사용자에게 표시되는 이름은 `ClCoBar`). Slack/Drive 등에 공유하고 동료에게는 [`docs/install-guide-ko.md`](docs/install-guide-ko.md) 안내.

## 개발

- 점진적 작업: `swift build` / `swift test`
- 전체 앱 번들 검증: `./Scripts/compile_and_run.sh`
- 리포 컨벤션: [`AGENTS.md`](AGENTS.md)

## 라이선스

MIT — [LICENSE](LICENSE). 원본 저작권 유지.
