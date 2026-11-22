import SwiftUI
import ValigiaCore

/// "Quick check": every single thing to tick, with big targets and haptics.
struct QuickCheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var onlyMissing = false
    @State private var leftBehindID: UUID?
    @State private var placeText = ""

    var body: some View {
        NavigationStack {
            if let trip = model.data.trip(tripID), let round = trip.activeRound {
                let marks = round.markIndex
                let p = trip.progress(round: round.id)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(p.packed)")
                                    .font(.system(size: 56, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                Text("/ \(p.total)")
                                    .font(.m3HeadlineSmall)
                                    .foregroundStyle(m3.onSurfaceVariant)
                                Spacer()
                                Chip(title: "Solo mancanti", icon: "circle.dashed", selected: onlyMissing) {
                                    withAnimation(.snappy) { onlyMissing.toggle() }
                                }
                            }
                            WavyProgressBar(fraction: p.fraction, color: m3.primary, track: m3.surfaceContainerHighest, height: 14)
                            if p.isComplete {
                                Label(round.direction == .unpack ? "Tutto riportato a casa" : "Tutto pronto, buon viaggio!", systemImage: "checkmark.seal.fill")
                                    .font(.m3TitleMedium)
                                    .foregroundStyle(m3.onSuccessContainer)
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(m3.successContainer, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                        .padding(.bottom, 6)

                        ForEach(trip.luggage) { bag in
                            let entries = leaves(of: bag, marks: marks)
                            if !entries.isEmpty {
                                Section {
                                    ForEach(entries, id: \.item.id) { entry in
                                        QuickRow(item: entry.item, path: entry.path, mark: marks[entry.item.id]) {
                                            withAnimation(.snappy) {
                                                model.updateTrip(tripID) { $0.togglePacked(itemID: entry.item.id) }
                                            }
                                        }
                                        .contextMenu {
                                            Button { set(.notFound, entry.item.id) } label: { Label("Non trovata", systemImage: "questionmark.circle") }
                                            Button { placeText = marks[entry.item.id]?.place ?? ""; leftBehindID = entry.item.id } label: { Label("Lasciata…", systemImage: "house") }
                                            Button { set(nil, entry.item.id) } label: { Label("Azzera", systemImage: "circle") }
                                        }
                                    }
                                } header: {
                                    HStack(spacing: 8) {
                                        Image(systemName: bag.kind.symbol)
                                        Text(bag.name).font(.m3TitleMedium)
                                        Spacer()
                                        let bp = trip.progress(round: round.id, luggageID: bag.id)
                                        Text("\(bp.packed)/\(bp.total)").font(.m3LabelLarge).monospacedDigit()
                                    }
                                    .foregroundStyle(m3.tones(bag.colorHex).onContainer)
                                    .padding(.horizontal, 16)
                                    .frame(height: 44)
                                    .background(m3.tones(bag.colorHex).container, in: Capsule())
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
                .background(m3.surface)
                .navigationTitle(round.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fine") { dismiss() }.fontWeight(.semibold)
                    }
                }
                .alert("Dove l'hai lasciata?", isPresented: Binding(get: { leftBehindID != nil }, set: { if !$0 { leftBehindID = nil } })) {
                    TextField("es. a casa, hotel", text: $placeText)
                    Button("Annulla", role: .cancel) { leftBehindID = nil }
                    Button("Segna lasciata") {
                        if let id = leftBehindID { set(.leftBehind, id, place: placeText) }
                        leftBehindID = nil
                    }
                }
            } else {
                EmptyStateView(icon: "checklist", title: "Niente da controllare", message: "")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            }
        }
    }

    private struct Entry {
        let item: Item
        let path: String
    }

    private func leaves(of bag: Luggage, marks: [UUID: ItemMark]) -> [Entry] {
        var out: [Entry] = []
        func walk(_ items: [Item], path: [String]) {
            for i in items {
                if i.isLeaf {
                    if !onlyMissing || marks[i.id]?.status != .packed {
                        out.append(Entry(item: i, path: path.joined(separator: " › ")))
                    }
                } else {
                    walk(i.children, path: path + [i.name])
                }
            }
        }
        walk(bag.items, path: [])
        return out
    }

    private func set(_ status: ItemStatus?, _ id: UUID, place: String = "") {
        withAnimation(.snappy) {
            model.updateTrip(tripID) { $0.setStatus(status, itemID: id, place: place) }
        }
    }
}

private struct QuickRow: View {
    @Environment(\.m3) private var m3
    let item: Item
    let path: String
    let mark: ItemMark?
    let onTap: () -> Void

    var body: some View {
        let packed = mark?.status == .packed
        Button(action: onTap) {
            HStack(spacing: 16) {
                CheckControl(state: mark.map { .done($0.status) } ?? .none, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let e = item.emoji { Text(e).font(.system(size: 22)) }
                        Text(item.name)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(packed ? m3.onSurfaceVariant : m3.onSurface)
                            .strikethrough(packed)
                        if item.quantity > 1 {
                            Text("×\(item.quantity)").font(.m3TitleSmall).foregroundStyle(m3.primary)
                        }
                    }
                    if !path.isEmpty || !(mark?.place ?? "").isEmpty {
                        Text([path, mark?.place ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 76)
            .background(packed ? m3.surfaceContainerLow : m3.surfaceContainer, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
