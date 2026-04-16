import CodexBarCore
import Foundation
import Testing

struct LocalFileUsageSnapshotTests {
    @Test
    func `local file snapshot encodes only sanitized quota fields`() throws {
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
            ])

        let data = try LocalFileUsageSnapshotStore.encoder.encode(snapshot)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let provider = try #require((json["providers"] as? [[String: Any]])?.first)

        #expect(provider["provider"] as? String == "codex")
        #expect(provider["primaryRemainingPercent"] as? Double == 72)
        #expect(provider["secondaryRemainingPercent"] as? Double == 41)
        #expect(provider["accountEmail"] == nil)
        #expect(provider["credits"] == nil)
    }

    @Test
    func `local file snapshot store round trips and persists private permissions`() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("local-file-\(UUID().uuidString)", isDirectory: true)
        let url = root.appendingPathComponent("safe-usage.json")
        let snapshot = LocalFileUsageSnapshot(
            providers: [
                LocalFileProviderSnapshot(
                    provider: .codex,
                    primaryRemainingPercent: 88,
                    secondaryRemainingPercent: 63,
                    tertiaryRemainingPercent: nil,
                    primaryResetsAt: Date(timeIntervalSince1970: 400),
                    secondaryResetsAt: Date(timeIntervalSince1970: 500),
                    tertiaryResetsAt: nil,
                    updatedAt: Date(timeIntervalSince1970: 600)),
            ])

        try LocalFileUsageSnapshotStore.save(snapshot, to: url)
        let loaded = try LocalFileUsageSnapshotStore.load(from: url)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)

        #expect(loaded == snapshot)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test
    func `provider snapshot derives usage snapshot without identity`() {
        let safe = LocalFileProviderSnapshot(
            provider: .codex,
            primaryRemainingPercent: 55,
            secondaryRemainingPercent: 20,
            tertiaryRemainingPercent: 10,
            primaryResetsAt: Date(timeIntervalSince1970: 700),
            secondaryResetsAt: Date(timeIntervalSince1970: 800),
            tertiaryResetsAt: Date(timeIntervalSince1970: 850),
            updatedAt: Date(timeIntervalSince1970: 900))

        let usage = safe.toUsageSnapshot()

        #expect(usage.primary?.remainingPercent == 55)
        #expect(usage.secondary?.remainingPercent == 20)
        #expect(usage.tertiary?.remainingPercent == 10)
        #expect(usage.identity == nil)
    }
}
