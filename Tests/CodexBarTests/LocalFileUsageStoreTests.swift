import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct LocalFileUsageStoreTests {
    @Test
    func `local usage file refresh updates snapshot before loading`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-refreshes-local-file")
        settings.codexUsageDataSource = .localUsageFile

        let refreshedSnapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 55,
                    secondaryRemainingPercent: 25,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 1000),
                    secondaryResetsAt: Date(timeIntervalSince1970: 2000),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 3000)),
            ])
        let refresher = TestLocalFileSnapshotRefresher { provider in
            #expect(provider == .codex)
            return refreshedSnapshot
        }
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            localFileSnapshotRefresher: refresher,
            startupBehavior: .testing)
        let staleSnapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 90,
                    secondaryRemainingPercent: 80,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
            ])

        try await Self.withLocalFileSnapshot(staleSnapshot) {
            let applied = await store.refreshProviderFromLocalFileSnapshotIfNeeded(UsageProvider.codex)

            #expect(applied == true)
            #expect(refresher.providers == [.codex])
            #expect(store.snapshot(for: .codex)?.primary?.remainingPercent == 55)
            #expect(store.snapshot(for: .codex)?.updatedAt == Date(timeIntervalSince1970: 3000))
        }
    }

    @Test
    func `local file snapshot applies supported providers without identity leakage`() {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-apply")
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let snapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 72,
                    secondaryRemainingPercent: 41,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
                LocalFileProviderSnapshot(
                    provider: .claude,
                    primaryRemainingPercent: 88,
                    secondaryRemainingPercent: 63,
                    tertiaryRemainingPercent: 91,
                    primaryResetsAt: Date(timeIntervalSince1970: 400),
                    secondaryResetsAt: Date(timeIntervalSince1970: 500),
                    tertiaryResetsAt: Date(timeIntervalSince1970: 550),
                    updatedAt: Date(timeIntervalSince1970: 600)),
            ])

        store.applyLocalFileUsageSnapshot(snapshot)

        #expect(store.snapshot(for: .codex)?.primary?.remainingPercent == 72)
        #expect(store.snapshot(for: .claude) == nil)
        #expect(store.snapshot(for: .codex)?.identity == nil)
        #expect(store.sourceLabel(for: .codex) == "local-file")
        #expect(store.lastCreditsError == "Credits unavailable in Local File mode.")
        #expect(store.error(for: .codex) == nil)
    }

    @Test
    func `local file snapshot only overrides providers present in file`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-subset")
        settings.codexUsageDataSource = .localUsageFile
        settings.claudeUsageDataSource = .auto
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
        let safeSnapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
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

        try await Self.withLocalFileSnapshot(safeSnapshot) {
            #expect(store.shouldUseLocalFileSource(for: .codex) == true)
            #expect(store.shouldUseLocalFileSource(for: .claude) == false)

            let codexApplied = await store.refreshProviderFromLocalFileSnapshotIfNeeded(.codex)
            let claudeApplied = await store.refreshProviderFromLocalFileSnapshotIfNeeded(.claude)

            #expect(codexApplied == true)
            #expect(claudeApplied == false)
            #expect(store.snapshot(for: .codex)?.primary?.remainingPercent == 72)
            #expect(store.snapshot(for: .claude)?.accountEmail(for: .claude) == "claude@example.com")
            #expect(store.error(for: .claude) == nil)
        }
    }

    @Test
    func `auto source ignores local usage file snapshot`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-auto-ignores-local-file")
        settings.codexUsageDataSource = .auto
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let safeSnapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
                    provider: .claude,
                    primaryRemainingPercent: 88,
                    secondaryRemainingPercent: 63,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 400),
                    secondaryResetsAt: Date(timeIntervalSince1970: 500),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 600)),
            ])

        try await Self.withLocalFileSnapshot(safeSnapshot) {
            #expect(store.shouldUseLocalFileSource(for: .codex) == false)
            let applied = await store.refreshProviderFromLocalFileSnapshotIfNeeded(.codex)
            #expect(applied == false)
        }
    }

    @Test
    func `local file snapshot clears stale account snapshots`() {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-account-snapshots")
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
        let safeSnapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
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

        store.applyLocalFileUsageSnapshot(safeSnapshot)

        #expect(store.accountSnapshots[.codex] == nil)
    }

    @Test
    func `credential free viewer mode activates only when local usage file source is selected`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-viewer-mode")
        settings.codexUsageDataSource = .localUsageFile
        settings.claudeUsageDataSource = .auto
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let safeSnapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
                    provider: .claude,
                    primaryRemainingPercent: 88,
                    secondaryRemainingPercent: 63,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 400),
                    secondaryResetsAt: Date(timeIntervalSince1970: 500),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 600)),
            ])

        try await Self.withLocalFileSnapshot(safeSnapshot) {
            #expect(store.isCredentialFreeViewerModeEnabled(for: .codex) == true)
            #expect(store.isCredentialFreeViewerModeEnabled(for: .claude) == false)
            #expect(store.isCredentialFreeViewerModeEnabled(for: .vertexai) == false)
        }
    }

    @Test
    func `local usage file source fails closed when selected provider is absent from snapshot`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-provider-missing")
        settings.codexUsageDataSource = .localUsageFile
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let safeSnapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
                    provider: .claude,
                    primaryRemainingPercent: 88,
                    secondaryRemainingPercent: 63,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 400),
                    secondaryResetsAt: Date(timeIntervalSince1970: 500),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 600)),
            ])

        try await Self.withLocalFileSnapshot(safeSnapshot) {
            #expect(store.shouldUseLocalFileSource(for: .codex) == true)
            let applied = await store.refreshProviderFromLocalFileSnapshotIfNeeded(.codex)
            #expect(applied == true)
            #expect(store.snapshot(for: .codex) == nil)
            #expect(store.error(for: .codex) == "Local File does not contain codex data.")
        }
    }

    @Test
    func `token usage refresh stays available for local usage file mode`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-token-state")
        settings.codexUsageDataSource = .localUsageFile
        settings.costUsageEnabled = true
        let registry = ProviderRegistry.shared
        if let codexMeta = registry.metadata[.codex] {
            settings.setProviderEnabled(provider: .codex, metadata: codexMeta, enabled: true)
        }

        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 8)
        let turnContext: [String: Any] = [
            "type": "turn_context",
            "timestamp": env.isoString(for: day),
            "payload": [
                "cwd": "/tmp/project",
                "model": "gpt-5.3-codex",
            ],
        ]
        let tokenCount: [String: Any] = [
            "type": "event_msg",
            "timestamp": env.isoString(for: day.addingTimeInterval(1)),
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": 100,
                        "cached_input_tokens": 20,
                        "output_tokens": 10,
                    ],
                    "model": "gpt-5.3-codex",
                ],
            ],
        ]
        _ = try env.writeCodexSessionFile(
            day: day,
            filename: "session.jsonl",
            contents: env.jsonl([turnContext, tokenCount]))

        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)

        try await Self.withEnvironment("CODEX_HOME", value: env.codexHomeRoot.path) {
            await store._refreshTokenUsageForTesting(.codex, force: true)

            #expect(store.tokenSnapshot(for: .codex)?.sessionTokens == 110)
            #expect(store.tokenSnapshot(for: .codex)?.last30DaysTokens == 110)
            #expect(store.tokenError(for: .codex) == nil)
        }
    }

    @Test
    func `credential free viewer mode protects codex when explicit safe path is missing`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-explicit-missing")
        settings.codexUsageDataSource = .localUsageFile
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-file-missing-\(UUID().uuidString).json")
            .path

        try await Self.withLocalFilePath(missingPath) {
            #expect(LocalFileViewerMode.isEnabled(for: .codex, settings: settings) == true)
            #expect(LocalFileViewerMode.isEnabled(for: .claude, settings: settings) == false)
            #expect(LocalFileViewerMode.isEnabled(for: .vertexai, settings: settings) == false)
        }
    }

    @Test
    func `missing explicit safe path hides persisted plan utilization history`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-missing-plan-history")
        settings.codexUsageDataSource = .localUsageFile
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
            .appendingPathComponent("local-file-plan-history-missing-\(UUID().uuidString).json")
            .path

        try await Self.withLocalFilePath(missingPath) {
            #expect(store.isLocalFileSourceActive(for: .codex) == true)
            #expect(store.shouldHidePlanUtilizationMenuItem(for: .codex) == true)
            #expect(store.planUtilizationHistory(for: .codex).isEmpty)
        }
    }

    @Test
    func `account info accessor hides codex account in local file mode`() async throws {
        let settings = Self.makeSettingsStore(suite: "LocalFileUsageStoreTests-account-info")
        settings.codexUsageDataSource = .localUsageFile
        let store = UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let safeSnapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 72,
                    secondaryRemainingPercent: 41,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 100),
                    secondaryResetsAt: Date(timeIntervalSince1970: 200),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 300)),
            ])

        try await Self.withLocalFileSnapshot(safeSnapshot) {
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

    private static func withLocalFileSnapshot<T>(
        _ snapshot: LocalFileUsageSnapshot,
        operation: () async throws -> T) async throws -> T
    {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-file-\(UUID().uuidString).json")
        try LocalFileUsageSnapshotStore.save(snapshot, to: url)

        return try await Self.withLocalFilePath(url.path) {
            defer {
                try? FileManager.default.removeItem(at: url)
            }
            return try await operation()
        }
    }

    private static func withLocalFilePath<T>(
        _ path: String,
        operation: () async throws -> T) async throws -> T
    {
        try await self.withEnvironment(LocalFileUsageSnapshotStore.environmentPathKey, value: path) {
            try await operation()
        }
    }

    private static func withEnvironment<T>(
        _ key: String,
        value: String,
        operation: () async throws -> T) async throws -> T
    {
        let original = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
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

private final class TestLocalFileSnapshotRefresher: LocalFileSnapshotRefreshing, @unchecked Sendable {
    private let makeSnapshot: @Sendable (UsageProvider) async throws -> LocalFileUsageSnapshot
    private(set) var providers: [UsageProvider] = []

    init(makeSnapshot: @escaping @Sendable (UsageProvider) async throws -> LocalFileUsageSnapshot) {
        self.makeSnapshot = makeSnapshot
    }

    func refreshIfNeeded(
        for provider: UsageProvider,
        destinationURL: URL?,
        environment: [String: String]) async throws
    {
        self.providers.append(provider)
        let snapshot = try await self.makeSnapshot(provider)
        let url = try #require(destinationURL)
        try LocalFileUsageSnapshotStore.save(snapshot, to: url)
    }
}
