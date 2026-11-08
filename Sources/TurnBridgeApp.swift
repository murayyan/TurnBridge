import SwiftUI
import UserNotifications

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
                .onOpenURL { url in
                    engine.handleURL(url)
                }
        }
    }
}
