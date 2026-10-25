import Foundation

/// `littlebabylog://` URLs: how widgets and Live Activities open the app for things that need UI.
///
///     littlebabylog://log/<kind>?baby=<uuid>     new-entry editor (bottle amount, solids, ...)
///     littlebabylog://nursing?baby=<uuid>        the nursing timer (starts one if none is running)
///     littlebabylog://today?baby=<uuid>          just show Today
///
/// `baby` is optional everywhere; without it the app keeps its current baby.
public enum DeepLink: Equatable, Sendable {
    public static let scheme = "littlebabylog"

    case log(EventKind, babyID: UUID?)
    case nursing(babyID: UUID?)
    case today(babyID: UUID?)

    public var babyID: UUID? {
        switch self {
        case .log(_, let id), .nursing(let id), .today(let id): return id
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .log(let kind, _):
            components.host = "log"
            components.path = "/" + kind.rawValue
        case .nursing:
            components.host = "nursing"
        case .today:
            components.host = "today"
        }
        if let babyID {
            components.queryItems = [URLQueryItem(name: "baby", value: babyID.uuidString)]
        }
        return components.url ?? URL(string: "\(Self.scheme)://today")!
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        let babyID = components.queryItems?
            .first(where: { $0.name == "baby" })?.value
            .flatMap(UUID.init(uuidString:))

        switch host {
        case "log":
            let name = components.path.split(separator: "/").first.map(String.init)?.lowercased()
            guard let name, let kind = EventKind.allCases.first(where: { $0.rawValue.lowercased() == name }) else {
                return nil
            }
            self = .log(kind, babyID: babyID)
        case "nursing":
            self = .nursing(babyID: babyID)
        case "today":
            self = .today(babyID: babyID)
        default:
            return nil
        }
    }
}
