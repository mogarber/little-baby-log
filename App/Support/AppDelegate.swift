import UIKit
import CloudKit
import UserNotifications
import os
import BabyLogKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The delegate must be in place before launch finishes, or a tap that launched the app is lost.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        ReminderScheduler.shared.registerCategories()
        return true
    }

    // MARK: Notifications

    /// A reminder arriving while the app is open still shows as a banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// A tap on the notification opens Today; the buttons act without opening the UI.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let action: ReminderResponse.Action
        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier: action = .open
        case ReminderCategory.startLeft: action = .startLeft
        case ReminderCategory.startRight: action = .startRight
        case ReminderCategory.snooze: action = .snooze
        default: action = .other
        }
        let reminder = ReminderResponse(
            action: action,
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier,
            userInfo: ReminderScheduler.stringInfo(content.userInfo)
        )
        await ReminderResponder.handle(reminder)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    private static let log = Logger(subsystem: "app.littlebabylog", category: "sharing")

    /// Cold launch from a share invitation link.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    /// Invitation opened while the app is running.
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        accept(cloudKitShareMetadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task {
            do {
                try await PersistenceController.shared.acceptShareInvitations(from: [metadata])
            } catch {
                Self.log.error("Could not accept share: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
