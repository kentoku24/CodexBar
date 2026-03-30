import CodexBarCore
import Foundation

enum SafeExternalViewerMode {
    static let supportedProviders: Set<UsageProvider> = [.codex, .claude]

    static func isEnabled(
        for provider: UsageProvider,
        env: [String: String] = ProcessInfo.processInfo.environment) -> Bool
    {
        self.enabledProtectedProviders(env: env).contains(provider)
    }

    static func enabledProtectedProviders(
        env: [String: String] = ProcessInfo.processInfo.environment) -> Set<UsageProvider>
    {
        let explicitPathConfigured = self.isExplicitPathConfigured(env: env)

        do {
            if let snapshot = try SafeExternalUsageSnapshotStore.load(env: env) {
                return Set(snapshot.providers.map(\.provider)).intersection(self.supportedProviders)
            }
            if explicitPathConfigured {
                return self.supportedProviders
            }
            return []
        } catch {
            if explicitPathConfigured || SafeExternalUsageSnapshotStore.fileExists(env: env) {
                return self.supportedProviders
            }
            return []
        }
    }

    static func isExplicitPathConfigured(
        env: [String: String] = ProcessInfo.processInfo.environment) -> Bool
    {
        guard let override = env[SafeExternalUsageSnapshotStore.environmentPathKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return false
        }
        return !override.isEmpty
    }
}
