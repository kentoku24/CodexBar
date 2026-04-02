import CodexBarCore
import Foundation

protocol SafeExternalSnapshotRefreshing: Sendable {
    func refreshIfNeeded(
        for provider: UsageProvider,
        destinationURL: URL?,
        environment: [String: String]) async throws
}

struct SafeExternalSnapshotRefresher: SafeExternalSnapshotRefreshing {
    private let timeout: TimeInterval
    private let logger = CodexBarLog.logger(LogCategories.subprocess)

    init(timeout: TimeInterval = 30) {
        self.timeout = timeout
    }

    func refreshIfNeeded(
        for provider: UsageProvider,
        destinationURL: URL?,
        environment: [String: String]) async throws
    {
        guard provider == .codex else { return }
        guard destinationURL != nil else { return }
        guard let helper = Self.locateBundledHelper("CodexBarSafeExporter", environment: environment) else { return }

        do {
            _ = try await SubprocessRunner.run(
                binary: helper,
                arguments: ["--providers", provider.rawValue],
                environment: environment,
                timeout: self.timeout,
                label: "safe-external-refresh-\(provider.rawValue)")
        } catch {
            self.logger.warning(
                "Safe external snapshot refresh failed",
                metadata: [
                    "provider": provider.rawValue,
                    "error": error.localizedDescription,
                ])
            throw error
        }
    }

    private static func locateBundledHelper(_ name: String, environment: [String: String]) -> String? {
        let fm = FileManager.default

        func isExecutable(_ path: String) -> Bool {
            fm.isExecutableFile(atPath: path)
        }

        if let override = environment["CODEXBAR_HELPER_\(name.uppercased())"], isExecutable(override) {
            return override
        }

        func candidate(inAppBundleURL appURL: URL) -> String? {
            let path = appURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
                .path
            return isExecutable(path) ? path : nil
        }

        let mainURL = Bundle.main.bundleURL
        if mainURL.pathExtension == "app", let found = candidate(inAppBundleURL: mainURL) {
            return found
        }

        if let argv0 = CommandLine.arguments.first {
            var url = URL(fileURLWithPath: argv0)
            if !argv0.hasPrefix("/") {
                url = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(argv0)
            }
            var probe = url
            for _ in 0..<6 {
                let parent = probe.deletingLastPathComponent()
                if parent.pathExtension == "app", let found = candidate(inAppBundleURL: parent) {
                    return found
                }
                if parent.path == probe.path { break }
                probe = parent
            }
        }

        return nil
    }
}
