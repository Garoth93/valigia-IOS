import SwiftUI
import ValigiaCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var cloud = CloudBackupService.shared

    var body: some View {
        @Bindable var model = model
        @Bindable var cloud = cloud
        TabView(selection: $model.tab) {
            Tab("Viaggi", systemImage: "suitcase.rolling.fill", value: AppTab.trips) {
                NavigationStack(path: $model.tripsPath) { TripsView() }
            }
            Tab("Template", systemImage: "square.stack.3d.up.fill", value: AppTab.templates) {
                NavigationStack { TemplatesView() }
            }
            Tab("Da comprare", systemImage: "cart.fill", value: AppTab.shopping) {
                NavigationStack { ShoppingView() }
            }
            .badge(ShoppingList.entries(in: model.data).count)
            Tab("Statistiche", systemImage: "chart.bar.xaxis", value: AppTab.stats) {
                NavigationStack { StatsView() }
            }
            Tab("Impostazioni", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .sheet(isPresented: $cloud.offerRestore) {
            CloudRestoreView(firstLaunch: true)
        }
        .alert("Attenzione", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { model.toast = nil }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
    }
}
