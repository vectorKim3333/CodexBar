import Foundation

/// 1.8.7: Claude `.auto` 모드의 *자동* web-session fallback probe 에 대한 negative 캐시.
///
/// OAuth·CLI 자격증명이 둘 다 없는 사용자는 `.auto` 모드에서 마지막 수단으로 브라우저
/// 쿠키에 Claude web 세션이 있는지 probe 한다. 그 probe 는 브라우저 쿠키 데이터를 읽는데,
/// 이게 macOS Sequoia/Tahoe 의 "다른 앱의 데이터에 접근" TCC 프롬프트를 유발한다. ad-hoc
/// 서명 앱은 그 동의가 launch 간 유지되지 않아, 세션이 *없는* 사용자는 매 refresh ·
/// cold-start 마다 다시 스캔되어 프롬프트가 반복됐다 (모니터 도킹/언도킹 시 특히 — 사용자 보고).
///
/// 이 게이트는 "세션을 못 찾았다"는 결과를 TTL 동안 기억해 재스캔을 막는다. UserDefaults
/// 기반이라 cold-start(프로세스 재시작) 사이에도 유지된다. 세션을 찾으면(positive) 즉시
/// 기록을 지워 self-heal 하고, TTL 경과 후 자동으로 다시 확인한다. 명시적 web 소스 / manual
/// header / webExtras 같은 *의도적* opt-in 경로에는 적용하지 않는다 (그쪽은 항상 probe).
///
/// `BrowserCookieAccessGate` 의 keychain 거부 cooldown(6시간)과 같은 발상이되, 이쪽은
/// "세션 없음"을 기억한다.
public enum ClaudeWebProbeGate {
    private static let defaultsKey = "claude.autoWebProbe.negativeUntil"
    /// 세션 없음을 기억하는 기간. 너무 길면 "방금 로그인" 케이스가 늦게 잡히고, 너무 짧으면
    /// 프롬프트 억제 효과가 약해진다. 1시간이면 모니터 도킹/언도킹 burst 를 충분히 덮으면서
    /// 자동 self-heal 한다.
    private static let ttl: TimeInterval = 60 * 60

    /// 자동 fallback probe 를 지금 시도해도 되는지. negative 기록이 살아있으면 false.
    public static func shouldProbe(now: Date = Date()) -> Bool {
        let until = UserDefaults.standard.double(forKey: self.defaultsKey)
        return until <= now.timeIntervalSince1970
    }

    /// 세션을 못 찾았음을 기록 — TTL 동안 재스캔을 막는다.
    public static func recordNoSession(now: Date = Date()) {
        UserDefaults.standard.set(now.addingTimeInterval(self.ttl).timeIntervalSince1970, forKey: self.defaultsKey)
    }

    /// 세션을 찾았음 — negative 기록을 즉시 해제 (self-heal).
    public static func recordSessionFound() {
        UserDefaults.standard.removeObject(forKey: self.defaultsKey)
    }

    public static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: self.defaultsKey)
    }
}
