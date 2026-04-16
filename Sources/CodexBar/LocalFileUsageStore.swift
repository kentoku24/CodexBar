import CodexBarCore
import Foundation

@MainActor
extension UsageStore {
    private static let localFileProviders: Set<UsageProvider> = LocalFileViewerMode.supportedProviders

    func shouldUseLocalFileSource(for provider: UsageProvider) -> Bool {
        self.isCredentialFreeViewerModeEnabled(for: provider)
    }

    func applyLocalFileUsageSnapshot(_ snapshot: LocalFileUsageSnapshot) {
        for providerSnapshot in snapshot.providers
            where Self.localFileProviders.contains(providerSnapshot.provider)
        {
            self.applyLocalFileProviderSnapshot(providerSnapshot)
        }
    }

    func refreshProviderFromLocalFileSnapshotIfNeeded(_ provider: UsageProvider) async -> Bool {
        guard Self.localFileProviders.contains(provider),
              self.shouldUseLocalFileSource(for: provider)
        else {
            return false
        }

        await self.refreshLocalFileSnapshotIfNeeded(for: provider)

        switch self.localFileSnapshotResolution() {
        case .inactive:
            let path = LocalFileUsageSnapshotStore.defaultFileURL()?.path ?? "unknown"
            self.applyLocalFileUsageError(provider: provider, message: "Local File not found at \(path).")
            return true
        case let .active(snapshot):
            guard let providerSnapshot = snapshot.providerSnapshot(for: provider) else {
                self.applyLocalFileUsageError(
                    provider: provider,
                    message: "Local File does not contain \(provider.rawValue) data.")
                return true
            }
            self.applyLocalFileProviderSnapshot(providerSnapshot)
            return true
        case let .error(message):
            self.applyLocalFileUsageError(provider: provider, message: message)
            return true
        }
    }

    private func refreshLocalFileSnapshotIfNeeded(for provider: UsageProvider) async {
        let environment = ProcessInfo.processInfo.environment
        let destinationURL = LocalFileUsageSnapshotStore.defaultFileURL(env: environment)

        do {
            try await self.localFileSnapshotRefresher.refreshIfNeeded(
                for: provider,
                destinationURL: destinationURL,
                environment: environment)
        } catch {
            // Keep Local File fail-closed semantics, but prefer the freshest readable snapshot if one exists.
        }
    }

    func isCredentialFreeViewerModeEnabled(for provider: UsageProvider) -> Bool {
        LocalFileViewerMode.isEnabled(for: provider, settings: self.settings)
    }

    func isLocalFileSourceActive(for provider: UsageProvider) -> Bool {
        self.isCredentialFreeViewerModeEnabled(for: provider)
    }

    private func applyLocalFileProviderSnapshot(_ providerSnapshot: LocalFileProviderSnapshot) {
        let usage = providerSnapshot.toUsageSnapshot()
        self.handleSessionQuotaTransition(provider: providerSnapshot.provider, snapshot: usage)
        self.snapshots[providerSnapshot.provider] = usage
        self.errors[providerSnapshot.provider] = nil
        self.lastSourceLabels[providerSnapshot.provider] = "local-file"
        self.lastFetchAttempts[providerSnapshot.provider] = []
        self.clearLocalFileProviderState(providerSnapshot.provider)
    }

    private func applyLocalFileUsageError(provider: UsageProvider, message: String) {
        self.snapshots.removeValue(forKey: provider)
        self.errors[provider] = message
        self.lastSourceLabels[provider] = "local-file"
        self.lastFetchAttempts[provider] = []
        self.clearLocalFileProviderState(provider)
    }

    private func clearLocalFileProviderState(_ provider: UsageProvider) {
        self.accountSnapshots.removeValue(forKey: provider)

        if provider == .codex {
            self.clearCodexSensitiveDerivedState()
        }
    }

    private func localFileSnapshotResolution() -> LocalFileSnapshotResolution {
        do {
            guard let snapshot = try LocalFileUsageSnapshotStore.load() else {
                return .inactive
            }
            return .active(snapshot)
        } catch {
            return .error("Local File could not be read: \(error.localizedDescription)")
        }
    }

    private enum LocalFileSnapshotResolution {
        case inactive
        case active(LocalFileUsageSnapshot)
        case error(String)
    }

    private func clearCodexSensitiveDerivedState() {
        self.credits = nil
        self.lastCreditsError = "Credits unavailable in Local File mode."
        self.resetOpenAIWebState()
        self.codexHistoricalDataset = nil
        self.codexHistoricalDatasetAccountKey = nil
        self.historicalPaceRevision += 1
        self.planUtilizationHistory[.codex]?.preferredAccountKey = nil
    }
}
