import CloudKit
import Foundation

/// A sync or sharing failure in plain language, with the technical text kept alongside so a tester can still send it.
///
/// CloudKit errors arrive wrapped in several layers (Core Data's "mirroring delegate" error around a `CKError`,
/// partial failures, underlying errors). `classify` looks through all of them for the most useful cause.
public struct CloudSyncProblem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// No iCloud account on this phone (or it is temporarily signed out).
        case notSignedIn
        /// iCloud is restricted on this phone (Screen Time, a managed device).
        case restricted
        /// No internet connection.
        case offline
        /// The person's iCloud storage is full.
        case storageFull
        /// iCloud asked us to slow down or is briefly unavailable.
        case busy
        /// This build has iCloud turned off.
        case syncOff
        /// Anything else. The details tell the story.
        case other
    }

    public var kind: Kind
    /// What to show the person.
    public var message: String
    /// The raw error text and codes, for the "Details" disclosure.
    public var technicalDetails: String

    public init(kind: Kind, message: String, technicalDetails: String) {
        self.kind = kind
        self.message = message
        self.technicalDetails = technicalDetails
    }

    public static func message(for kind: Kind) -> String {
        switch kind {
        case .notSignedIn: return "Sign in to iCloud in Settings to share."
        case .restricted: return "iCloud is restricted on this phone, so sharing isn't available."
        case .offline: return "You're offline. Connect to the internet and try again."
        case .storageFull: return "Your iCloud storage is full. Free up space or get more storage in Settings, then try again."
        case .busy: return "iCloud is busy right now. Try again in a few minutes."
        case .syncOff: return "iCloud sync is turned off in this build."
        case .other: return "iCloud sync isn't working right now."
        }
    }

    public static func classify(_ error: Error) -> CloudSyncProblem {
        var kinds: [Kind] = []
        var lines: [String] = []
        var seen = Set<ObjectIdentifier>()
        walk(error as NSError, depth: 0, seen: &seen, kinds: &kinds, lines: &lines)
        if case .cloudSyncDisabled? = error as? SharingError { kinds.append(.syncOff) }

        let kind = kinds.min(by: { priority($0) < priority($1) }) ?? .other
        var details = lines.joined(separator: "\n")
        if details.count > 3000 { details = String(details.prefix(3000)) + "…" }
        return CloudSyncProblem(kind: kind, message: message(for: kind), technicalDetails: details)
    }

    // MARK: Walking the error chain

    private static func priority(_ kind: Kind) -> Int {
        switch kind {
        case .syncOff: return 0
        case .notSignedIn: return 1
        case .restricted: return 2
        case .storageFull: return 3
        case .offline: return 4
        case .busy: return 5
        case .other: return 6
        }
    }

    private static func walk(
        _ error: NSError,
        depth: Int,
        seen: inout Set<ObjectIdentifier>,
        kinds: inout [Kind],
        lines: inout [String]
    ) {
        guard depth < 6, seen.insert(ObjectIdentifier(error)).inserted else { return }
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)\(error.localizedDescription) [\(error.domain) \(error.code)]")
        if let kind = kind(of: error) { kinds.append(kind) }

        var nested: [NSError] = []
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { nested.append(underlying) }
        if let many = error.userInfo["NSUnderlyingErrors"] as? [NSError] { nested += many }
        if let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
            nested += partial.values.prefix(5).map { $0 as NSError }
        }
        for child in nested {
            walk(child, depth: depth + 1, seen: &seen, kinds: &kinds, lines: &lines)
        }
    }

    private static func kind(of error: NSError) -> Kind? {
        switch error.domain {
        case CKError.errorDomain:
            switch CKError.Code(rawValue: error.code) {
            case .notAuthenticated, .accountTemporarilyUnavailable: return .notSignedIn
            case .managedAccountRestricted: return .restricted
            case .quotaExceeded: return .storageFull
            case .networkUnavailable, .networkFailure: return .offline
            case .serviceUnavailable, .requestRateLimited, .zoneBusy: return .busy
            default: return nil
            }
        case NSURLErrorDomain:
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed,
                 NSURLErrorInternationalRoamingOff, NSURLErrorCannotConnectToHost, NSURLErrorTimedOut:
                return .offline
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
