import Foundation

/// Decides whether what you typed is a web address.
///
/// The hard part is *not* matching things that merely look like one:
/// `readme.md`, `script.sh` and `v1.co` are all valid-looking hosts, and `.md`
/// and `.sh` are real top-level domains. Rather than ship a 1,500-entry TLD
/// list, anything without a scheme has to end in a domain people actually
/// browse — which keeps filenames out of the launcher.
enum URLDetector {
    /// Endings that collide with things you actually have on disk. `.app`,
    /// `.sh` and `.md` are all real top-level domains, so `Omnicast.app` and
    /// `build.sh` would otherwise become web addresses inside a launcher —
    /// which is almost never what someone means. Add a path or a scheme
    /// (`linear.app/pricing`, `https://linear.app`) to browse them anyway.
    static let collidesWithFilenames: Set<String> = ["app", "sh", "md", "py", "rb", "js", "ts"]

    /// Enough to cover what anyone types into a launcher by hand.
    static let commonTopLevelDomains: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int", "info", "biz",
        "io", "ai", "app", "dev", "sh", "co", "me", "tv", "fm", "gg", "xyz",
        "cloud", "page", "site", "tech", "online", "store", "blog", "wiki",
        "uk", "us", "ca", "de", "fr", "es", "it", "nl", "se", "no", "fi", "dk",
        "in", "jp", "cn", "kr", "au", "nz", "br", "mx", "ru", "pl", "ch", "at",
        "be", "ie", "pt", "gr", "cz", "tr", "za", "sg", "hk", "ae", "il", "eu",
    ]

    /// `nil` when this is not a web address.
    static func url(from query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }

        // An explicit scheme is the user telling us outright.
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard let url = URL(string: trimmed), url.host?.isEmpty == false else { return nil }
            return url
        }
        // Anything else with a scheme is somebody else's business.
        if trimmed.contains("://") { return nil }

        let parts = trimmed.split(separator: "/", maxSplits: 1)
        let hostPart = parts.first.map(String.init) ?? trimmed
        let hasPath = parts.count > 1
        let withoutPort = hostPart.split(separator: ":").first.map(String.init) ?? hostPart

        // localhost and localhost:3000 are addresses even without a dot.
        if withoutPort == "localhost" { return URL(string: "http://\(trimmed)") }

        let labels = withoutPort.split(separator: ".").map(String.init)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }),
            let tld = labels.last?.lowercased(), commonTopLevelDomains.contains(tld),
            labels.allSatisfy({ $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } })
        else { return nil }

        // A bare `Omnicast.app` is a bundle; `linear.app/pricing` is a site.
        if !hasPath && collidesWithFilenames.contains(tld) { return nil }

        return URL(string: "https://\(trimmed)")
    }

    /// The host a favicon and a history row are keyed on.
    static func host(of url: URL) -> String {
        (url.host ?? url.absoluteString).lowercased()
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }
}
