import Foundation

public struct LocalFileUsageSnapshot: Codable, Equatable, Sendable {
    public let providers: [LocalFileProviderSnapshot]

    public init(providers: [LocalFileProviderSnapshot]) {
        self.providers = providers.sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    public func providerSnapshot(for provider: UsageProvider) -> LocalFileProviderSnapshot? {
        self.providers.first { $0.provider == provider }
    }
}

public struct LocalFileProviderSnapshot: Codable, Equatable, Sendable {
    public let provider: UsageProvider
    public let primaryRemainingPercent: Double?
    public let secondaryRemainingPercent: Double?
    public let tertiaryRemainingPercent: Double?
    public let primaryResetsAt: Date?
    public let secondaryResetsAt: Date?
    public let tertiaryResetsAt: Date?
    public let updatedAt: Date

    public init(
        provider: UsageProvider,
        primaryRemainingPercent: Double?,
        secondaryRemainingPercent: Double?,
        tertiaryRemainingPercent: Double?,
        primaryResetsAt: Date?,
        secondaryResetsAt: Date?,
        tertiaryResetsAt: Date?,
        updatedAt: Date)
    {
        self.provider = provider
        self.primaryRemainingPercent = Self.clamp(primaryRemainingPercent)
        self.secondaryRemainingPercent = Self.clamp(secondaryRemainingPercent)
        self.tertiaryRemainingPercent = Self.clamp(tertiaryRemainingPercent)
        self.primaryResetsAt = primaryResetsAt
        self.secondaryResetsAt = secondaryResetsAt
        self.tertiaryResetsAt = tertiaryResetsAt
        self.updatedAt = updatedAt
    }

    public init(provider: UsageProvider, usage: UsageSnapshot) {
        self.init(
            provider: provider,
            primaryRemainingPercent: usage.primary?.remainingPercent,
            secondaryRemainingPercent: usage.secondary?.remainingPercent,
            tertiaryRemainingPercent: usage.tertiary?.remainingPercent,
            primaryResetsAt: usage.primary?.resetsAt,
            secondaryResetsAt: usage.secondary?.resetsAt,
            tertiaryResetsAt: usage.tertiary?.resetsAt,
            updatedAt: usage.updatedAt)
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            primary: Self.makeWindow(
                remainingPercent: self.primaryRemainingPercent,
                resetsAt: self.primaryResetsAt),
            secondary: Self.makeWindow(
                remainingPercent: self.secondaryRemainingPercent,
                resetsAt: self.secondaryResetsAt),
            tertiary: Self.makeWindow(
                remainingPercent: self.tertiaryRemainingPercent,
                resetsAt: self.tertiaryResetsAt),
            updatedAt: self.updatedAt,
            identity: nil)
    }

    private static func makeWindow(remainingPercent: Double?, resetsAt: Date?) -> RateWindow? {
        guard let remainingPercent else { return nil }
        let usedPercent = max(0, min(100, 100 - remainingPercent))
        let resetDescription = resetsAt.map { UsageFormatter.resetDescription(from: $0) }
        return RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: resetsAt,
            resetDescription: resetDescription)
    }

    private static func clamp(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return max(0, min(100, value))
    }
}

public enum LocalFileUsageSnapshotStore {
    public static let environmentPathKey = "CODEXBAR_SAFE_USAGE_PATH"

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func load(from url: URL) throws -> LocalFileUsageSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try self.decoder.decode(LocalFileUsageSnapshot.self, from: data)
    }

    public static func load(env: [String: String] = ProcessInfo.processInfo
        .environment) throws -> LocalFileUsageSnapshot?
    {
        guard let url = self.defaultFileURL(env: env) else { return nil }
        return try self.load(from: url)
    }

    public static func save(_ snapshot: LocalFileUsageSnapshot, to url: URL) throws {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".safe-usage-\(UUID().uuidString).tmp")
        let data = try self.encoder.encode(snapshot)
        try data.write(to: temporaryURL, options: .atomic)
        try self.setPrivatePermissions(at: temporaryURL)

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: url)
        }

        try self.setPrivatePermissions(at: url)
    }

    public static func save(
        _ snapshot: LocalFileUsageSnapshot,
        env: [String: String] = ProcessInfo.processInfo.environment) throws
    {
        guard let url = self.defaultFileURL(env: env) else { return }
        try self.save(snapshot, to: url)
    }

    public static func fileExists(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let url = self.defaultFileURL(env: env) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func defaultFileURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) -> URL?
    {
        if let override = env[self.environmentPathKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return URL(fileURLWithPath: override).standardizedFileURL
        }

        guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = root.appendingPathComponent("com.steipete.codexbar", isDirectory: true)
        return directory.appendingPathComponent("safe-usage.json")
    }

    private static func setPrivatePermissions(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
