import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIProviderSelectionTests {
    @Test
    func `help includes claude and codex and all`() {
        let usage = CodexBarCLI.usageHelp(version: "0.0.0")
        let root = CodexBarCLI.rootHelp(version: "0.0.0")
        let expectedProviders = [
            "--provider codex|",
            "|claude|",
            "|both|",
            "|all]",
        ]
        for provider in expectedProviders {
            #expect(usage.contains(provider))
            #expect(root.contains(provider))
        }
        #expect(usage.contains("--json"))
        #expect(root.contains("--json"))
        #expect(usage.contains("--json-only"))
        #expect(root.contains("--json-only"))
        #expect(usage.contains("--json-output"))
        #expect(root.contains("--json-output"))
        #expect(usage.contains("--log-level"))
        #expect(root.contains("--log-level"))
        #expect(usage.contains("--verbose"))
        #expect(root.contains("--verbose"))
    }

    @Test
    func `help mentions source flag`() {
        let usage = CodexBarCLI.usageHelp(version: "0.0.0")
        let root = CodexBarCLI.rootHelp(version: "0.0.0")

        func tokens(_ text: String) -> [String] {
            let split = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]|,"))
            return text.components(separatedBy: split).filter { !$0.isEmpty }
        }

        #expect(usage.contains("--source"))
        #expect(root.contains("--source"))
        #expect(usage.contains("--web-timeout"))
        #expect(usage.contains("--web-debug-dump-html"))
        #expect(!tokens(usage).contains("--web"))
        #expect(!tokens(root).contains("--web"))
        #expect(!tokens(usage).contains("--claude-source"))
        #expect(!tokens(root).contains("--claude-source"))
    }

    @Test
    func `provider selection respects override`() {
        let selection = CodexBarCLI.providerSelection(rawOverride: "claude", enabled: [.codex])
        #expect(selection.asList == [.claude])
    }

    @Test
    func `provider selection uses enabled providers when three or more are enabled`() {
        let selection = CodexBarCLI.providerSelection(
            rawOverride: nil,
            enabled: [.codex, .claude])
        #expect(selection.asList == [.codex, .claude])
    }

    @Test
    func `provider selection uses both for codex and claude`() {
        let selection = CodexBarCLI.providerSelection(rawOverride: nil, enabled: [.codex, .claude])
        #expect(selection.asList == [.codex, .claude])
    }

    @Test
    func `provider selection honors empty enabled set`() {
        let selection = CodexBarCLI.providerSelection(rawOverride: nil, enabled: [])
        #expect(selection.asList == [])
    }
}
