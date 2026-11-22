import SwiftUI
import ValigiaCore

struct TemplatesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var showNew = false
    @State private var toDelete: PackTemplate?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: ListRef.always) {
                    HStack(spacing: 14) {
                        IconBadge(icon: "pin.fill", tones: m3.tertiaryTones, size: 52, cookie: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sempre presenti").font(.m3TitleMedium).foregroundStyle(m3.onSurface)
                            Text(model.data.alwaysItems.isEmpty ? "Voci copiate in ogni nuovo viaggio" : model.data.alwaysItems.map(\.name).joined(separator: ", "))
                                .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant).lineLimit(2)
                        }
                        Spacer()
                        Text("\(model.data.alwaysItems.itemCount)")
                            .font(.m3TitleMedium).foregroundStyle(m3.onTertiaryContainer)
                    }
                    .padding(16)
                    .background(m3.tertiaryContainer.opacity(0.55), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(PressableStyle())

                SectionTitle("I tuoi template", trailing: "\(model.data.templates.count)")
                if model.data.templates.isEmpty {
                    EmptyStateView(icon: "square.stack.3d.up", title: "Nessun template",
                                   message: "Un template è un contenitore con la sua lista, pronto da copiare in un viaggio.")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(model.data.templates) { t in
                        NavigationLink(value: ListRef.template(t.id)) {
                            TemplateTile(template: t)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button {
                                model.update { _ = $0.duplicateTemplate(t.id) }
                            } label: { Label("Duplica", systemImage: "plus.square.on.square") }
                            Button {
                                model.update { $0.createTrip(TripDraft(name: t.name, templateIDs: [t.id])) }
                                model.tab = .trips
                                model.show("Viaggio creato da «\(t.name)»")
                            } label: { Label("Nuovo viaggio da qui", systemImage: "suitcase.rolling") }
                            ShareLink(item: TextExport.luggage(t.luggage, options: .init(withChecks: false))) {
                                Label("Condividi", systemImage: "square.and.arrow.up")
                            }
                            Button(role: .destructive) { toDelete = t } label: { Label("Elimina", systemImage: "trash") }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .background(m3.surface)
        .navigationTitle("Template")
        .navigationDestination(for: ListRef.self) { ref in LuggageView(ref: ref) }
        .overlay(alignment: .bottomTrailing) {
            ExtendedFAB(title: "Template", icon: "plus") { showNew = true }
                .padding(20)
        }
        .sheet(isPresented: $showNew) {
            LuggageEditorView(initial: Luggage(name: "", kind: .backpack), title: "Nuovo template") { bag in
                model.update { $0.addTemplate(bag) }
            }
        }
        .confirmationDialog("Eliminare il template «\(toDelete?.name ?? "")»?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let t = toDelete { model.update { $0.deleteTemplate(t.id) } }
                toDelete = nil
            }
        } message: { Text("I viaggi già creati da questo template non cambiano.") }
    }
}

private struct TemplateTile: View {
    @Environment(\.m3) private var m3
    let template: PackTemplate

    var body: some View {
        let bag = template.luggage
        let tones = m3.tones(bag.colorHex)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(icon: bag.kind.symbol, tones: tones, size: 46, cookie: true, filled: true)
                Spacer()
                if template.usageCount > 0 {
                    Text("\(template.usageCount)×")
                        .font(.m3LabelMedium)
                        .foregroundStyle(tones.onContainer)
                }
            }
            Text(bag.name)
                .font(.m3TitleSmall)
                .foregroundStyle(tones.onContainer)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(ItalianFormat.items(bag.items.itemCount))
                if bag.totalWeightGrams > 0 || bag.maxWeightGrams != nil {
                    Text(WeightFormat.ratio(bag.totalWeightGrams, max: bag.maxWeightGrams))
                        .foregroundStyle(bag.isOverweight ? m3.error : tones.onContainer.opacity(0.75))
                }
            }
            .font(.m3BodySmall)
            .foregroundStyle(tones.onContainer.opacity(0.75))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tones.container.opacity(0.7), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
