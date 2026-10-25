import UIKit
import CloudKit
import CoreData
import BabyLogKit

/// Presents `UICloudSharingController` directly from the top view controller
/// (a SwiftUI representable is unreliable for this controller).
///
/// The delegate property of the controller is weak, so keep the coordinator alive
/// (e.g. in a `@State`) while the sheet is up.
@MainActor
final class CloudSharingCoordinator: NSObject, UICloudSharingControllerDelegate {
    private let persistence: PersistenceController
    private let baby: Baby
    private let onChange: () -> Void
    private var activeShare: CKShare?

    init(persistence: PersistenceController, baby: Baby, onChange: @escaping () -> Void) {
        self.persistence = persistence
        self.baby = baby
        self.onChange = onChange
        super.init()
    }

    /// Creates (or fetches) the share, then shows the system sharing sheet.
    func present() async throws {
        let (share, container) = try await persistence.share(baby)
        activeShare = share
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = self
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.modalPresentationStyle = .formSheet
        UIApplication.topViewController()?.present(controller, animated: true)
    }

    // MARK: UICloudSharingControllerDelegate

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        onChange()
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        baby.displayName
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        if let share = csc.share ?? activeShare {
            persistence.persistUpdatedShare(share)
        }
        onChange()
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        if let share = csc.share ?? activeShare, persistence.isInSharedStore(baby) {
            persistence.purgeSharedZone(of: share)
        }
        onChange()
    }
}

extension UIApplication {
    /// The frontmost presented view controller of the active window scene.
    static func topViewController() -> UIViewController? {
        let scenes = shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
