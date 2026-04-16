import CodexBarCore
import Testing
@testable import CodexBarSafeExporter

struct LocalFileExporterTests {
    @Test
    func `default exporter providers are codex only`() throws {
        let command = try ExporterCommand(arguments: ["--stdout"])

        #expect(command.providers == [.codex])
    }

    @Test
    func `providers parser keeps explicit single provider exports`() throws {
        let command = try ExporterCommand(arguments: ["--providers", "codex", "--stdout"])

        #expect(command.providers == [.codex])
    }

    @Test
    func `providers parser rejects claude export requests`() {
        #expect(throws: ExporterCommandError.self) {
            _ = try ExporterCommand(arguments: ["--providers", "claude", "--stdout"])
        }
    }

    @Test
    func `providers parser rejects mixed valid and invalid provider names`() {
        #expect(throws: ExporterCommandError.self) {
            _ = try ExporterCommand(arguments: ["--providers", "codex,cluade", "--stdout"])
        }
    }
}
