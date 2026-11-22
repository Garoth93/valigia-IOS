import SwiftUI
import ValigiaCore

/// Choose where to move (or copy) an item: any bag of the same trip, a template, the "always" list,
/// at the top level or inside another item.
struct MoveItemSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let source: ListRef
    let item: Item
    @State private var destination: ListRef?
    @State private var copy = false

    struct Destination: Identifiable {
        let ref: ListRef
        let name: String
        let symbol: String
        var id: ListRef { ref }
    }

    private var lists: [Destination] {
        var out: [Destination] = []
        if let tid = source.tripID, let trip = model.data.trip(tid) {
            for b in trip.luggage { out.append(Destination(ref: .trip(tripID: tid, luggageID: b.id), name: b.name, symbol: b.kind.symbol)) }
        }
        for t in model.data.templates { out.append(Destination(ref: .template(t.id), name: "Template: \(t.name)", symbol: t.luggage.kind.symbol)) }
        out.append(Destination(ref: .always, name: "Sempre presenti", symbol: "pin.fill"))
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Azione", selection: $copy) {
                        Text("Sposta").tag(false)
                        Text("Copia").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(copy ? "La copia è indipendente: l'originale resta dov'è." : "Le spunte restano se sposti dentro lo stesso viaggio.")
                }
                .listRowBackground(Color.clear)

                Section {
                    ForEach(lists) { entry in
                        Button { destination = entry.ref } label: {
                            HStack {
                                Label(entry.name, systemImage: entry.symbol).foregroundStyle(m3.onSurface)
                                Spacer()
                                if destination == entry.ref { Image(systemName: "checkmark").foregroundStyle(m3.primary) }
                            }
                        }
                    }
                } header: { ListHeader(title: "Lista") }
                .listRowBackground(m3.surfaceContainerLow)

                if let destination, !copy {
                    Section {
                        Button { perform(destination, parent: nil) } label: {
                            Label("In cima alla lista (primo livello)", systemImage: "list.bullet").foregroundStyle(m3.primary)
                        }
                        let targets = (model.data.items(at: destination) ?? []).moveTargets(excluding: item.id)
                        ForEach(targets) { row in
                            Button { perform(destination, parent: row.id) } label: {
                                HStack(spacing: 8) {
                                    Color.clear.frame(width: CGFloat(row.depth) * 16, height: 1)
                                    ItemGlyph(emoji: row.item.emoji, size: 24)
                                    Text(row.item.name).foregroundStyle(m3.onSurface)
                                    Spacer()
                                    Image(systemName: "arrow.turn.down.left").foregroundStyle(m3.onSurfaceVariant)
                                }
                            }
                        }
                    } header: { ListHeader(title: "Dentro a…") }
                    .listRowBackground(m3.surfaceContainerLow)
                } else if let destination, copy {
                    Section {
                        Button { perform(destination, parent: nil) } label: {
                            Label("Copia qui", systemImage: "plus.square.on.square").foregroundStyle(m3.primary)
                        }
                    }
                    .listRowBackground(m3.surfaceContainerLow)
                }
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            .onAppear { if destination == nil { destination = source } }
        }
    }

    private func perform(_ dest: ListRef, parent: UUID?) {
        if copy {
            model.update { _ = $0.copyItem(item.id, from: source, to: dest) }
            model.show("Copiata")
        } else {
            var ok = false
            model.update { ok = $0.moveItem(item.id, from: source, to: dest, parentID: parent) }
            if ok { model.show("Spostata") }
        }
        dismiss()
    }
}

