# CodexBar (Claude + Codex slim fork)

> A pared-down fork of [steipete/CodexBar](https://github.com/steipete/CodexBar) that tracks **only Claude and Codex** usage in the macOS menu bar.

## Requirements

- macOS 14+ (Sonoma)
- Swift 6 toolchain (Xcode 16+)

## Build & Run

```bash
swift build -c release
./Scripts/compile_and_run.sh   # builds, packages, relaunches CodexBar.app
```

## Configuration

- First launch → menu bar icon appears.
- Open **Preferences → Providers** and sign in to Claude and/or Codex via the source path of your choice (OAuth, CLI, browser cookies).
- See [`docs/claude.md`](docs/claude.md) and [`docs/codex.md`](docs/codex.md) for provider-specific details.

## Development

- `swift build` / `swift test` for incremental work.
- `./Scripts/compile_and_run.sh` to validate the full app bundle.
- See [`AGENTS.md`](AGENTS.md) for repo conventions.

## License

MIT — see [LICENSE](LICENSE). Upstream copyright retained.
