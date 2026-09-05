import Foundation

/// Google's multi-login is cookie based: the same browser session can hold
/// several signed-in Google accounts, addressed either by a `/u/<n>/` path
/// segment (`calendar.google.com/calendar/u/1/r/month`) or by the
/// `?authuser=<n>` query parameter. This rewrites a URL to a given account.
enum Accounts {
    static let maxAccounts = 9

    /// Returns `url` pointed at `account` (0-based), preserving everything else.
    ///
    /// Strategy, in order:
    ///  1. If the path already contains `/u/<n>/`, replace that number.
    ///  2. If the query already contains `authuser=<n>`, replace that.
    ///  3. Otherwise add `?authuser=<n>` (works for any Google property, even
    ///     ones whose path shape we do not know).
    static func url(_ string: String, account: Int) -> String {
        precondition(account >= 0)
        guard var comps = URLComponents(string: string),
              let host = comps.host,
              host.lowercased().hasSuffix("google.com") || host.lowercased() == "gmail.com"
        else { return string }

        // Never rewrite the account chooser itself; it manages accounts by design.
        if host.lowercased() == "accounts.google.com" { return string }

        // 1. path segment
        let pattern = "/u/[0-9]+"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: comps.path, range: NSRange(comps.path.startIndex..., in: comps.path)) {
            let replaced = comps.path.replacingCharacters(in: Range(match.range, in: comps.path)!, with: "/u/\(account)")
            comps.path = replaced
            return comps.url?.absoluteString ?? string
        }

        // 2. existing authuser
        var items = comps.queryItems ?? []
        if let idx = items.firstIndex(where: { $0.name.lowercased() == "authuser" }) {
            items[idx] = URLQueryItem(name: "authuser", value: account == 0 ? "0" : String(account))
            comps.queryItems = items
            return comps.url?.absoluteString ?? string
        }

        // 3. append authuser
        items.append(URLQueryItem(name: "authuser", value: String(account)))
        comps.queryItems = items
        return comps.url?.absoluteString ?? string
    }

    /// Best-effort guess at which account `url` is showing (nil if unknown).
    static func account(of string: String) -> Int? {
        guard let comps = URLComponents(string: string) else { return nil }
        if let match = try? NSRegularExpression(pattern: "/u/([0-9]+)")
            .firstMatch(in: comps.path, range: NSRange(comps.path.startIndex..., in: comps.path)),
           let range = Range(match.range(at: 1), in: comps.path) {
            return Int(comps.path[range])
        }
        if let item = comps.queryItems?.first(where: { $0.name.lowercased() == "authuser" }),
           let value = item.value {
            return Int(value)
        }
        return nil
    }
}
