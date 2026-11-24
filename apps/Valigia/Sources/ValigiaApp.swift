import SwiftUI
import UserNotifications
import ValigiaCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationDelegate = NotificationDelegate()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        MainActor.assumeIsolated {
            _ = AppModel.shared
        }
        return true
    }
}

@main
struct ValigiaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
                .onOpenURL { model.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.saveNow()
                DocumentLock.shared.lock()
            }
        }
    }
}

/// Builds the Material palette (from the chosen seed) for light/dark.
private struct ThemedRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme {
        switch model.data.settings.appearance {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        let theme = M3Theme(seed: model.data.settings.seedHex, dark: scheme == .dark)
        RootView()
            .environment(\.m3, theme)
            .tint(theme.primary)
            .preferredColorScheme(model.data.settings.appearance == .system ? nil : scheme)
    }
}

/// Re-themes a subtree with another seed (a bag's own color).
struct SeedTheme: ViewModifier {
    @Environment(\.m3) private var m3
    let seed: String?

    func body(content: Content) -> some View {
        if let seed {
            let theme = M3Theme(seed: seed, dark: m3.dark)
            content.environment(\.m3, theme).tint(theme.primary)
        } else {
            content
        }
    }
}

extension View {
    func seedTheme(_ seed: String?) -> some View { modifier(SeedTheme(seed: seed)) }
}