/// New check round: name, packing or unpacking.
struct NewRoundSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var name = ""
    @State private var direction: PackDirection = .pack

    private let presets: [String: PackDirection] = [
        "Cambio albergo": .pack, "Spostamento": .pack, "Rientro": .pack, "Disfare a casa": .unpack
    ]
    private let presetOrder = ["Cambio albergo", "Spostamento", "Rientro", "Disfare a casa"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome del giro", text: $name).font(.m3TitleMedium)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(presetOrder, id: \.self) { p in
                                Chip(title: p, selected: name == p) {
                                    name = p
                                    direction = presets[p] ?? .pack
                                }
                            }
                        }
                    }
                }
                .listRowBackground(m3.surfaceContainerLow)
                Section {
                    Picker("Direzione", selection: $direction) {
                        Text("Riempi").tag(PackDirection.pack)
                        Text("Svuota").tag(PackDirection.unpack)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(direction == .pack
                         ? "Spunti quello che metti dentro: la valigia si riempie."
                         : "Spunti quello che tiri fuori a casa: la valigia si svuota e vedi se hai riportato tutto.")
                }
                .listRowBackground(m3.surfaceContainerLow)
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle("Nuovo giro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        model.updateTrip(tripID) { $0.addRound(name: name, kind: .custom, direction: direction) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

/// End of a round: what's missing, not found, left behind.
struct RoundSummaryView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case missing = "Mancanti", notFound = "Non trovate", left = "Lasciate"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var filter: Filter = .missing

    var body: some View {
        NavigationStack {
            if let trip = model.data.trip(tripID), let round = trip.activeRound {
                let summary = trip.summary(round: round.id)
                let entries: [RoundEntry] = {
                    switch filter {
                    case .missing: return summary.missing
                    case .notFound: return summary.notFound
                    case .left: return summary.leftBehind
                    }
                }()
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                ZStack {
                                    CookieShape(lobes: 10, depth: 0.06)
                                        .fill(summary.missing.isEmpty ? m3.successContainer : m3.primaryContainer)
                                    Image(systemName: summary.missing.isEmpty ? "checkmark" : round.kind.symbol)
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(summary.missing.isEmpty ? m3.onSuccessContainer : m3.onPrimaryContainer)
                                }
                                .frame(width: 72, height: 72)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.missing.isEmpty ? (round.direction == .unpack ? "Tutto riportato!" : "Tutto pronto!") : "Mancano \(ItalianFormat.items(summary.missing.count))")
                                        .font(.m3HeadlineSmall)
                                        .foregroundStyle(m3.onSurface)
                                    Text("Giro «\(round.name)» · \(summary.progress.packed)/\(summary.progress.total)")
                                        .font(.m3BodyMedium)
                                        .foregroundStyle(m3.onSurfaceVariant)
                                }
                            }
                            WavyProgressBar(fraction: summary.progress.fraction, color: m3.primary, track: m3.surfaceContainerHighest, height: 12)
                        }
                        .padding(.vertical, 6)
                        Picker("Filtro", selection: $filter) {
                            ForEach(Filter.allCases) { f in
                                Text(label(f, summary)).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    Section {
                        if entries.isEmpty {
                            Text(filter == .missing ? "Niente da segnalare." : "Nessuna voce.")
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        ForEach(entries) { e in
                            HStack(spacing: 12) {
                                Button {
                                    model.updateTrip(tripID) { $0.togglePacked(itemID: e.itemID) }
                                } label: {
                                    CheckControl(state: trip.find(e.itemID)?.checkState(marks: round.markIndex) ?? .none, size: 28)
                                }
                                .buttonStyle(.plain)
                                ItemGlyph(emoji: e.emoji, size: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.quantity > 1 ? "\(e.name) ×\(e.quantity)" : e.name).font(.m3BodyLarge).foregroundStyle(m3.onSurface)
                                    Text(e.place.isEmpty ? e.location : "\(e.location) · lasciata: \(e.place)")
                                        .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                                }
                            }
                        }
                    }
                    .listRowBackground(m3.surfaceContainerLow)
                }
                .scrollContentBackground(.hidden)
                .background(m3.surface)
                .navigationTitle("Fine giro")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: TextExport.trip(trip, roundID: round.id, options: .init(onlyMissing: true))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    PillButton(title: round.isCompleted ? "Riapri il giro" : "Chiudi il giro", icon: round.isCompleted ? "lock.open" : "checkmark.seal.fill", tones: m3.primaryTones, height: 56) {
                        model.updateTrip(tripID) { t in
                            if round.isCompleted { t.reopenRound(round.id) } else { t.completeRound(round.id) }
                        }
                        if !round.isCompleted { dismiss() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            } else {
                EmptyStateView(icon: "flag.checkered", title: "Nessun giro", message: "")
            }
        }
    }

    private func label(_ f: Filter, _ s: RoundSummary) -> String {
        switch f {
        case .missing: return "Mancanti \(s.missing.count)"
        case .notFound: return "Non trovate \(s.notFound.count)"
        case .left: return "Lasciate \(s.leftBehind.count)"
        }
    }
}
