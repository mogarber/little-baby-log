import CloudKit
import Testing
import Foundation
@testable import BabyLogKit

struct CloudSyncProblemTests {
    private func kind(_ error: Error) -> CloudSyncProblem.Kind { CloudSyncProblem.classify(error).kind }

    @Test func cloudKitCodesMapToPlainLanguage() {
        #expect(kind(CKError(.notAuthenticated)) == .notSignedIn)
        #expect(kind(CKError(.accountTemporarilyUnavailable)) == .notSignedIn)
        #expect(kind(CKError(.networkUnavailable)) == .offline)
        #expect(kind(CKError(.networkFailure)) == .offline)
        #expect(kind(CKError(.quotaExceeded)) == .storageFull)
        #expect(kind(CKError(.requestRateLimited)) == .busy)
        #expect(kind(CKError(.serviceUnavailable)) == .busy)
        #expect(kind(CKError(.managedAccountRestricted)) == .restricted)
        #expect(kind(CKError(.serverRejectedRequest)) == .other)
    }

    @Test func messagesAreFriendly() {
        #expect(CloudSyncProblem.classify(CKError(.notAuthenticated)).message == "Sign in to iCloud in Settings to share.")
        #expect(CloudSyncProblem.classify(CKError(.networkUnavailable)).message.hasPrefix("You're offline"))
        #expect(CloudSyncProblem.classify(CKError(.quotaExceeded)).message.contains("iCloud storage is full"))
        #expect(CloudSyncProblem.classify(CKError(.internalError)).message == "iCloud sync isn't working right now.")
    }

    @Test func urlErrorsMeanOffline() {
        #expect(kind(URLError(.notConnectedToInternet)) == .offline)
        #expect(kind(URLError(.networkConnectionLost)) == .offline)
        #expect(kind(URLError(.badURL)) == .other)
    }

    @Test func wrappedMirroringErrorIsUnwrapped() {
        // Core Data wraps the CloudKit error: "...mirroring delegate never successfully initialized due to error...".
        let inner = CKError(.notAuthenticated)
        let wrapped = NSError(
            domain: NSCocoaErrorDomain, code: 134400,
            userInfo: [
                NSLocalizedDescriptionKey: "Request was aborted because the mirroring delegate never successfully initialized due to error",
                NSUnderlyingErrorKey: inner,
            ]
        )
        let problem = CloudSyncProblem.classify(wrapped)
        #expect(problem.kind == .notSignedIn)
        #expect(problem.technicalDetails.contains("mirroring delegate"))
        #expect(problem.technicalDetails.contains("CKErrorDomain"))
        #expect(!problem.message.contains("mirroring"))
    }

    @Test func partialFailureLooksAtItsItems() {
        let partial = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: ["a": CKError(.quotaExceeded)],
        ])
        #expect(kind(partial) == .storageFull)
    }

    @Test func mostActionableCauseWins() {
        let multi = NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [
            "NSUnderlyingErrors": [CKError(.requestRateLimited), CKError(.notAuthenticated)] as [NSError],
        ])
        #expect(kind(multi) == .notSignedIn)
    }

    @Test func productionSchemaErrorStaysGenericWithDetails() {
        let schema = NSError(
            domain: NSCocoaErrorDomain, code: 134400,
            userInfo: [NSLocalizedDescriptionKey: "Cannot create new type CD_Baby in production schema"]
        )
        let problem = CloudSyncProblem.classify(schema)
        #expect(problem.kind == .other)
        #expect(problem.message == "iCloud sync isn't working right now.")
        #expect(problem.technicalDetails.contains("Cannot create new type CD_Baby in production schema"))
    }

    @Test func syncDisabledSharingError() {
        #expect(kind(SharingError.cloudSyncDisabled) == .syncOff)
        #expect(CloudSyncProblem.classify(SharingError.cloudSyncDisabled).message == "iCloud sync is turned off in this build.")
    }

    @Test func detailsAreBounded() {
        let long = NSError(domain: "X", code: 1, userInfo: [NSLocalizedDescriptionKey: String(repeating: "a", count: 10_000)])
        #expect(CloudSyncProblem.classify(long).technicalDetails.count <= 3001)
    }
}
