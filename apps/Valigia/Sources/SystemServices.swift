import Foundation
import UIKit
import UserNotifications
import LocalAuthentication
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

/// Attachment files (photos, PDFs, other files) in Application Support/Attachments,
/// written with complete file protection (readable only while the phone is unlocked).
/// Files are never modified: copies of items share them, and a file is deleted
/// only when no item or trip references it anymore (`ValigiaData.referencedFiles`).
enum AttachmentStore {
    static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    static var folder: URL { base.appendingPathComponent("Attachments", isDirectory: true) }

    /// Version 1 kept item photos here.
    static var legacyFolder: URL { base.appendingPathComponent("Photos", isDirectory: true) }

    static func url(named name: String) -> URL { folder.appendingPathComponent(name) }

    static func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: url(named: name).path) }

    static func data(named name: String) -> Data? { try? Data(contentsOf: url(named: name)) }

    static func fileSize(_ name: String) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url(named: name).path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    @discardableResult
    static func write(_ data: Data, named name: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url(named: name), options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    /// Stores raw data as a new attachment.
    static func importData(_ data: Data, originalName: String, title: String? = nil) -> Attachment? {
        let id = UUID()
        let kind = AttachmentKind.from(fileExtension: (originalName as NSString).pathExtension)
        let stored = Attachment.storedName(forOriginal: originalName, id: id)
        guard write(data, named: stored) else { return nil }
        return Attachment(id: id, kind: kind, fileName: stored,
                          title: title ?? Attachment.defaultTitle(forOriginal: originalName, kind: kind),
                          originalName: originalName, byteSize: data.count, createdAt: Date())
    }

    /// Photo: resized (max 2000 px, enough to read a ticket) and saved as JPEG.
    static func importImage(_ image: UIImage, title: String = "Foto") -> Attachment? {
        let maxSide: CGFloat = 2000
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return importData(jpeg, originalName: "\(title).jpg", title: title)
    }

    /// Copies a file picked in Files.
    static func importFile(at url: URL) -> Attachment? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return importData(data, originalName: url.lastPathComponent)
    }

    static func delete(_ names: Set<String>) {
        for n in names { try? FileManager.default.removeItem(at: url(named: n)) }
    }

    /// Deletes files nothing points to anymore (e.g. added in an editor then cancelled).
    static func removeOrphans(keeping names: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for f in files where !names.contains(f) {
            try? FileManager.default.removeItem(at: url(named: f))
        }
    }

    /// Moves version 1 photos (Photos/) into Attachments/ with file protection.
    static func migrateLegacyPhotos() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: legacyFolder.path) else { return }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for f in files {
            let src = legacyFolder.appendingPathComponent(f)
            let dst = url(named: f)
            if fm.fileExists(atPath: dst.path) {
                try? fm.removeItem(at: src)
            } else {
                try? fm.moveItem(at: src, to: dst)
                try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: dst.path)
            }
        }
        try? fm.removeItem(at: legacyFolder)
    }
}

/// Optional Face ID / passcode before showing attachments (setting "lockDocuments").
/// Unlocked once per session; locked again when the app goes to background.
@MainActor
@Observable
final class DocumentLock {
    static let shared = DocumentLock()
    private(set) var isUnlocked = false

    var isRequired: Bool { AppModel.shared.data.settings.lockDocuments }

    /// Documents may be shown right now.
    var canShow: Bool { !isRequired || isUnlocked }

    func lock() { isUnlocked = false }

    /// Asks Face ID / passcode if needed. Returns true when documents can be shown.
    @discardableResult
    func unlock(reason: String = "Sblocca per vedere i documenti") async -> Bool {
        if canShow { return true }
        let ok = await DeviceAuth.authenticate(reason: reason)
        isUnlocked = ok
        return ok
    }
}

/// Face ID / Touch ID / passcode.
enum DeviceAuth {
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "il codice"
        }
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        // No passcode set on the phone: nothing to protect with.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
