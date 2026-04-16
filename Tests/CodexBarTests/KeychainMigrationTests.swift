import CodexBarCore
import Testing
@testable import CodexBar

struct KeychainMigrationTests {
    @Test
    func `migration list covers known keychain items`() {
        let items = Set(KeychainMigration.itemsToMigrate.map(\.label))
        let expected: Set = [
            "com.steipete.CodexBar:codex-cookie",
            "com.steipete.CodexBar:claude-cookie",
            "com.steipete.CodexBar:cursor-cookie",
            "com.steipete.CodexBar:factory-cookie",
            "com.steipete.CodexBar:minimax-cookie",
            "com.steipete.CodexBar:minimax-api-token",
            "com.steipete.CodexBar:augment-cookie",
            "com.steipete.CodexBar:copilot-api-token",
            "com.steipete.CodexBar:zai-api-token",
            "com.steipete.CodexBar:synthetic-api-key",
        ]

        let missing = expected.subtracting(items)
        #expect(missing.isEmpty, "Missing migration entries: \(missing.sorted())")
    }

    @Test
    func `migration list excludes local file protected providers`() {
        let protected: Set<UsageProvider> = [.codex, .claude]
        let items = Set(KeychainMigration.itemsToMigrate(protectedProviders: protected).map(\.label))

        #expect(items.contains("com.steipete.CodexBar:codex-cookie") == false)
        #expect(items.contains("com.steipete.CodexBar:claude-cookie"))
        #expect(items.contains("com.steipete.CodexBar:cursor-cookie"))
    }
}
