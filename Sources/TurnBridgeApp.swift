import SwiftUI
import UserNotifications

/// Foreground notifications are suppressed unless a delegate opts in. Without this the
/// test alert never reaches the lock screen (and therefore never reaches the watch).
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct TurnBridgeApp: App {
    @StateObject private var engine = NavigationEngine()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
        }
    }
}
