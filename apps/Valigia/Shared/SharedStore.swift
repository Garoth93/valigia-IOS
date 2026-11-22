import Foundation
import ValigiaCore

/// Small JSON shared by the app and the widgets through the App Group.
///
/// The widgets never read the whole data file: the app writes a
/// `WidgetSnapshot` after every change. The real group id is read from the
/// provisioning profile, because free-account signers (Sideloadly / SideStore)
/// may rename it.
enum SharedStore {
    static let configuredGroup = "group.com.garoth93.valigia"
    static let snapshotFileName = "widget-snapshot.json"

    /// The App Group actually available to this process, if any.
    static let groupID: String? = {
        var candidates: [String] = []
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url) {
            candidates = ProvisioningProfile.appGroups(from: data)
        }
        if let declared = Bundle.main.object(forInfoDictionaryKey: "VLAppGroup") as? String, !declared.isEmpty {
            candidates.append(declared)
        }
        candidates.append(configuredGroup)
        var seen = Set<String>()
        let ordered = candidates.filter { seen.insert($0).inserted }
        let preferred = ProvisioningProfile.pickGroup(configured: configuredGroup, available: ordered)
        for id in [preferred].compactMap({ $0 }) + ordered {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil { return id }
        }
        return nil
    }()

    static var containerURL: URL? {
        groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    static var isShared: Bool { containerURL != nil }

    static var snapshotURL: URL? { containerURL?.appendingPathComponent(snapshotFileName) }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL else { return nil }
        return try? JSONFileStore<WidgetSnapshot>(url: url).load()
    }

    /// Returns true when the file changed (so widgets need a reload).
    @discardableResult
    static func saveSnapshot(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL else { return false }
        let store = JSONFileStore<WidgetSnapshot>(url: url)
        if var old = try? store.load() {
            old.generatedAt = snapshot.generatedAt
            if old == snapshot { return false }
        }
        try? store.save(snapshot)
        return true
    }
}
