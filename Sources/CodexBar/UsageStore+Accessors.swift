import CodexBarCore
import Foundation

extension UsageStore {
    var codexSnapshot: UsageSnapshot? {
        self.snapshots[.codex]
    }

    var claudeSnapshot: UsageSnapshot? {
        self.snapshots[.claude]
    }

    var lastCodexError: String? {
        self.errors[.codex]
    }

    var userFacingLastCodexError: String? {
        self.userFacingError(for: .codex)
    }

    var userFacingLastCreditsError: String? {
        CodexUIErrorMapper.userFacingMessage(self.lastCreditsError)
    }

    var userFacingLastOpenAIDashboardError: String? {
        CodexUIErrorMapper.userFacingMessage(self.lastOpenAIDashboardError)
    }

    var lastClaudeError: String? {
        self.errors[.claude]
    }

    func error(for provider: UsageProvider) -> String? {
        self.errors[provider]
    }

    func userFacingError(for provider: UsageProvider) -> String? {
        if let raw = self.errors[provider] {
            // HTTP-level patterns (429, 401, 5xx, network) — applies to both providers.
            if let mapped = ProviderHTTPErrorMapper.userFacingMessage(raw, provider: provider) {
                return mapped
            }
            // Provider-specific fallback.
            if provider == .codex {
                return CodexUIErrorMapper.userFacingMessage(raw)
            }
            return raw
        }
        return self.unavailableMessage(for: provider)
    }

    func unavailableMessage(for provider: UsageProvider) -> String? {
        guard self.enabledProvidersForDisplay().contains(provider),
              !self.isProviderAvailable(provider)
        else {
            return nil
        }

        return "\(self.metadata(for: provider).displayName) is unavailable in the current environment."
    }

    func status(for provider: UsageProvider) -> ProviderStatus? {
        guard self.statusChecksEnabled else { return nil }
        return self.statuses[provider]
    }

    func statusIndicator(for provider: UsageProvider) -> ProviderStatusIndicator {
        self.status(for: provider)?.indicator ?? .none
    }

    func accountInfo(for provider: UsageProvider) -> AccountInfo {
        guard provider == .codex else {
            return self.codexFetcher.loadAccountInfo()
        }
        let env = ProviderRegistry.makeEnvironment(
            base: self.environmentBase,
            provider: .codex,
            settings: self.settings,
            tokenOverride: nil)
        let fetcher = ProviderRegistry.makeFetcher(base: self.codexFetcher, provider: .codex, env: env)
        return fetcher.loadAccountInfo()
    }
}

/// Maps HTTP-level / network error patterns (429, 401, 5xx, network) to friendly
/// Korean messages with cause + resolution. Returns nil for patterns it doesn't recognize.
enum ProviderHTTPErrorMapper {
    static func userFacingMessage(_ raw: String, provider: UsageProvider) -> String? {
        let lower = raw.lowercased()
        let name = provider == .claude ? "Claude" : "Codex"

        if Self.looksRateLimited(lower: lower) {
            return """
            \(name) API 사용량 한도에 일시적으로 도달했습니다.
            약 10분 후 자동으로 다시 시도합니다.

            해결: 환경설정에서 새로고침 주기를 늘리거나(예: 5분 이상), 잠시 후 메뉴를 다시 열어보세요.
            """
        }
        if Self.looksAuthExpired(lower: lower) {
            return """
            \(name) 인증이 만료되었거나 유효하지 않습니다.

            해결: 환경설정 → Providers → \(name) 에서 다시 로그인해 주세요.
            """
        }
        if Self.looksServerError(lower: lower) {
            return """
            \(name) 서버에 일시적인 문제가 발생했습니다 (5xx).
            잠시 후 자동으로 다시 시도합니다.

            해결: 몇 분 후 메뉴를 다시 열어보세요. 같은 오류가 계속되면 Anthropic / OpenAI 상태 페이지를 확인해 주세요.
            """
        }
        if Self.looksNetworkError(lower: lower) {
            return """
            \(name) 서버와 연결할 수 없습니다.

            해결: 네트워크 연결을 확인해 주세요. VPN / 방화벽 / 프록시 환경이면 일시적으로 끄고 다시 시도해 보세요.
            """
        }
        return nil
    }

    private static func looksRateLimited(lower: String) -> Bool {
        lower.contains("429")
            || lower.contains("rate_limit")
            || lower.contains("rate limit")
            || lower.contains("ratelimit")
    }

    private static func looksAuthExpired(lower: String) -> Bool {
        lower.contains("401")
            || lower.contains("unauthorized")
            || lower.contains("authentication_error")
            || lower.contains("token_expired")
            || lower.contains("invalid_grant")
            || lower.contains("invalid token")
    }

    private static func looksServerError(lower: String) -> Bool {
        // HTTP 5xx — gateway/server-side
        lower.contains("http 500")
            || lower.contains("http 502")
            || lower.contains("http 503")
            || lower.contains("http 504")
            || lower.contains("internal_server_error")
            || lower.contains("bad gateway")
            || lower.contains("service unavailable")
            || lower.contains("gateway timeout")
    }

    private static func looksNetworkError(lower: String) -> Bool {
        lower.contains("could not connect")
            || lower.contains("offline")
            || lower.contains("network connection")
            || lower.contains("timed out")
            || lower.contains("nsurlerror")
            || lower.contains("dns")
            || lower.contains("hostname")
    }
}
