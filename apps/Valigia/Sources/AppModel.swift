import SwiftUI
import WidgetKit
import ValigiaCore

struct Toast: Identifiable, Equatable {
    enum Style { case success, info, error }
    let id = UUID()
    let message: String
    let icon: String
    let style: Style
}

enum AppTab: Hashable {
    case trips, templates, shopping, stats, settings
}

/// Writes the data file off the main thread; older revisions never overwrite newer ones.
/// The previous file is kept as `.bak` so a bad write can always be recovered.
actor DataWriter {
    private let store: JSONFileStore<ValigiaData>
    private var lastRevision = -1

    init(url: URL) {
        store = JSONFileStore(url: url, compact: true)
    }

    func save(_ data: ValigiaData, revision: Int) throws {
        guard revision > lastRevision else { return }
        try store.save(data, keepBackup: true)
        lastRevision = revision
    }
}

/// Packing events for the bag visuals (phase 2 animations hook in here).
/// Visuals can observe `lastBatch` or iterate `stream()`.
@MainActor
@Observable
final class PackingEventCenter {
    struct Batch: Equatable, Identifiable {
        let id = UUID()
        let tripID: UUID
        let events: [PackingEvent]
    }

    private(set) var lastBatch: Batch?
    @ObservationIgnored private var continuations: [UUID: AsyncStream<PackingEvent>.Continuation] = [:]

    func publish(tripID: UUID, events: [PackingEvent]) {
        guard !events.isEmpty else { return }
        lastBatch = Batch(tripID: tripID, events: events)
        for c in continuations.values {
            for e in events { c.yield(e) }
        }
    }

    /// Async stream of every future event.
    func stream() -> AsyncStream<PackingEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var data = ValigiaData()
    private(set) var isLoaded = false
    var toast: Toast?
    var errorMessage: String?
    var tab: AppTab = .trips
    /// Trip to open (widget tap / notification / deep link).
    var openTripID: UUID?

    let events = PackingEventCenter()
    private let writer: DataWriter
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var derivedTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    /// Files no longer referenced: deleted after the next successful save.
    @ObservationIgnored private var releasedFiles = Set<String>()

