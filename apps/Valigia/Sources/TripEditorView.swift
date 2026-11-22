import SwiftUI
import ValigiaCore

/// New trip (with bags from templates) or edit of name / dates / destination.
struct TripEditorView: View {
    enum Mode: Equatable {
        case new
        case edit(UUID)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let mode: Mode

    @State private var name = ""
    @State private var destination = ""
    @State private var note = ""
    @State private var hasDates = true
    @State private var start = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400 * 7))
    @State private var end = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400 * 9))
    @State private var selected: [UUID] = []
    @State private var includeAlways = true
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome del viaggio", text: $name)
                        .font(.m3TitleMedium)
                    TextField("Destinazione", text: $destination)
                } header: { ListHeader(title: "Viaggio") }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    Toggle("Date", isOn: $hasDates.animation())
                    if hasDates {
                        DatePicker("Partenza", selection: $start, displayedComponents: .date)
                        DatePicker("Ritorno", selection: $end, in: start..., displayedComponents: .date)
                    }
                } header: { ListHeader(title: "Quando") } footer: {
                    if hasDates && model.data.settings.reminderEnabled {
                        Text("La sera prima della partenza ricevi una notifica con quello che manca.")
                    }
                }
                .listRowBackground(m3.surfaceContainerLow)

                if mode == .new {
                    Section {
                        if model.data.templates.isEmpty {
                            Text("Nessun template: potrai aggiungere contenitori vuoti dal viaggio.")
                                .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                        }
                        ForEach(model.data.templates) { t in
                            Button { toggle(t.id) } label: { templateRow(t) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        ListHeader(title: "Contenitori dai template", trailing: selected.isEmpty ? nil : "\(selected.count) scelti")
                    } footer: {
                        Text("Ogni contenitore è una copia indipendente: nel viaggio puoi togliere e aggiungere voci senza toccare il template.")
                    }
                    .listRowBackground(m3.surfaceContainerLow)

                    Section {
                        Toggle(isOn: $includeAlways) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Aggiungi le voci «sempre presenti»")
                                Text(model.data.alwaysItems.isEmpty ? "La lista è vuota (Template › Sempre presenti)" : model.data.alwaysItems.map(\.name).prefix(4).joined(separator: ", "))
                                    .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant).lineLimit(1)
                            }
                        }
                        .disabled(model.data.alwaysItems.isEmpty)
                    }
                    .listRowBackground(m3.surfaceContainerLow)
                }

                Section {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                } header: { ListHeader(title: "Note") }
                .listRowBackground(m3.surfaceContainerLow)
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle(mode == .new ? "Nuovo viaggio" : "Modifica viaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .new ? "Crea" : "Salva") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
            .onChange(of: start) { _, newValue in
                if end < newValue { end = newValue }
            }
        }
    }

    private func templateRow(_ t: PackTemplate) -> some View {
        let on = selected.contains(t.id)
        let tones = m3.tones(t.luggage.colorHex)
        return HStack(spacing: 12) {
            IconBadge(icon: t.luggage.kind.symbol, tones: tones, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(.m3TitleSmall).foregroundStyle(m3.onSurface)
                Text("\(ItalianFormat.items(t.luggage.items.itemCount)) · \(WeightFormat.string(t.luggage.totalWeightGrams))")
                    .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
            }
            Spacer()
            if let i = selected.firstIndex(of: t.id) {
                Text("\(i + 1)")
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onPrimary)
                    .frame(width: 26, height: 26)
                    .background(m3.primary, in: Circle())
            } else {
                Circle().strokeBorder(m3.outline, lineWidth: 2).frame(width: 26, height: 26)
            }
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ id: UUID) {
        if let i = selected.firstIndex(of: id) { selected.remove(at: i) } else { selected.append(id) }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        includeAlways = !model.data.alwaysItems.isEmpty
        if case .edit(let id) = mode, let t = model.data.trip(id) {
            name = t.name
            destination = t.destination
            note = t.note
            hasDates = t.startDate != nil
            if let s = t.startDate { start = s }
            end = t.endDate ?? t.startDate ?? end
        }
    }

    private func save() {
        let cal = Calendar.current
        let s = hasDates ? cal.startOfDay(for: start) : nil
        let e = hasDates ? cal.startOfDay(for: max(end, start)) : nil
        switch mode {
        case .new:
            var newID: UUID?
            model.update { d in
                newID = d.createTrip(TripDraft(name: name, destination: destination, startDate: s, endDate: e, note: note, templateIDs: selected, includeAlwaysItems: includeAlways))
            }
            if hasDates, model.data.settings.reminderEnabled {
                Task { await Notifier.requestAuthorization() }
            }
            dismiss()
            if let newID {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    model.openTripID = newID
                }
            }
        case .edit(let id):
            model.updateTrip(id) { t in
                t.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? t.name : name
                t.destination = destination
                t.note = note
                t.startDate = s
                t.endDate = e
            }
            dismiss()
        }
    }
}
