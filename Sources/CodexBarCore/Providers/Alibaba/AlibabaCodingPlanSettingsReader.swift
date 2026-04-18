import Foundation

public struct AlibabaCodingPlanSettingsReader: Sendable {
    public static let apiTokenKey = "ALIBABA_CODING_PLAN_API_KEY"
    public static let cookieHeaderKey = "ALIBABA_CODING_PLAN_COOKIE"
    public static let hostKey = "ALIBABA_CODING_PLAN_HOST"
    public static let quotaURLKey = "ALIBABA_CODING_PLAN_QUOTA_URL"

    public static func apiToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.cleaned(environment[self.apiTokenKey])
    }

    public static func hostOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        guard let raw = self.cleaned(environment[self.hostKey]),
              let url = self.validatedAlibabaURL(raw)
        else {
            return nil
        }

        guard let host = url.host else { return nil }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    public static func cookieHeader(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.cleaned(environment[self.cookieHeaderKey])
    }

    public static func quotaURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        guard let raw = self.cleaned(environment[self.quotaURLKey]) else { return nil }
        return self.validatedAlibabaURL(raw)
    }

    static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value.removeFirst()
            value.removeLast()
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func validatedAlibabaURL(_ raw: String) -> URL? {
        let candidate: URL? = if let url = URL(string: raw), url.scheme != nil {
            url
        } else {
            URL(string: "https://\(raw)")
        }
        guard let candidate else { return nil }
        guard candidate.scheme?.lowercased() == "https" else { return nil }
        guard let host = candidate.host?.lowercased(), self.isAllowedAlibabaHost(host) else {
            return nil
        }
        return candidate
    }

    private static func isAllowedAlibabaHost(_ host: String) -> Bool {
        let normalized = host.hasSuffix(".") ? String(host.dropLast()) : host
        let suffixes = [".aliyun.com", ".alibabacloud.com", ".aliyuncs.com"]
        return suffixes.contains { normalized == String($0.dropFirst()) || normalized.hasSuffix($0) }
    }
}

public enum AlibabaCodingPlanSettingsError: LocalizedError, Sendable {
    case missingToken
    case missingCookie(details: String? = nil)
    case invalidCookie

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Alibaba Coding Plan API key not found. " +
                "Set apiKey in ~/.codexbar/config.json or ALIBABA_CODING_PLAN_API_KEY."
        case let .missingCookie(details):
            let base = "No Alibaba Coding Plan session cookies found in browsers. " +
                "If you use Safari, enable Full Disk Access for CodexBar/Terminal or paste a manual Cookie header."
            guard let details, !details.isEmpty else { return base }
            return "\(base) \(details)"
        case .invalidCookie:
            return "Alibaba Coding Plan cookie header is invalid."
        }
    }
}
