// Tests/CodexBarTests/Companion/SettingsStoreCompanionTests.swift
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SettingsStoreCompanionTests {
    private func freshStore() -> SettingsStore {
        let defaults = UserDefaults(suiteName: "CompanionTest-\(UUID().uuidString)")!
        return SettingsStore(userDefaults: defaults)
    }

    @Test
    func companionEnabledDefaultsToFalse() {
        let store = freshStore()
        #expect(store.companionEnabled == false)
    }

    @Test
    func companionCharacterDefaultsToCatPixel() {
        let store = freshStore()
        #expect(store.companionCharacter == .catPixel)
    }

    @Test
    func companionProviderDefaultsToClaude() {
        let store = freshStore()
        #expect(store.companionProvider == .claude)
    }

    @Test
    func settingCompanionEnabledPersists() {
        let store = freshStore()
        store.companionEnabled = true
        #expect(store.companionEnabled == true)
    }

    @Test
    func settingCompanionCharacterPersists() {
        let store = freshStore()
        store.companionCharacter = .dogLine
        #expect(store.companionCharacter == .dogLine)
    }

    @Test
    func companionFeatureSeenDefaultsToFalse() {
        let store = freshStore()
        #expect(store.companionFeatureSeen == false)
    }
}
