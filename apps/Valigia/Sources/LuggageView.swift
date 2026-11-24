import SwiftUI
import ValigiaCore

/// The multi-level list of a bag (trip or template) or of the "always" items.
/// Expand/collapse, check, statuses, drag to reorder, move, duplicate branches.
struct LuggageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let ref: ListRef

    @State private var query = ""
    @State private var tags: Set<String> = []
    @State private var onlyMissing = false
    @State private var onlyToBuy = false
    @State private var onlyWithAttachments = false
    @State private var reordering = false
    @State private var quickName = ""
    @State private var editing: ItemEditorTarget?
    @State private var moving: Item?
    @State private var leftBehindItem: Item?
    @State private var placeText = ""
    @State private var showLuggageEditor = false
    @State private var toDelete: Item?
    @FocusState private var quickFocused: Bool

    private var trip: Trip? { ref.tripID.flatMap { model.data.trip($0) } }
    private var round: CheckRound? { trip?.activeRound }
    private var luggage: Luggage? { model.data.luggage(at: ref) }
    private var items: [Item] { model.data.items(at: ref) ?? [] }
    private var isChecking: Bool { trip != nil }

    var body: some View {
        let marks = round?.markIndex ?? [:]
        let filter = ItemFilter(query: query, tags: tags, onlyMissing: onlyMissing && isChecking, onlyToBuy: onlyToBuy, onlyWithAttachments: onlyWithAttachments)
        let rows = filter.rows(for: items, marks: marks)
        let tagsInList = items.allTags
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if !tagsInList.isEmpty || isChecking || items.contains(where: { !$0.allAttachments.isEmpty }) {
                    filterBar(tagsInList)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            Section {
                if rows.isEmpty {
                    Group {
                        if filter.isActive {
                            EmptyStateView(icon: onlyMissing ? "checkmark.seal.fill" : "magnifyingglass",
                                           title: onlyMissing ? "Non manca niente" : "Nessun risultato",
                                           message: onlyMissing ? "Tutto quello che è in lista è pronto." : "Prova un'altra parola o togli i filtri.")
                        } else {
                            EmptyStateView(icon: "list.bullet.indent", title: "Lista vuota",
                                           message: "Scrivi qui sotto per aggiungere una voce. Tieni premuto una voce per aggiungere sotto-voci, spostarla o duplicarla.")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(rows) { row in
                    ItemRowView(row: row, state: isChecking ? row.item.checkState(marks: marks) : nil,
                                place: marks[row.id]?.place ?? "",
                                isFiltering: filter.isActive,
                                onToggleExpand: { toggleExpand(row.item) },
                                onCheck: { check(row.item) },
                                onOpen: { editing = .edit(row.item) })
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if isChecking {
                                Button { setStatus(.notFound, row.item) } label: { Label("Non trovata", systemImage: "questionmark") }
                                    .tint(m3.warning)
                                Button { placeText = marks[row.id]?.place ?? ""; leftBehindItem = row.item } label: { Label("Lasciata", systemImage: "house.fill") }
                                    .tint(m3.tertiary)
                            } else {
                                Button { editing = .new(parentID: row.id) } label: { Label("Sotto-voce", systemImage: "plus") }
                                    .tint(m3.primary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { delete(row.item) } label: { Label("Elimina", systemImage: "trash") }
                            Button { duplicate(row.item) } label: { Label("Duplica", systemImage: "plus.square.on.square") }
                                .tint(m3.outline)
                        }
                        .contextMenu { itemMenu(row, marks: marks) }
                }
                .onMove(perform: filter.isActive ? nil : moveHandler(rows))
            }
            Color.clear.frame(height: 70)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .environment(\.editMode, .constant(reordering ? .active : .inactive))
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Cerca nella lista")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { quickAddBar }
        .seedTheme(model.data.settings.tintWithLuggageColor ? luggage?.colorHex : nil)
        .sheet(item: $editing) { target in
            ItemEditorView(ref: ref, target: target)
        }
        .sheet(item: $moving) { item in
            MoveItemSheet(source: ref, item: item)
        }
        .sheet(isPresented: $showLuggageEditor) {
            if let luggage {
                LuggageEditorView(initial: luggage, title: "Contenitore") { updated in
                    model.editLuggage(ref) { bag in
                        let items = bag.items
                        bag = updated
                        bag.items = items
                    }
                }
            }
        }
        .alert("Dove l'hai lasciata?", isPresented: Binding(get: { leftBehindItem != nil }, set: { if !$0 { leftBehindItem = nil } })) {
            TextField("es. a casa, hotel, auto", text: $placeText)
            Button("Annulla", role: .cancel) { leftBehindItem = nil }
            Button("Segna lasciata") {
                if let i = leftBehindItem { setStatus(.leftBehind, i, place: placeText) }
                leftBehindItem = nil
            }
        } message: { Text(leftBehindItem?.name ?? "") }
        .confirmationDialog("Eliminare «\(toDelete?.name ?? "")»?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Elimina con \(ItalianFormat.plural(toDelete?.descendantCount ?? 0, "sotto-voce", "sotto-voci"))", role: .destructive) {
                if let i = toDelete { model.editItems(ref) { $0.remove(i.id) } }
                toDelete = nil
            }
        }
    }

    private var title: String {
        if case .always = ref { return "Sempre presenti" }
        return luggage?.name ?? "Lista"
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if let luggage {
            let state = LuggageFillState(luggage: luggage, round: round)
            let large = isChecking && LuggageVisualView.usesLarge(model.data.settings.visualStyle, allowsLarge: true)
            VStack(spacing: 6) {
            if large {
                LuggageVisualView(state: state, tripID: trip?.id, size: 230, allowsLarge: true)
                    .background(m3.surfaceContainer, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            HStack(alignment: .center, spacing: 16) {
                if isChecking && !large {
                    LuggageVisualView(state: state, tripID: trip?.id, size: 84)
                } else if !isChecking {
                    IconBadge(icon: luggage.kind.symbol, tones: m3.tones(luggage.colorHex), size: 72, cookie: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text([luggage.kind.label, VolumeFormat.dimensions(luggage.dimensions)].compactMap { $0 }.joined(separator: " · "))
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                    if isChecking, let round {
                        HStack(spacing: 6) {
                            Text("\(state.progress.packed)/\(state.progress.total)")
                                .font(.m3TitleLarge).monospacedDigit()
                                .foregroundStyle(m3.onSurface)
                            Text(round.name).font(.m3LabelLarge).foregroundStyle(m3.onSurfaceVariant)
                        }
                        WavyProgressBar(fraction: state.checkedFraction, color: m3.primary, track: m3.surfaceContainerHighest, height: 10)
                    } else {
                        Text(ItalianFormat.items(luggage.items.itemCount))
                            .font(.m3TitleMedium).foregroundStyle(m3.onSurface)
                    }
                    WeightGauge(grams: luggage.totalWeightGrams, maxGrams: luggage.maxWeightGrams)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { showLuggageEditor = true }
            }
            .padding(large ? 10 : 16)
            .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else if case .always = ref {
            Text("Queste voci vengono copiate in ogni nuovo viaggio (nel primo contenitore), se non ci sono già.")
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func filterBar(_ tagsInList: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if isChecking {
                    Chip(title: "Solo mancanti", icon: "circle.dashed", selected: onlyMissing) {
                        withAnimation(.snappy) { onlyMissing.toggle() }
                    }
                }
                Chip(title: "Da comprare", icon: "cart", selected: onlyToBuy) {
                    withAnimation(.snappy) { onlyToBuy.toggle() }
                }
                if items.contains(where: { !$0.allAttachments.isEmpty }) || onlyWithAttachments {
                    Chip(title: "Con allegati", icon: "paperclip", selected: onlyWithAttachments) {
                        withAnimation(.snappy) { onlyWithAttachments.toggle() }
                    }
                }
                ForEach(tagsInList, id: \.self) { tag in
                    Chip(title: tag, icon: "number", selected: tags.contains(tag)) {
                        withAnimation(.snappy) {
                            if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Toolbar and quick add

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                withAnimation { reordering.toggle() }
            } label: {
                Image(systemName: reordering ? "checkmark" : "arrow.up.arrow.down")
            }
            .accessibilityLabel(reordering ? "Fine riordino" : "Riordina")
            Menu {
                Button { editing = .new(parentID: nil) } label: { Label("Nuova voce", systemImage: "plus") }
                Button { model.editItems(ref) { $0.setCollapsed(false) } } label: { Label("Espandi tutto", systemImage: "chevron.down.2") }
                Button { model.editItems(ref) { $0.setCollapsed(true) } } label: { Label("Comprimi tutto", systemImage: "chevron.up.2") }
                if luggage != nil {
                    Button { showLuggageEditor = true } label: { Label("Modifica contenitore", systemImage: "slider.horizontal.3") }
                }
                if let luggage {
                    ShareLink(item: TextExport.luggage(luggage, round: round)) { Label("Condividi", systemImage: "square.and.arrow.up") }
                }
                if let trip, let round, let luggage {
                    Button { model.updateTrip(trip.id) { $0.resetLuggage(luggage.id, roundID: round.id) } } label: {
                        Label("Azzera spunte", systemImage: "arrow.counterclockwise")
                    }
                }
            } label: { Image(systemName: "ellipsis") }
        }
    }

    private var quickAddBar: some View {
        HStack(spacing: 10) {
            TextField("Aggiungi voce…", text: $quickName)
                .focused($quickFocused)
                .submitLabel(.done)
                .onSubmit(quickAdd)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(m3.surfaceContainerHigh, in: Capsule())
            Button {
                if quickName.trimmingCharacters(in: .whitespaces).isEmpty {
                    editing = .new(parentID: nil)
                } else {
                    quickAdd()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(m3.onPrimary)
                    .frame(width: 52, height: 52)
                    .background(m3.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: Actions

    private func quickAdd() {
        let name = quickName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        // "3 calze" or "calze x3" set the quantity.
        let parsed = QuickEntry.parse(name)
        model.editItems(ref) { $0.append(Item(name: parsed.name, quantity: parsed.quantity)) }
        quickName = ""
        quickFocused = true
    }

    private func moveHandler(_ rows: [TreeRow]) -> (IndexSet, Int) -> Void {
        { source, destination in
            guard let s = source.first else { return }
            model.editItems(ref) { $0.moveRow(from: s, to: destination, in: rows) }
        }
    }

    private func toggleExpand(_ item: Item) {
        withAnimation(.snappy) {
            model.editItems(ref) { $0.update(item.id) { $0.isCollapsed.toggle() } }
        }
    }

    private func check(_ item: Item) {
        guard let trip else { return }
        withAnimation(.snappy) {
            model.updateTrip(trip.id) { $0.togglePacked(itemID: item.id) }
        }
    }

    private func setStatus(_ status: ItemStatus?, _ item: Item, place: String = "") {
        guard let trip else { return }
        withAnimation(.snappy) {
            model.updateTrip(trip.id) { $0.setStatus(status, itemID: item.id, place: place) }
        }
    }

    private func duplicate(_ item: Item) {
        model.editItems(ref) { $0.duplicate(item.id) }
        model.show(item.isLeaf ? "Voce duplicata" : "Ramo duplicato")
    }

    private func delete(_ item: Item) {
        if item.isLeaf {
            model.editItems(ref) { $0.remove(item.id) }
        } else {
            toDelete = item
        }
    }

    @ViewBuilder
    private func itemMenu(_ row: TreeRow, marks: [UUID: ItemMark]) -> some View {
        let item = row.item
        Button { editing = .edit(item) } label: { Label("Modifica", systemImage: "pencil") }
        Button { editing = .new(parentID: item.id) } label: { Label("Aggiungi sotto-voce", systemImage: "plus") }
        if isChecking {
            Menu {
                Button { setStatus(.packed, item) } label: { Label("Preparata", systemImage: "checkmark.circle") }
                Button { setStatus(.notFound, item) } label: { Label("Non trovata", systemImage: "questionmark.circle") }
                Button { placeText = marks[item.id]?.place ?? ""; leftBehindItem = item } label: { Label("Lasciata…", systemImage: "house") }
                Button { setStatus(nil, item) } label: { Label("Azzera", systemImage: "circle") }
            } label: { Label("Stato", systemImage: "checklist") }
        }
        Divider()
        Button { duplicate(item) } label: { Label(item.isLeaf ? "Duplica" : "Duplica ramo", systemImage: "plus.square.on.square") }
        Button { moving = item } label: { Label("Sposta in…", systemImage: "arrow.turn.down.right") }
        if row.parentID != nil {
            Button { withAnimation { model.editItems(ref) { $0.outdent(item.id) } } } label: { Label("Porta fuori", systemImage: "arrow.left.to.line") }
        }
        Button { withAnimation { model.editItems(ref) { $0.indent(item.id) } } } label: { Label("Metti dentro la voce sopra", systemImage: "arrow.right.to.line") }
        Button {
            model.editItems(ref) { $0.update(item.id) { $0.owned.toggle() } }
        } label: {
            Label(item.owned ? "Segna da comprare" : "Segna come posseduta", systemImage: item.owned ? "cart.badge.plus" : "bag.fill.badge.checkmark")
        }
        Divider()
        Button(role: .destructive) { delete(item) } label: { Label("Elimina", systemImage: "trash") }
    }
}

/// Quick entry parsing: "3 calze", "calze x3", "calze ×3".
enum QuickEntry {
    static func parse(_ text: String) -> (name: String, quantity: Int) {
        let t = text.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: " ")
        if parts.count > 1, let n = Int(parts[0]), n > 0, n < 1000 {
            return (parts.dropFirst().joined(separator: " "), n)
        }
        if parts.count > 1, let last = parts.last {
            let l = last.lowercased()
            if l.hasPrefix("x") || l.hasPrefix("×"), let n = Int(l.dropFirst()), n > 0, n < 1000 {
                return (parts.dropLast().joined(separator: " "), n)
            }
        }
        return (t, 1)
    }
}
