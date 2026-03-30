import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct SafeExternalUsageStoreTests {
    @Test
    func `safe snapshot applies codex and claude without identity leakage`() {
        let settings = Self.makeSettingsStore(suite: "SafeExternalUsageStoreTests-apply")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let snapshot = SafeExternalUsageSnapshot(
            providers: [
                SafeExternalProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 72,
                    secondaryRemainingPercent: 41,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
                SafeExternalProviderSnapshot(
                    provider: .claude,
                    primaryRemainingPercent: 88,
                    secondaryRemainingPercent: 63,
                    tertiaryRemainingPercent: 91,
                    primaryResetsAt: Date(timeIntervalSince1970: 400),
                    secondaryResetsAt: Date(timeIntervalSince1970: 500),
                    tertiaryResetsAt: Date(timeIntervalSince1970: 550),
                    updatedAt: Date(timeIntervalSince1970: 600)),
            ])

        store.applySafeExternalUsageSnapshot(snapshot)

        #expect(store.snapshot(for: .codex)?.primary?.remainingPercent == 72)
        #expect(store.snapshot(for: .claude)?.secondary?.remainingPercent == 63)
        #expect(store.snapshot(for: .claude)?.tertiary?.remainingPercent == 91)
        #expect(store.snapshot(for: .codex)?.identity == nil)
        #expect(store.sourceLabel(for: .codex) == "safe-external")
        #expect(store.error(for: .codex) == nil)
    }

    @Test
    func `safe snapshot only overrides providers present in file`() async throws {
        let settings = Self.makeSettingsStore(suite: "SafeExternalUsageStoreTests-subset")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let existingClaudeSnapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 20,
                windowMinutes: 60,
                resetsAt: Date(timeIntervalSince1970: 900),
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: Date(timeIntervalSince1970: 901),
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: "claude@example.com",
                accountOrganization: nil,
                loginMethod: nil))
        let safeSnapshot = SafeExternalUsageSnapshot(
            providers: [
                SafeExternalProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 72,
                    secondaryRemainingPercent: 41,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
            ])

        store.snapshots[.claude] = existingClaudeSnapshot

        try await Self.withSafeExternalSnapshot(safeSnapshot) {
            #expect(store.shouldUseSafeExternalSource(for: .codex) == true)
            #expect(store.shouldUseSafeExternalSource(for: .claude) == false)

            let codexApplied = await store.refreshProviderFromSafeExternalSnapshotIfNeeded(.codex)
            let claudeApplied = await store.refreshProviderFromSafeExternalSnapshotIfNeeded(.claude)

            #expect(codexApplied == true)
            #expect(claudeApplied == false)
            #expect(store.snapshot(for: .codex)?.primary?.remainingPercent == 72)
            #expect(store.snapshot(for: .claude)?.accountEmail(for: .claude) == "claude@example.com")
            #expect(store.error(for: .claude) == nil)
        }
    }

    @Test
    func `safe snapshot clears stale account snapshots`() {
        let settings = Self.makeSettingsStore(suite: "SafeExternalUsageStoreTests-account-snapshots")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let account = ProviderTokenAccount(
            id: UUID(),
            label: "work",
            token: "secret-token",
            addedAt: 100,
            lastUsed: nil)
        let staleAccountSnapshot = TokenAccountUsageSnapshot(
            account: account,
            snapshot: UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 40,
                    windowMinutes: 60,
                    resetsAt: Date(timeIntervalSince1970: 120),
                    resetDescription: nil),
                secondary: nil,
                tertiary: nil,
                updatedAt: Date(timeIntervalSince1970: 121),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "stale@example.com",
                    accountOrganization: nil,
                    loginMethod: nil)),
            error: nil,
            sourceLabel: "oauth")
        let safeSnapshot = SafeExternalUsageSnapshot(
            providers: [
                SafeExternalProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 72,
                    secondaryRemainingPercent: 41,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
            ])

        store.accountSnapshots[.codex] = [staleAccountSnapshot]

        store.applySafeExternalUsageSnapshot(safeSnapshot)

        #expect(store.accountSnapshots[.codex] == nil)
    }

    @Test
    func `credential free viewer mode activates only for providers present in safe snapshot`() async throws {
        let settings = Self.makeSettingsStore(suite: "SafeExternalUsageStoreTests-viewer-mode")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let safeSnapshot = SafeExternalUsageSnapshot(
            providers: [
                SafeExternalProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 72,
                    secondaryRemainingPercent: 41,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
            ])

        try await Self.withSafeExternalSnapshot(safeSnapshot) {
            #expect(store.isCredentialFreeViewerModeEnabled(for: .codex) == true)
            #expect(store.isCredentialFreeViewerModeEnabled(for: .claude) == false)
            #expect(store.isCredentialFreeViewerModeEnabled(for: .vertexai) == false)
        }
    }

    @Test
    func `token usage refresh clears safe external provider token state`() async throws {
        let settings = Self.makeSettingsStore(suite: "SafeExternalUsageStoreTests-token-state")
        settings.costUsageEnabled = true
        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }
        if let claudeMeta = registry.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: claudeMeta, enabled: true)
        }

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 123,
                sessionCostUSD: 0.12,
                last30DaysTokens: 456,
                last30DaysCostUSD: 1.23,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 999)),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 321,
                sessionCostUSD: 0.21,
                last30DaysTokens: 654,
                last30DaysCostUSD: 3.21,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1000)),
            provider: .claude)
        store._setTokenErrorForTesting("stale-codex", provider: .codex)
        store._setTokenErrorForTesting("stale-claude", provider: .claude)

        let safeSnapshot = SafeExternalUsageSnapshot(
            providers: [
                SafeExternalProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 72,
                    secondaryRemainingPercent: 41,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
                SafeExternalProviderSnapshot(
                    provider: .claude,
                    primaryRemainingPercent: 88,
                    secondaryRemainingPercent: 63,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 400),
                    secondaryResetsAt: Date(timeIntervalSince1970: 500),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 600)),
            ])

        try await Self.withSafeExternalSnapshot(safeSnapshot) {
            await store._refreshTokenUsageForTesting(.codex, force: true)
            await store._refreshTokenUsageForTesting(.claude, force: true)

            #expect(store.tokenSnapshot(for: .codex) == nil)
            #expect(store.tokenSnapshot(for: .claude) == nil)
            #expect(store.tokenError(for: .codex) == "Cost usage unavailable in safe external mode.")
            #expect(store.tokenError(for: .claude) == "Cost usage unavailable in safe external mode.")
        }
    }

    @Test
    func `credential free viewer mode protects codex and claude when explicit safe path is missing`() async throws {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-external-missing-\(UUID().uuidString).json")
            .path

        try await Self.withSafeExternalPath(missingPath) {
            #expect(SafeExternalViewerMode.isEnabled(for: .codex) == true)
            #expect(SafeExternalViewerMode.isEnabled(for: .claude) == true)
            #expect(SafeExternalViewerMode.isEnabled(for: .vertexai) == false)
        }
    }

    @Test
    func `missing explicit safe path hides persisted plan utilization history`() async throws {
        let settings = Self.makeSettingsStore(suite: "SafeExternalUsageStoreTests-missing-plan-history")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let weekly = PlanUtilizationSeriesHistory(
            name: .weekly,
            windowMinutes: 10080,
            entries: [
                PlanUtilizationHistoryEntry(
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    usedPercent: 64,
                    resetsAt: Date(timeIntervalSince1970: 1_700_086_400)),
            ])
        store.planUtilizationHistory[.codex] = PlanUtilizationHistoryBuckets(unscoped: [weekly])

        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-external-plan-history-missing-\(UUID().uuidString).json")
            .path

        try await Self.withSafeExternalPath(missingPath) {
            #expect(store.isSafeExternalSourceActive(for: .codex) == true)
            #expect(store.shouldHidePlanUtilizationMenuItem(for: .codex) == true)
            #expect(store.planUtilizationHistory(for: .codex).isEmpty)
        }
    }

    @Test
    func `account info accessor hides codex account in safe external mode`() async throws {
        let settings = Self.makeSettingsStore(suite: "SafeExternalUsageStoreTests-account-info")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let safeSnapshot = SafeExternalUsageSnapshot(
            providers: [
                SafeExternalProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 72,
                    secondaryRemainingPercent: 41,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
            ])

        try await Self.withSafeExternalSnapshot(safeSnapshot) {
            #expect(store.accountInfo() == AccountInfo(email: nil, plan: nil))
        }
    }

    private static func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            tokenAccountStore: InMemoryTokenAccountStore())
    }

    private static func withSafeExternalSnapshot<T>(
        _ snapshot: SafeExternalUsageSnapshot,
        operation: () async throws -> T) async throws -> T
    {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("safe-external-\(UUID().uuidString).json")
        try SafeExternalUsageSnapshotStore.save(snapshot, to: url)

        return try await Self.withSafeExternalPath(url.path) {
            defer {
                try? FileManager.default.removeItem(at: url)
            }
            return try await operation()
        }
    }

    private static func withSafeExternalPath<T>(
        _ path: String,
        operation: () async throws -> T) async throws -> T
    {
        let key = SafeExternalUsageSnapshotStore.environmentPathKey
        let original = getenv(key).map { String(cString: $0) }
        setenv(key, path, 1)
        defer {
            if let original {
                setenv(key, original, 1)
            } else {
                unsetenv(key)
            }
        }

        return try await operation()
    }
}
