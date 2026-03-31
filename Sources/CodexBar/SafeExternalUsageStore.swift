import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    private static let safeExternalProviders: Set<UsageProvider> = SafeExternalViewerMode.supportedProviders
    nonisolated static let safeExternalTokenUsageMessage = "Cost usage unavailable in safe external mode."

    func shouldUseSafeExternalSource(for provider: UsageProvider) -> Bool {
        self.isCredentialFreeViewerModeEnabled(for: provider)
    }

    func applySafeExternalUsageSnapshot(_ snapshot: SafeExternalUsageSnapshot) {
        for providerSnapshot in snapshot.providers
            where Self.safeExternalProviders.contains(providerSnapshot.provider)
        {
            self.applySafeExternalProviderSnapshot(providerSnapshot)
        }
    }

    func refreshProviderFromSafeExternalSnapshotIfNeeded(_ provider: UsageProvider) async -> Bool {
        guard Self.safeExternalProviders.contains(provider),
              self.shouldUseSafeExternalSource(for: provider)
        else {
            return false
        }

        switch self.safeExternalSnapshotResolution() {
        case .inactive:
            let path = SafeExternalUsageSnapshotStore.defaultFileURL()?.path ?? "unknown"
            self.applySafeExternalUsageError(provider: provider, message: "Local usage file not found at \(path).")
            return true
        case let .active(snapshot):
            guard let providerSnapshot = snapshot.providerSnapshot(for: provider) else {
                self.applySafeExternalUsageError(
                    provider: provider,
                    message: "Local usage file does not contain \(provider.rawValue) data.")
                return true
            }
            self.applySafeExternalProviderSnapshot(providerSnapshot)
            return true
        case let .error(message):
            self.applySafeExternalUsageError(provider: provider, message: message)
            return true
        }
    }

    func isCredentialFreeViewerModeEnabled(for provider: UsageProvider) -> Bool {
        SafeExternalViewerMode.isEnabled(for: provider, settings: self.settings)
    }

    func isSafeExternalSourceActive(for provider: UsageProvider) -> Bool {
        self.isCredentialFreeViewerModeEnabled(for: provider)
    }

    private func applySafeExternalProviderSnapshot(_ providerSnapshot: SafeExternalProviderSnapshot) {
        let usage = providerSnapshot.toUsageSnapshot()
        self.handleSessionQuotaTransition(provider: providerSnapshot.provider, snapshot: usage)
        self.snapshots[providerSnapshot.provider] = usage
        self.errors[providerSnapshot.provider] = nil
        self.lastSourceLabels[providerSnapshot.provider] = "safe-external"
        self.lastFetchAttempts[providerSnapshot.provider] = []
        self.clearSafeExternalProviderState(providerSnapshot.provider)
    }

    private func applySafeExternalUsageError(provider: UsageProvider, message: String) {
        self.snapshots.removeValue(forKey: provider)
        self.errors[provider] = message
        self.lastSourceLabels[provider] = "safe-external"
        self.lastFetchAttempts[provider] = []
        self.clearSafeExternalProviderState(provider)
    }

    private func clearSafeExternalProviderState(_ provider: UsageProvider) {
        self.accountSnapshots.removeValue(forKey: provider)
        self.clearSafeExternalTokenState(provider)

        if provider == .codex {
            self.clearCodexSensitiveDerivedState()
        }
    }

    func clearSafeExternalTokenState(_ provider: UsageProvider) {
        self.tokenSnapshots.removeValue(forKey: provider)
        self.tokenErrors[provider] = Self.safeExternalTokenUsageMessage
        self.tokenFailureGates[provider]?.reset()
        self.lastTokenFetchAt.removeValue(forKey: provider)
    }

    private func safeExternalSnapshotResolution() -> SafeExternalSnapshotResolution {
        do {
            guard let snapshot = try SafeExternalUsageSnapshotStore.load() else {
                return .inactive
            }
            return .active(snapshot)
        } catch {
            return .error("Local usage file could not be read: \(error.localizedDescription)")
        }
    }

    private enum SafeExternalSnapshotResolution {
        case inactive
        case active(SafeExternalUsageSnapshot)
        case error(String)
    }

    private func clearCodexSensitiveDerivedState() {
        self.credits = nil
        self.lastCreditsError = "Credits unavailable in safe external mode."
        self.resetOpenAIWebState()
        self.codexHistoricalDataset = nil
        self.codexHistoricalDatasetAccountKey = nil
        self.historicalPaceRevision += 1
        self.planUtilizationHistory[.codex]?.preferredAccountKey = nil
    }
}