    static var dataURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("valigia-data.json")
    }

    private init() {
        writer = DataWriter(url: Self.dataURL)
        Task { await load() }
    }

    // MARK: Loading and saving

    private func load() async {
        let url = Self.dataURL
        let result = await Task.detached(priority: .userInitiated) { () -> (ValigiaData?, Bool) in
            let store = JSONFileStore<ValigiaData>(url: url)
            do {
                return (try store.load(), false)
            } catch {
                // Main file unreadable: keep it aside, fall back to the previous copy.
                let stamp = Int(Date().timeIntervalSince1970)
                let aside = url.deletingLastPathComponent().appendingPathComponent("valigia-data-illeggibile-\(stamp).json")
                try? FileManager.default.moveItem(at: url, to: aside)
                return ((try? store.loadBackup()) ?? nil, true)
            }
        }.value
        var loaded = result.0 ?? ValigiaData()
        if result.1 {
            errorMessage = result.0 == nil
                ? "Il file dei dati non era leggibile ed è stato messo da parte. Puoi ripristinare un backup dalle Impostazioni."
                : "Il file dei dati non era leggibile: è stata ripristinata la copia precedente."
        }
        let fresh = !loaded.samplesInstalled
        loaded.installSamplesIfNeeded()
        data = loaded
        isLoaded = true
        if fresh { saveNow() }
        refreshDerived()
        let referenced = data.referencedFiles
        Task.detached(priority: .background) {
            AttachmentStore.migrateLegacyPhotos()
            AttachmentStore.removeOrphans(keeping: referenced)
        }
    }

    /// Saves after a short pause (many quick edits → one write).
    private func scheduleSave() {
        revision += 1
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.writeNow()
        }
    }

    /// Saves immediately (used when the app goes to background).
    func saveNow() {
        revision += 1
        saveTask?.cancel()
        saveTask = nil
        BackgroundWork.run("valigia-save") { [weak self] in
            await self?.writeNow()
        }
    }

    private func writeNow() async {
        let snapshot = data
        let rev = revision
        do {
            try await writer.save(snapshot, revision: rev)
            // Only now (data saved) the unused files can go; still re-checked against current data.
            let unused = releasedFiles.subtracting(data.referencedFiles)
            releasedFiles = []
            if !unused.isEmpty {
                Task.detached(priority: .utility) { AttachmentStore.delete(unused) }
            }
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }

    // MARK: Derived state (widget, reminders)

    private func refreshDerived() {
        derivedTask?.cancel()
        derivedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            let snap = WidgetSnapshot(data: self.data, now: Date())
            if SharedStore.saveSnapshot(snap) {
                WidgetCenter.shared.reloadAllTimelines()
            }
            await Notifier.reschedule(ReminderPlanner.plans(for: self.data, now: Date()))
        }
    }

    // MARK: Mutations

    /// Any change to the data: saved and propagated.
    func update(_ change: (inout ValigiaData) -> Void) {
        var copy = data
        change(&copy)
        guard copy != data else { return }
        let before = data
        data = copy
        releasedFiles.formUnion(ValigiaData.releasedFiles(before: before, after: copy))
        publishEvents(before: before, after: copy)
        scheduleSave()
        refreshDerived()
    }

    func updateTrip(_ id: UUID, _ change: (inout Trip) -> Void) {
        update { $0.editTrip(id, change) }
    }

    func updateSettings(_ change: (inout ValigiaSettings) -> Void) {
        update { change(&$0.settings) }
    }

    func editItems(_ ref: ListRef, _ change: (inout [Item]) -> Void) {
        update { $0.editItems(at: ref, change) }
    }

    func editLuggage(_ ref: ListRef, _ change: (inout Luggage) -> Void) {
        update { $0.editLuggage(at: ref, change) }
    }

    /// Events for the visuals: diff of every trip whose ticks changed.
    private func publishEvents(before: ValigiaData, after: ValigiaData) {
        for trip in after.trips {
            guard let old = before.trip(trip.id), old.rounds != trip.rounds || old.luggage.map(\.id) != trip.luggage.map(\.id) else { continue }
            let events = PackingEvents.diff(before: old, after: trip, roundID: trip.activeRound?.id)
            events.forEach(handleHaptic)
            self.events.publish(tripID: trip.id, events: events)
        }
    }

    private func handleHaptic(_ e: PackingEvent) {
        guard data.settings.haptics else { return }
        switch e {
        case .itemChecked: Haptics.tick()
        case .itemUnchecked: Haptics.light()
        case .itemFlagged: Haptics.warning()
        case .luggageClosed, .luggageEmptied: Haptics.heavy()
        case .roundCompleted, .returnRoundEmptied: Haptics.success()
        }
    }

    // MARK: Convenience

    var allTags: [String] {
        var items: [Item] = data.alwaysItems
        for t in data.trips { for b in t.luggage { items += b.items } }
        for t in data.templates { items += t.luggage.items }
        return items.allTags
    }

    func show(_ message: String, icon: String = "checkmark.circle.fill", style: Toast.Style = .success) {
        toast = Toast(message: message, icon: icon, style: style)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func handle(url: URL) {
        guard url.scheme == "valigia" else { return }
        if url.host == "trip", let id = UUID(uuidString: url.lastPathComponent) {
            tab = .trips
            openTripID = id
        } else {
            tab = .trips
        }
    }

    // MARK: Backup

    func makeBackup() -> Data? {
        var photos: [String: Data] = [:]
        for name in data.referencedFiles {
            if let d = AttachmentStore.data(named: name) { photos[name] = d }
        }
        return try? BackupFile(data: data, photos: photos).encoded()
    }

    func restore(from raw: Data) {
        do {
            let backup = try BackupFile.decode(raw)
            for (name, d) in backup.photoData { AttachmentStore.write(d, named: name) }
            var restored = backup.data
            restored.samplesInstalled = true
            data = restored
            saveNow()
            refreshDerived()
            show("Backup ripristinato: \(ItalianFormat.plural(restored.trips.count, "viaggio", "viaggi")), \(ItalianFormat.plural(restored.templates.count, "template", "template"))")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func reinstallSamples() {
        update { d in
            d.templates += SampleContent.templates(now: Date())
        }
        show("Template di esempio aggiunti")
    }
}
