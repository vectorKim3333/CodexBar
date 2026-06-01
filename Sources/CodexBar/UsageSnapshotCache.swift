import CodexBarCore
import Foundation

/// 1.8.3: 마지막으로 성공한 사용량 snapshot 을 디스크에 보존했다가 다음 실행 시 복원한다.
///
/// 배경: 디스플레이 변경 자동 재시작 (1.8.2) 은 새 프로세스 cold start 라 in-memory
/// snapshot 이 사라진다. 그러면 첫 fetch 가 끝날 때까지 pill 이 비어 있고, cold start
/// 첫 fetch 가 자격증명 로드 전 transient 로 실패하면 "인증이 만료/유효하지 않음" 문구가
/// 잠깐 떴다 사라진다 (사용자 보고). 마지막 snapshot 을 복원해 두면:
///   - pill 이 마지막 값으로 즉시 그려짐 (updatedAt 이 오래됐으면 stale 표시).
///   - prior data 가 존재하므로 `ConsecutiveFailureGate` 가 cold-start 첫 transient 에러를
///     억제하고 snapshot 을 보존 (`UsageStore+Refresh` 의 preservesPriorData 경로) → 문구
///     flash 도 사라짐.
/// 첫 refresh 가 1~3초 내 실제 값으로 갱신한다.
enum UsageSnapshotCache {
    /// 이 시간보다 오래된 캐시는 복원하지 않는다 (낡은 값이 오래 보이는 것 방지).
    private static let maxAge: TimeInterval = 12 * 60 * 60

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches", isDirectory: true)
        return base
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("usage-snapshots-v1.json")
    }

    static func save(_ snapshots: [UsageProvider: UsageSnapshot]) {
        guard !snapshots.isEmpty else { return }
        let keyed = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(keyed) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func load(now: Date = Date()) -> [UsageProvider: UsageSnapshot] {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let keyed = try? JSONDecoder().decode([String: UsageSnapshot].self, from: data)
        else { return [:] }
        var result: [UsageProvider: UsageSnapshot] = [:]
        for (raw, snapshot) in keyed {
            guard let provider = UsageProvider(rawValue: raw) else { continue }
            guard now.timeIntervalSince(snapshot.updatedAt) <= Self.maxAge else { continue }
            result[provider] = snapshot
        }
        return result
    }
}
