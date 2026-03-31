import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
struct HistoricalUsagePaceLocalUsageFileTests {
    @MainActor
    @Test
    func `usage store keeps linear forecast for local usage file`() throws {
        let suite = "HistoricalUsagePaceTests-local-usage-file"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            kimiK2TokenStore: InMemoryKimiK2TokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.historicalTrackingEnabled = true
        settings.codexUsageDataSource = .localUsageFile

        let planHistoryStore = testPlanUtilizationHistoryStore(
            suiteName: "HistoricalUsagePaceTests-\(UUID().uuidString)")
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            historicalUsageHistoryStore: HistoricalUsageHistoryStore(fileURL: HistoricalUsagePaceTests.makeTempURL()),
            planUtilizationHistoryStore: planHistoryStore)

        let now = Date(timeIntervalSince1970: 0)
        let duration = TimeInterval(10080 * 60)
        let resetsAt = now.addingTimeInterval(duration / 2)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 10080,
            resetsAt: resetsAt,
            resetDescription: nil)

        let historicalWeeks = (0..<5).map { index in
            HistoricalWeekProfile(
                resetsAt: resetsAt.addingTimeInterval(-duration * Double(index + 1)),
                windowMinutes: 10080,
                curve: HistoricalUsagePaceTests.outlierCurve())
        }
        store._setCodexHistoricalDatasetForTesting(CodexHistoricalDataset(weeks: historicalWeeks))

        let computed = store.weeklyPace(provider: .codex, window: window, now: now)
        let linear = try #require(UsagePace.weekly(window: window, now: now, defaultWindowMinutes: 10080))

        #expect(computed != nil)
        #expect(abs((computed?.expectedUsedPercent ?? 0) - linear.expectedUsedPercent) < 0.001)
        #expect(abs((computed?.deltaPercent ?? 0) - linear.deltaPercent) < 0.001)
        #expect(computed?.runOutProbability == nil)
    }
}
