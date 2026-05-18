import Testing
@testable import CodexBar

struct KeychainMigrationTests {
    @Test
    func `migration list covers known keychain items`() {
        let items = Set(KeychainMigration.itemsToMigrate.map(\.label))
        let expected: Set = [
            "com.steipete.CodexBar:codex-cookie",
            "com.steipete.CodexBar:claude-cookie",
        ]

        let missing = expected.subtracting(items)
        #expect(missing.isEmpty, "Missing migration entries: \(missing.sorted())")
    }
}
