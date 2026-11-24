import Foundation

/// Reads the App Group identifiers from an `embedded.mobileprovision`.
///
/// The app is signed by the user (Sideloadly / SideStore) with a free Apple
/// account; some signers rename the App Group (e.g. appending the Team ID).
/// Reading the real group from the profile keeps app and widgets in sync.
public enum ProvisioningProfile {
    /// The profile is a CMS envelope around an XML plist: extract the plist.
    public static func plist(from data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil)) as? [String: Any]
    }

    public static func appGroups(from data: Data) -> [String] {
        guard let p = plist(from: data),
              let ent = p["Entitlements"] as? [String: Any],
              let groups = ent["com.apple.security.application-groups"] as? [String] else { return [] }
        return groups
    }

    /// Picks the group to use: the configured one if present, else the one
    /// that contains its base name, else the first.
    public static func pickGroup(configured: String, available: [String]) -> String? {
        if available.contains(configured) { return configured }
        let base = configured.replacingOccurrences(of: "group.", with: "")
        if let match = available.first(where: { $0.contains(base) }) { return match }
        if let match = available.first(where: { $0.lowercased().contains("valigia") }) { return match }
        return available.first
    }
}
