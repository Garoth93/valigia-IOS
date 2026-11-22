import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import ValigiaCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDoc = DataFileDocument(data: Data())
    @State private var pendingRestore: Data?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        let s = model.data.settings
        Form {
            Section {
                Picker("Tema", selection: Binding(get: { s.appearance }, set: { v in model.updateSettings { $0.appearance = v } })) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Colore").font(.m3TitleSmall)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                        ForEach(Palette.seeds) { seed in
                            let selected = seed.hex.lowercased() == s.seedHex.lowercased()
                            let tones = Tones(hex: seed.hex, dark: m3.dark)
                            Button {
                                Haptics.selection()
                                model.updateSettings { $0.seedHex = seed.hex }
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        if selected {
                                            CookieShape(lobes: 8, depth: 0.08).fill(tones.accent)
                                            Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).foregroundStyle(tones.onAccent)
                                        } else {
                                            Circle().fill(tones.container)
                                            Circle().fill(tones.accent).padding(12)
                                        }
                                    }
                                    .frame(width: 48, height: 48)
                                    Text(seed.name).font(.m3LabelSmall).foregroundStyle(m3.onSurfaceVariant)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
                Toggle("Colore del contenitore nelle sue liste", isOn: Binding(get: { s.tintWithLuggageColor }, set: { v in model.updateSettings { $0.tintWithLuggageColor = v } }))
            } header: { ListHeader(title: "Aspetto") } footer: {
                Text("Tutta la tavolozza Material 3 (chiara e scura) viene generata dal colore scelto.")
            }
            .listRowBackground(m3.surfaceContainerLow)

            Section {
                Picker("Valigia", selection: Binding(get: { s.visualStyle }, set: { v in model.updateSettings { $0.visualStyle = v } })) {
                    ForEach(LuggageVisualStyle.allCases, id: \.self) { style in
                        Text(style.isAvailable ? style.label : "\(style.label) (in arrivo)").tag(style)
                            .selectionDisabled(!style.isAvailable)
                    }
                }
                Toggle("Feedback tattile", isOn: Binding(get: { s.haptics }, set: { v in model.updateSettings { $0.haptics = v } }))
            } header: { ListHeader(title: "Controllo") } footer: {
                if s.visualStyle == .threeD {
                    Text("Valigia 3D: la vedi in cima alla lista di ogni contenitore di un viaggio. Trascinala per ruotarla, tocca due volte per raddrizzarla; le voci spuntate ci volano dentro e a 100% il coperchio si chiude. Con «Riduci movimento» attivo le animazioni sono ridotte.")
                }
            }
            .listRowBackground(m3.surfaceContainerLow)

            Section {
                Toggle("Promemoria la sera prima", isOn: Binding(get: { s.reminderEnabled }, set: { v in
                    model.updateSettings { $0.reminderEnabled = v }
                    if v { Task { await Notifier.requestAuthorization(); await refreshStatus() } }
                }))
                if s.reminderEnabled {
                    DatePicker("Orario", selection: Binding(get: {
                        Calendar.current.date(bySettingHour: s.reminderHour, minute: s.reminderMinute, second: 0, of: Date()) ?? Date()
                    }, set: { d in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                        model.updateSettings { $0.reminderHour = c.hour ?? 20; $0.reminderMinute = c.minute ?? 0 }
                    }), displayedComponents: .hourAndMinute)
                }
                if notificationStatus == .denied {
                    Label("Notifiche disattivate in Impostazioni di iOS", systemImage: "bell.slash")
                        .font(.m3BodySmall).foregroundStyle(m3.error)
                }
            } header: { ListHeader(title: "Notifiche") } footer: {
                Text("La sera prima della partenza ti dice quante voci mancano e quali.")
            }
            .listRowBackground(m3.surfaceContainerLow)

            Section {
                Button {
                    if let d = model.makeBackup() {
                        exportDoc = DataFileDocument(data: d)
                        showExporter = true
                    }
                } label: { Label("Esporta backup JSON", systemImage: "square.and.arrow.up") }
                Button { showImporter = true } label: { Label("Ripristina da backup", systemImage: "square.and.arrow.down") }
            } header: { ListHeader(title: "Backup") } footer: {
                Text("Il backup contiene viaggi, template, spunte, impostazioni e foto. Il ripristino sostituisce tutti i dati attuali.")
            }
            .listRowBackground(m3.surfaceContainerLow)

            Section {
                Button { model.reinstallSamples() } label: { Label("Aggiungi di nuovo i template di esempio", systemImage: "square.stack.3d.up.badge.automatic") }
            }
            .listRowBackground(m3.surfaceContainerLow)

            Section {
                LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Dati condivisi con i widget", value: SharedStore.isShared ? "Attivi" : "Non disponibili")
                LabeledContent("Viaggi · template", value: "\(model.data.trips.count) · \(model.data.templates.count)")
            } header: { ListHeader(title: "Informazioni") } footer: {
                Text("Tutto resta sul tuo iPhone: nessun server, nessun account.")
            }
            .listRowBackground(m3.surfaceContainerLow)
        }
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle("Impostazioni")
        .task { await refreshStatus() }
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json, defaultFilename: backupName) { result in
            if case .success = result { model.show("Backup salvato") }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url) {
                pendingRestore = d
            } else {
                model.errorMessage = "Non riesco a leggere il file."
            }
        }
        .confirmationDialog("Ripristinare il backup?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
            Button("Sostituisci tutti i dati", role: .destructive) {
                if let d = pendingRestore { model.restore(from: d) }
                pendingRestore = nil
            }
        } message: { Text("I dati attuali verranno sostituiti da quelli del backup.") }
    }

    private var backupName: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "valigia-backup-%04d-%02d-%02d.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private func refreshStatus() async {
        notificationStatus = await Notifier.authorizationStatus()
    }
}
