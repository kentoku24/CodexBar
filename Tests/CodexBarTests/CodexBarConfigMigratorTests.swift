import CodexBarCore
import Testing
@testable import CodexBar

struct CodexBarConfigMigratorTests {
    @Test
    func `legacy secret migration excludes safe external protected providers`() {
        let requested: Set<UsageProvider> = [.codex, .claude]
        let protected = CodexBarConfigMigrator.legacySecretProtectedProviders(for: requested)

        #expect(protected.contains(.codex))
        #expect(protected.contains(.claude) == false)

        let migratedCookies = CodexBarConfigMigrator.legacyCookieProvidersToMigrate(
            protectedProviders: protected)
        #expect(migratedCookies.contains(.codex) == false)
        #expect(migratedCookies.contains(.claude))
        #expect(migratedCookies.contains(.cursor))
    }
}
