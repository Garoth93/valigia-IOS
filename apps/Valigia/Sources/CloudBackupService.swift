import Foundation
import SwiftUI
import BackgroundTasks
import ValigiaCore

/// Automatic backups in iCloud Drive, in the shared container
/// `iCloud.com.garoth93.backup` › Documents › Valigia (visible in the Files app
/// as iCloud Drive › Backup › Valigia). One .zip per day plus "latest", written
/// when the data change, when the app goes to background and from a background
/// refresh task. Attachments only if turned on in Settings (default off).
/// Restore from Settings, or guided at first launch when the app is empty.
@MainActor
@Observable
final class CloudBackupService {
    static let shared = CloudBackupService()

    /// nil = not checked yet; false = iCloud off / not signed in / no entitlement (Sideloadly).
    private(set) var available: Bool?
    private(set) var isWorking = false
    private(set) var lastBackupAt: Date? = UserDefaults.standard.object(forKey: Keys.lastAt) as? Date
    private(set) var lastError: String?
    private(set) var entries: [CloudBackupPlan.Entry] = []
    /// Set at first launch when an empty app finds backups in iCloud.
    var offerRestore = false

    @ObservationIgnored private var scheduled: Task<Void, Never>?

    private enum Keys {
        static let fingerprint = "cloudBackup.fingerprint"
        static let lastAt = "cloudBackup.lastAt"
        static let restoreOffered = "cloudBackup.restoreOffered"
    }

    static let refreshTaskID = "com.garoth93.valigia.backup"

    private var model: AppModel { AppModel.shared }

    // MARK: Folder

    /// Resolving the ubiquity container can block: always off the main thread.
    nonisolated static func folderURL() async -> URL? {
        await Task.detached(priority: .utility) { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: CloudBackupPlan.containerID) else { return nil }
            let folder = container.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(CloudBackupPlan.folderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }.value
    }

    // MARK: Backup

