import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import ValigiaCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDoc = FileURLDocument(url: nil)
    @State private var pendingRestore: URL?
    @State private var includeAttachments = true
    @State private var exporting = false
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
                Toggle(isOn: $includeAttachments) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Includi gli allegati")
                        Text("Dimensione prevista: \(ByteFormat.string(model.estimatedBackupSize(includeAttachments: includeAttachments)))")
                            .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                Button {
                    exporting = true
                    Task {
                        if let url = await model.makeBackup(includeAttachments: includeAttachments) {
                            exportDoc = FileURLDocument(url: url)
                            showExporter = true
                        }
                        exporting = false
                    }
                } label: {
                    HStack {
                        Label("Esporta backup (.zip)", systemImage: "square.and.arrow.up")
                        if exporting { Spacer(); ProgressView() }
                    }
                }
                .disabled(exporting)
                Button { showImporter = true } label: { Label("Ripristina da backup (.zip o .json)", systemImage: "square.and.arrow.down") }
            } header: { ListHeader(title: "Backup") } footer: {
                Text("Lo zip contiene viaggi, template, spunte, impostazioni e, se vuoi, gli allegati (attenzione: possono esserci documenti d'identità). Il ripristino sostituisce tutti i dati attuali; si leggono anche i vecchi backup .json.")
            }
            .listRowBackground(m3.surfaceContainerLow)

            Section {
                Toggle(isOn: Binding(get: { s.lockDocuments }, set: { v in setDocumentLock(v) })) {
                    Label("\(DeviceAuth.biometryName) per aprire i documenti", systemImage: "lock.doc")
                }
            } header: { ListHeader(title: "Privacy") } footer: {
                Text("Chiede \(DeviceAuth.biometryName) prima di aprire o mostrare in anteprima gli allegati. Resta sbloccato finché l'app non va in background. I file sono comunque cifrati da iOS quando il telefono è bloccato.")
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
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .zip, defaultFilename: exportDoc.url?.lastPathComponent ?? "valigia-backup.zip") { result in
            if case .success = result { model.show("Backup salvato") }
            if let url = exportDoc.url { try? FileManager.default.removeItem(at: url) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip, .json]) { result in
            guard case .success(let url) = result else { return }
            pendingRestore = url
        }
        .confirmationDialog("Ripristinare il backup?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
            Button("Sostituisci tutti i dati", role: .destructive) {
                if let u = pendingRestore { model.restore(from: u) }
                pendingRestore = nil
            }
        } message: { Text("I dati attuali verranno sostituiti da quelli del backup.") }
    }

    private func setDocumentLock(_ on: Bool) {
        Task {
            // Turning the protection off needs the same authentication.
            if !on, !(await DeviceAuth.authenticate(reason: "Disattiva la protezione dei documenti")) { return }
            model.updateSettings { $0.lockDocuments = on }
            if on { DocumentLock.shared.lock() }
        }
    }

    private func refreshStatus() async {
        notificationStatus = await Notifier.authorizationStatus()
    }
}

/// Exports an existing file (the backup zip) without loading it in memory.
struct FileURLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var url: URL?

    init(url: URL?) { self.url = url }

    init(configuration: ReadConfiguration) throws { url = nil }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        return try FileWrapper(url: url, options: .immediate)
    }
}
