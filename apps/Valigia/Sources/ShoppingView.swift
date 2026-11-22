import SwiftUI
import ValigiaCore

/// Every item marked as "not owned yet", in one list.
struct ShoppingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        let entries = ShoppingList.entries(in: model.data)
        let groups = Dictionary(grouping: entries, by: \.sourceName)
        let order = entries.map(\.sourceName).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        List {
            if entries.isEmpty {
                EmptyStateView(icon: "cart", title: "Niente da comprare",
                               message: "Nelle voci, togli «Ce l'ho già» (o tieni premuto › Segna da comprare): finiscono qui, da tutti i viaggi e i template.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(order, id: \.self) { source in
                Section {
                    ForEach(groups[source] ?? []) { e in
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.snappy) { model.update { ShoppingList.markBought([e], in: &$0) } }
                                if model.data.settings.haptics { Haptics.tick() }
                            } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 26, weight: .regular))
                                    .foregroundStyle(m3.outline)
                            }
                            .buttonStyle(.plain)
                            ItemGlyph(emoji: e.emoji, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.quantity > 1 ? "\(e.name) ×\(e.quantity)" : e.name)
                                    .font(.m3BodyLarge).foregroundStyle(m3.onSurface)
                                if !e.note.isEmpty {
                                    Text(e.note).font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                                }
                            }
                        }
                        .swipeActions {
                            Button { model.update { ShoppingList.markBought([e], in: &$0) } } label: {
                                Label("Comprato", systemImage: "checkmark")
                            }
                            .tint(m3.success)
                        }
                    }
                } header: {
                    ListHeader(title: source, trailing: due(groups[source]?.first?.dueDate))
                }
                .listRowBackground(m3.surfaceContainerLow)
            }
        }
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle("Da comprare")
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: ShoppingList.text(entries)) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }

    private func due(_ date: Date?) -> String? {
        guard let date else { return nil }
        return "partenza " + ItalianFormat.relative(date, now: Date())
    }
}
