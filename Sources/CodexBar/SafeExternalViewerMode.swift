import CodexBarCore
import Foundation

enum SafeExternalViewerMode {
    static let supportedProviders: Set<UsageProvider> = [.codex]

    @MainActor
    static func isEnabled(
        for provider: UsageProvider,
        settings: SettingsStore) -> Bool
    {
        self.enabledProtectedProviders(settings: settings).contains(provider)
    }

    @MainActor
    static func enabledProtectedProviders(
        settings: SettingsStore) -> Set<UsageProvider>
    {
        self.enabledProtectedProviders(codexSource: settings.codexUsageDataSource)
    }

    static func isEnabled(
        for provider: UsageProvider,
        config: CodexBarConfig? = nil,
        configStore: CodexBarConfigStore = CodexBarConfigStore()) -> Bool
    {
        self.enabledProtectedProviders(config: config, configStore: configStore).contains(provider)
    }

    static func enabledProtectedProviders(
        config: CodexBarConfig? = nil,
        configStore: CodexBarConfigStore = CodexBarConfigStore()) -> Set<UsageProvider>
    {
        if let config {
            return self.enabledProtectedProviders(config: config)
        }
        let loadedConfig = try? configStore.load()
        return self.enabledProtectedProviders(config: loadedConfig ?? CodexBarConfig.makeDefault())
    }

    static func enabledProtectedProviders(config: CodexBarConfig) -> Set<UsageProvider> {
        var providers: Set<UsageProvider> = []
        if config.providerConfig(for: .codex)?.source == .localFile {
            providers.insert(.codex)
        }
        return providers.intersection(self.supportedProviders)
    }

    private static func enabledProtectedProviders(codexSource: CodexUsageDataSource) -> Set<UsageProvider> {
        var providers: Set<UsageProvider> = []
        if codexSource == .localUsageFile {
            providers.insert(.codex)
        }
        return providers
    }
}
