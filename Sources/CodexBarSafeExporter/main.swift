import CodexBarCore
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
enum CodexBarSafeExporter {
    static func main() async {
        do {
            let command = try ExporterCommand(arguments: Array(CommandLine.arguments.dropFirst()))
            let snapshot = try await command.run()
            if command.destination == .stdout {
                try Self.writeSnapshot(snapshot, pretty: command.pretty)
            }
        } catch let error as ExporterCommandError {
            switch error {
            case .help:
                FileHandle.standardOutput.write(Data("\(error.localizedDescription)\n".utf8))
                exit(0)
            case .invalidArguments:
                Self.fail(error.localizedDescription)
            }
        } catch {
            Self.fail(error.localizedDescription)
        }
    }

    private static func writeSnapshot(_ snapshot: SafeExternalUsageSnapshot, pretty: Bool) throws {
        let encoder = Self.makeEncoder(pretty: pretty)
        let data = try encoder.encode(snapshot)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func makeEncoder(pretty: Bool) -> JSONEncoder {
        let encoder = SafeExternalUsageSnapshotStore.encoder
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return encoder
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        exit(1)
    }
}

struct ExporterCommand {
    enum Destination: Equatable {
        case file(URL)
        case stdout
    }

    let providers: [UsageProvider]
    let destination: Destination
    let pretty: Bool
    let codexFetcher: UsageFetcher
    let browserDetection: BrowserDetection

    init(arguments: [String]) throws {
        var providers: [UsageProvider] = [.codex, .claude]
        var destination: Destination?
        var pretty = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--pretty":
                pretty = true
            case "--stdout":
                destination = .stdout
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw ExporterCommandError.invalidArguments("--output requires a path.")
                }
                destination = .file(URL(fileURLWithPath: arguments[index]).standardizedFileURL)
            case "--providers":
                index += 1
                guard index < arguments.count else {
                    throw ExporterCommandError.invalidArguments("--providers requires a comma-separated list.")
                }
                providers = try Self.parseProviders(arguments[index])
            case "-h", "--help":
                throw ExporterCommandError.help
            default:
                throw ExporterCommandError.invalidArguments("Unknown argument: \(argument)")
            }
            index += 1
        }

        self.providers = providers
        if let destination {
            self.destination = destination
        } else if let defaultURL = SafeExternalUsageSnapshotStore.defaultFileURL() {
            self.destination = .file(defaultURL)
        } else {
            self.destination = .stdout
        }
        self.pretty = pretty
        self.codexFetcher = UsageFetcher()
        self.browserDetection = BrowserDetection()
    }

    func run() async throws -> SafeExternalUsageSnapshot {
        var snapshots: [SafeExternalProviderSnapshot] = []
        snapshots.reserveCapacity(self.providers.count)

        for provider in self.providers {
            switch provider {
            case .codex:
                try await snapshots.append(self.fetchCodex())
            case .claude:
                try await snapshots.append(self.fetchClaude())
            default:
                throw ExporterCommandError.invalidArguments(
                    "Unsupported provider for safe export: \(provider.rawValue)")
            }
        }

        let snapshot = SafeExternalUsageSnapshot(providers: snapshots)
        if case let .file(outputURL) = self.destination {
            try SafeExternalUsageSnapshotStore.save(snapshot, to: outputURL)
        }
        return snapshot
    }

    private func fetchCodex() async throws -> SafeExternalProviderSnapshot {
        do {
            var credentials = try CodexOAuthCredentialsStore.load()
            if credentials.needsRefresh, !credentials.refreshToken.isEmpty {
                credentials = try await CodexTokenRefresher.refresh(credentials)
                try CodexOAuthCredentialsStore.save(credentials)
            }

            let usage = try await CodexOAuthUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId)

            return SafeExternalProviderSnapshot(
                provider: .codex,
                primaryRemainingPercent: usage.rateLimit?.primaryWindow.map { 100 - Double($0.usedPercent) },
                secondaryRemainingPercent: usage.rateLimit?.secondaryWindow.map { 100 - Double($0.usedPercent) },
                tertiaryRemainingPercent: nil,
                primaryResetsAt: usage.rateLimit?.primaryWindow.map {
                    Date(timeIntervalSince1970: TimeInterval($0.resetAt))
                },
                secondaryResetsAt: usage.rateLimit?.secondaryWindow.map {
                    Date(timeIntervalSince1970: TimeInterval($0.resetAt))
                },
                tertiaryResetsAt: nil,
                updatedAt: Date())
        } catch {
            let usage = try await self.codexFetcher.loadLatestUsage()
            return SafeExternalProviderSnapshot(provider: .codex, usage: usage)
        }
    }

    private func fetchClaude() async throws -> SafeExternalProviderSnapshot {
        do {
            let oauthFetcher = ClaudeUsageFetcher(
                browserDetection: self.browserDetection,
                runtime: .app,
                dataSource: .oauth)
            let usage = try await oauthFetcher.loadLatestUsage(model: "sonnet")
            return SafeExternalProviderSnapshot(
                provider: .claude,
                primaryRemainingPercent: usage.primary.remainingPercent,
                secondaryRemainingPercent: usage.secondary?.remainingPercent,
                tertiaryRemainingPercent: usage.opus?.remainingPercent,
                primaryResetsAt: usage.primary.resetsAt,
                secondaryResetsAt: usage.secondary?.resetsAt,
                tertiaryResetsAt: usage.opus?.resetsAt,
                updatedAt: usage.updatedAt)
        } catch {
            let cliFetcher = ClaudeUsageFetcher(
                browserDetection: self.browserDetection,
                runtime: .app,
                dataSource: .cli)
            let usage = try await cliFetcher.loadLatestUsage(model: "sonnet")
            return SafeExternalProviderSnapshot(
                provider: .claude,
                primaryRemainingPercent: usage.primary.remainingPercent,
                secondaryRemainingPercent: usage.secondary?.remainingPercent,
                tertiaryRemainingPercent: usage.opus?.remainingPercent,
                primaryResetsAt: usage.primary.resetsAt,
                secondaryResetsAt: usage.secondary?.resetsAt,
                tertiaryResetsAt: usage.opus?.resetsAt,
                updatedAt: usage.updatedAt)
        }
    }

    static func parseProviders(_ raw: String) throws -> [UsageProvider] {
        let tokens = raw
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !tokens.isEmpty else {
            throw ExporterCommandError.invalidArguments("No valid providers were supplied.")
        }

        var providers: [UsageProvider] = []
        providers.reserveCapacity(tokens.count)

        for token in tokens {
            guard let provider = UsageProvider(rawValue: token) else {
                throw ExporterCommandError.invalidArguments("Unknown provider in --providers: \(token)")
            }
            providers.append(provider)
        }

        return providers
    }
}

enum ExporterCommandError: LocalizedError {
    case help
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .help:
            [
                "CodexBarSafeExporter",
                "",
                "Usage:",
                "  CodexBarSafeExporter [--providers codex,claude] [--output /path/to/safe-usage.json] [--pretty]",
                "  CodexBarSafeExporter --stdout --pretty",
            ].joined(separator: "\n")
        case let .invalidArguments(message):
            message
        }
    }
}
