// Sources/CodexBar/SettingsStore+Companion.swift
import CodexBarCore
import Foundation

extension SettingsStore {
    var companionEnabled: Bool {
        get { self.defaultsState.companionEnabled }
        set {
            var state = self.defaultsState
            state.companionEnabled = newValue
            self.defaultsState = state
            self.userDefaults.set(newValue, forKey: "companion.enabled")
        }
    }

    var companionCharacter: CompanionCharacter {
        get {
            CompanionCharacter(rawValue: self.defaultsState.companionCharacterRaw) ?? .catPixel
        }
        set {
            var state = self.defaultsState
            state.companionCharacterRaw = newValue.rawValue
            self.defaultsState = state
            self.userDefaults.set(newValue.rawValue, forKey: "companion.character")
        }
    }

    var companionProvider: UsageProvider {
        get {
            UsageProvider(rawValue: self.defaultsState.companionProviderRaw) ?? .claude
        }
        set {
            var state = self.defaultsState
            state.companionProviderRaw = newValue.rawValue
            self.defaultsState = state
            self.userDefaults.set(newValue.rawValue, forKey: "companion.provider")
        }
    }

    var companionFeatureSeen: Bool {
        get { self.defaultsState.companionFeatureSeen }
        set {
            var state = self.defaultsState
            state.companionFeatureSeen = newValue
            self.defaultsState = state
            self.userDefaults.set(newValue, forKey: "companion.featureSeen")
        }
    }
}
