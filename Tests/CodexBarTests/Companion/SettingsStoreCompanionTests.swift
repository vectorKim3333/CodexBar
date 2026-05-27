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
    func companionCharacterDefaultsToDog() {
        let store = freshStore()
        #expect(store.companionCharacter == .dog)
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
        // 1종일 때는 .dog 자체 setter round-trip 만 확인. 추후 case 추가되면
        // 변종으로 교체.
        store.companionCharacter = .dog
        #expect(store.companionCharacter == .dog)
    }

    @Test
    func companionFeatureSeenDefaultsToFalse() {
        let store = freshStore()
        #expect(store.companionFeatureSeen == false)
    }
}
