import Foundation
import UIKit
import UserNotifications
import ValigiaCore

/// "The evening before departure" notifications.
///
/// Local notifications carry fixed text, so they are rescheduled with fresh
/// numbers after every change.
enum Notifier {
    static let prefix = "valigia.trip."

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func reschedule(_ plans: [ReminderPlan]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        guard !plans.isEmpty else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        for plan in plans.prefix(20) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = ["tripID": plan.tripID.uuidString]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + plan.tripID.uuidString, content: content, trigger: trigger))
        }
    }
}

/// Opens the trip when the user taps the notification.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let s = response.notification.request.content.userInfo["tripID"] as? String,
              let id = UUID(uuidString: s) else { return }
        await MainActor.run {
            AppModel.shared.openTrip(id)
        }
    }
}

/// Tactile feedback.
@MainActor
enum Haptics {
    static func tick() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

/// Keeps the app alive a few seconds while saving in the background.
@MainActor
enum BackgroundWork {
    private final class Token {
        var id: UIBackgroundTaskIdentifier = .invalid
    }

    static func run(_ name: String, _ work: @escaping @MainActor () async -> Void) {
        let token = Token()
        token.id = UIApplication.shared.beginBackgroundTask(withName: name) {
            UIApplication.shared.endBackgroundTask(token.id)
            token.id = .invalid
        }
        Task { @MainActor in
            await work()
            if token.id != .invalid {
                UIApplication.shared.endBackgroundTask(token.id)
                token.id = .invalid
            }
        }
    }
}

/// Item photos: small JPEGs in Application Support/Photos.
enum PhotoStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Photos", isDirectory: true)
    }

    static func url(named name: String) -> URL { folder.appendingPathComponent(name) }

    static func data(named name: String) -> Data? { try? Data(contentsOf: url(named: name)) }

    static func image(named name: String) -> UIImage? {
        guard let d = data(named: name) else { return nil }
        return UIImage(data: d)
    }

    static func write(_ data: Data, named name: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: url(named: name), options: .atomic)
    }

    /// Resizes (max 1200 px), compresses and saves; returns the file name.
    static func save(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1200
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.72) else { return nil }
        let name = UUID().uuidString + ".jpg"
        write(jpeg, named: name)
        return name
    }

    /// Deletes photos no item points to anymore.
    static func removeOrphans(keeping names: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for f in files where !names.contains(f) {
            try? FileManager.default.removeItem(at: url(named: f))
        }
    }
}