    /// After a change: back up a few seconds later (many edits → one write).
    func schedule() {
        guard model.data.settings.cloudBackup else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await self?.backup(force: false)
        }
    }

    /// Writes the backup if the content changed since the last one (or `force`).
    /// An empty app never overwrites existing backups.
    @discardableResult
    func backup(force: Bool) async -> Bool {
        let settings = model.data.settings
        guard model.isLoaded, force || settings.cloudBackup, !model.data.isEffectivelyEmpty else { return false }
        let snapshot = model.data
        let withFiles = settings.cloudIncludeAttachments
        let fp = CloudBackupPlan.fingerprint(snapshot, includeAttachments: withFiles)
        if !force, fp == UserDefaults.standard.string(forKey: Keys.fingerprint) { return false }
        isWorking = true
        defer { isWorking = false }
        guard let folder = await Self.folderURL() else {
            available = false
            if force { lastError = "iCloud Drive non disponibile: controlla di aver fatto l'accesso a iCloud e che iCloud Drive sia attivo per Valigia." }
            return false
        }
        available = true
        let now = Date()
        let result = await Task.detached(priority: .utility) { () -> String? in
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("icloud-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: temp) }
            do {
                try BackupArchive.write(snapshot, includeAttachments: withFiles, to: temp, date: now) { AttachmentStore.url(named: $0) }
                try Self.coordinatedCopy(temp, to: folder.appendingPathComponent(CloudBackupPlan.dailyName(for: now)))
                try Self.coordinatedCopy(temp, to: folder.appendingPathComponent(CloudBackupPlan.latestName))
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                for name in CloudBackupPlan.namesToPrune(names) {
                    Self.coordinatedDelete(folder.appendingPathComponent(name))
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let result {
            lastError = "Backup su iCloud non riuscito: \(result)"
            return false
        }
        lastError = nil
        lastBackupAt = now
        UserDefaults.standard.set(now, forKey: Keys.lastAt)
        UserDefaults.standard.set(fp, forKey: Keys.fingerprint)
        return true
    }

    /// Settings changed what goes in the backup: next backup must be written.
    func invalidate() {
        UserDefaults.standard.removeObject(forKey: Keys.fingerprint)
        schedule()
    }

    nonisolated private static func coordinatedCopy(_ source: URL, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            do {
                let data = try Data(contentsOf: source)
                try data.write(to: target, options: .atomic)
            } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
    }

    nonisolated private static func coordinatedDelete(_ url: URL) {
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &err) { target in
            try? FileManager.default.removeItem(at: target)
        }
    }

    // MARK: Restore

    /// Backups in the iCloud folder, newest first.
    func refreshEntries() async {
        guard let folder = await Self.folderURL() else {
            available = false
            entries = []
            return
        }
        available = true
        let names = await Task.detached(priority: .userInitiated) {
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        }.value
        entries = CloudBackupPlan.entries(fromFileNames: names)
    }

    /// Downloads (if needed) a backup into a local temporary file.
    func download(_ entry: CloudBackupPlan.Entry) async throws -> URL {
        guard let folder = await Self.folderURL() else { throw CocoaError(.fileReadNoPermission) }
        let url = folder.appendingPathComponent(entry.name)
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(entry.name)")
        return try await Task.detached(priority: .userInitiated) { () async throws -> URL in
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            // The coordinated read waits for the iCloud download.
            for _ in 0..<120 {
                var coordError: NSError?
                var ok = false
                NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { target in
                    if let d = try? Data(contentsOf: target), !d.isEmpty {
                        ok = (try? d.write(to: local, options: .atomic)) != nil
                    }
                }
                if ok { return local }
                try await Task.sleep(for: .milliseconds(500))
            }
            throw CocoaError(.fileReadUnknown)
        }.value
    }

    func restore(_ entry: CloudBackupPlan.Entry) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let local = try await download(entry)
            defer { try? FileManager.default.removeItem(at: local) }
            model.restore(from: local)
            lastError = nil
            return model.errorMessage == nil
        } catch {
            lastError = "Non riesco a scaricare il backup da iCloud: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: First launch

    /// Empty app + backups in iCloud → guided restore (asked once).
    func offerRestoreIfNeeded() async {
        guard model.data.isEffectivelyEmpty, !UserDefaults.standard.bool(forKey: Keys.restoreOffered) else { return }
        await refreshEntries()
        guard !entries.isEmpty, model.data.isEffectivelyEmpty else { return }
        UserDefaults.standard.set(true, forKey: Keys.restoreOffered)
        offerRestore = true
    }

    // MARK: Background refresh

    /// Called once in didFinishLaunching.
    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            let work = Task { @MainActor in
                await CloudBackupService.shared.backup(force: false)
                CloudBackupService.scheduleBackgroundRefresh()
            }
            task.expirationHandler = { work.cancel() }
            Task {
                await work.value
                task.setTaskCompleted(success: true)
            }
        }
    }

    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Restore from iCloud: list of backups with a preview. Also shown at first
/// launch when the app is empty and iCloud has backups.
struct CloudRestoreView: View {
    let firstLaunch: Bool
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @State private var cloud = CloudBackupService.shared
    @State private var choice: CloudBackupPlan.Entry?
    @State private var preview: (file: BackupFile, files: Int)?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                if firstLaunch {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            IconBadge(icon: "icloud.and.arrow.down.fill", tones: m3.primaryTones, size: 64, cookie: true)
                            Text("Bentornato!").font(.m3HeadlineSmall).foregroundStyle(m3.onSurface)
                            Text("In iCloud Drive c'è un backup di Valigia. Vuoi ripristinare viaggi e template?")
                                .font(.m3BodyMedium).foregroundStyle(m3.onSurfaceVariant)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    if cloud.entries.isEmpty {
                        Text(cloud.available == false ? "iCloud Drive non disponibile." : "Nessun backup trovato.")
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    ForEach(cloud.entries) { entry in
                        Button {
                            choice = entry
                            Task { await loadPreview(entry) }
                        } label: {
                            HStack {
                                Image(systemName: entry.isLatest ? "clock.arrow.circlepath" : "doc.zipper")
                                    .foregroundStyle(m3.primary)
                                Text(title(entry)).foregroundStyle(m3.onSurface)
                                Spacer()
                                if choice == entry {
                                    if loading { ProgressView() } else { Image(systemName: "checkmark").foregroundStyle(m3.primary) }
                                }
                            }
                        }
                    }
                } header: {
                    ListHeader(title: "iCloud Drive › Backup › Valigia")
                } footer: {
                    Text("Il ripristino sostituisce tutti i dati attuali con quelli del backup.")
                }
                .listRowBackground(m3.surfaceContainerLow)

                if let preview, let choice {
                    Section {
                        LabeledContent("Viaggi", value: "\(preview.file.data.trips.count)")
                        LabeledContent("Template", value: "\(preview.file.data.templates.count)")
                        LabeledContent("Allegati inclusi", value: preview.files == 0 ? "No" : "\(preview.files)")
                        LabeledContent("Salvato il", value: preview.file.exportedAt.formatted(date: .abbreviated, time: .shortened))
                        Button {
                            Task {
                                if await cloud.restore(choice) { dismiss() }
                            }
                        } label: {
                            Label("Ripristina questo backup", systemImage: "arrow.counterclockwise")
                                .font(.m3TitleSmall)
                        }
                        .disabled(cloud.isWorking)
                    }
                    .listRowBackground(m3.surfaceContainerLow)
                }
                if let e = cloud.lastError {
                    Section { Text(e).foregroundStyle(m3.error) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle("Ripristina da iCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(firstLaunch ? "Inizia da zero" : "Chiudi") { dismiss() }
                }
            }
            .task {
                await cloud.refreshEntries()
                if let first = cloud.entries.first, choice == nil {
                    choice = first
                    await loadPreview(first)
                }
            }
        }
    }

    private func title(_ e: CloudBackupPlan.Entry) -> String {
        if let d = e.day { return ItalianFormat.longDay(d) + " " + String(Calendar.current.component(.year, from: d)) }
        return "Ultimo backup"
    }

    private func loadPreview(_ entry: CloudBackupPlan.Entry) async {
        loading = true
        defer { loading = false }
        guard let local = try? await cloud.download(entry) else { preview = nil; return }
        defer { try? FileManager.default.removeItem(at: local) }
        if let file = try? BackupArchive.peek(local) {
            preview = (file, BackupArchive.fileCount(local))
        } else {
            preview = nil
        }
    }
}
