import SwiftUI
import ValigiaCore

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID

    @State private var showEdit = false
    @State private var showNewRound = false
    @State private var showAddLuggage = false
    @State private var showQuickCheck = false
    @State private var showSummary = false
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var renaming: CheckRound?
    @State private var renameText = ""
    @State private var luggageToDelete: Luggage?
    @State private var templateFrom: Luggage?
    @State private var templateName = ""

    var body: some View {
        if let trip = model.data.trip(tripID) {
            content(trip)
        } else {
            EmptyStateView(icon: "suitcase", title: "Viaggio non trovato", message: "Forse è stato eliminato.")
        }
    }

    private func content(_ trip: Trip) -> some View {
        let now = Date()
        let round = trip.activeRound
        let fill = TripFillState(trip: trip)
        let p = fill.progress
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    if !trip.subtitle(now: now).isEmpty {
                        Text(trip.subtitle(now: now))
                            .font(.m3BodyLarge)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    if !trip.note.isEmpty {
                        Text(trip.note).font(.m3BodyMedium).foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                .padding(.horizontal, 4)

                roundsBar(trip)

                // Round progress
                M3Card(color: m3.surfaceContainer, padding: 18, corner: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(p.percent)%")
                                .font(.m3DisplaySmall)
                                .monospacedDigit()
                                .foregroundStyle(m3.onSurface)
                                .contentTransition(.numericText())
                            VStack(alignment: .leading, spacing: 0) {
                                Text(round?.direction == .unpack ? "riportate a casa" : "preparate")
                                    .font(.m3LabelLarge).foregroundStyle(m3.onSurfaceVariant)
                                Text("\(p.packed) di \(ItalianFormat.items(p.total))")
                                    .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                            }
                            Spacer()
                            if round?.isCompleted == true {
                                TagLabel(text: "Giro chiuso", icon: "checkmark.seal.fill", tones: m3.successTones)
                            }
                        }
                        WavyProgressBar(fraction: p.fraction, color: m3.primary, track: m3.surfaceContainerHighest, height: 12)
                        if p.notFound + p.leftBehind > 0 {
                            HStack(spacing: 8) {
                                if p.notFound > 0 {
                                    TagLabel(text: "\(p.notFound) non trovate", icon: "questionmark", tones: m3.warningTones)
                                }
                                if p.leftBehind > 0 {
                                    TagLabel(text: "\(p.leftBehind) lasciate", icon: "house.fill", tones: m3.tertiaryTones)
                                }
                            }
                        }
                        HStack(spacing: 10) {
                            PillButton(title: "Controllo rapido", icon: "checklist", tones: m3.primaryTones, height: 52) {
                                showQuickCheck = true
                            }
                            .disabled(p.total == 0)
                            PillButton(title: "Fine giro", icon: "flag.checkered", tones: m3.primaryTones, filled: false, height: 52) {
                                showSummary = true
                            }
                            .frame(maxWidth: 150)
                        }
                    }
                }

                SectionTitle("Contenitori", trailing: trip.totalWeightGrams > 0 ? WeightFormat.string(trip.totalWeightGrams) : nil)
                ForEach(trip.luggage) { bag in
                    let ref = ListRef.trip(tripID: trip.id, luggageID: bag.id)
                    NavigationLink(value: ref) {
                        LuggageCard(luggage: bag, state: fill.luggage(bag.id), tripID: trip.id)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu { luggageMenu(trip, bag) }
                }
                Button { showAddLuggage = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                        Text("Aggiungi contenitore").font(.m3TitleSmall)
                    }
                    .foregroundStyle(m3.primary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(m3.outlineVariant, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
            .animation(.snappy, value: p)
        }
        .background(m3.surface)
        .navigationTitle(trip.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: TextExport.trip(trip)) { Image(systemName: "square.and.arrow.up") }
                Menu {
                    Button { showEdit = true } label: { Label("Modifica viaggio", systemImage: "pencil") }
                    ShareLink(item: TextExport.trip(trip, options: .init(onlyMissing: true))) {
                        Label("Condividi solo mancanti", systemImage: "list.bullet.indent")
                    }
                    ShareLink(item: TextExport.trip(trip, options: .init(withChecks: false))) {
                        Label("Condividi lista semplice", systemImage: "list.bullet")
                    }
                    Divider()
                    Button {
                        model.update { _ = $0.duplicateTrip(trip.id) }
                        model.show("Viaggio duplicato")
                    } label: { Label("Duplica viaggio", systemImage: "plus.square.on.square") }
                    Button {
                        model.updateTrip(trip.id) { $0.isArchived.toggle() }
                    } label: { Label(trip.isArchived ? "Ripristina" : "Archivia", systemImage: "archivebox") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina viaggio", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(isPresented: $showEdit) { TripEditorView(mode: .edit(trip.id)) }
        .sheet(isPresented: $showNewRound) { NewRoundSheet(tripID: trip.id).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showAddLuggage) { AddLuggageSheet(tripID: trip.id).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showSummary) { RoundSummaryView(tripID: trip.id).presentationDetents([.large]) }
        .fullScreenCover(isPresented: $showQuickCheck) { QuickCheckView(tripID: trip.id) }
        .confirmationDialog("Azzerare le spunte del giro «\(round?.name ?? "")»?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Azzera spunte", role: .destructive) {
                if let r = round { model.updateTrip(trip.id) { $0.resetRound(r.id) } }
            }
        } message: { Text("Gli altri giri non cambiano.") }
        .confirmationDialog("Eliminare il viaggio?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                dismiss()
                model.update { $0.deleteTrip(trip.id) }
            }
        }
        .confirmationDialog("Eliminare «\(luggageToDelete?.name ?? "")» dal viaggio?", isPresented: Binding(get: { luggageToDelete != nil }, set: { if !$0 { luggageToDelete = nil } }), titleVisibility: .visible) {
            Button("Elimina contenitore", role: .destructive) {
                if let b = luggageToDelete { model.update { $0.removeLuggage(b.id, fromTrip: trip.id) } }
                luggageToDelete = nil
            }
        } message: { Text("Il template da cui era stato creato non cambia.") }
        .alert("Rinomina giro", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nome", text: $renameText)
            Button("Annulla", role: .cancel) { renaming = nil }
            Button("Salva") {
                if let r = renaming, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.updateTrip(trip.id) { $0.editRound(r.id) { $0.name = renameText } }
                }
                renaming = nil
            }
        }
        .alert("Salva come template", isPresented: Binding(get: { templateFrom != nil }, set: { if !$0 { templateFrom = nil } })) {
            TextField("Nome del template", text: $templateName)
            Button("Annulla", role: .cancel) { templateFrom = nil }
            Button("Salva") {
                if let b = templateFrom {
                    model.update { _ = $0.saveAsTemplate(tripID: trip.id, luggageID: b.id, name: templateName) }
                    model.show("Template «\(templateName)» creato")
                }
                templateFrom = nil
            }
        } message: { Text("Copia indipendente del contenitore con tutta la sua lista.") }
    }

    // MARK: Rounds bar

    private func roundsBar(_ trip: Trip) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(trip.rounds) { r in
                    let selected = r.id == trip.activeRound?.id
                    let rp = trip.progress(round: r.id)
                    Button {
                        Haptics.selection()
                        model.updateTrip(trip.id) { $0.activeRoundID = r.id }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: r.isCompleted ? "checkmark.seal.fill" : r.kind.symbol)
                                .font(.system(size: 13, weight: .bold))
                            Text(r.name).font(.m3LabelLarge)
                            if rp.total > 0 {
                                Text("\(rp.packed)/\(rp.total)")
                                    .font(.m3LabelSmall)
                                    .monospacedDigit()
                                    .opacity(0.8)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .foregroundStyle(selected ? m3.onSecondaryContainer : m3.onSurfaceVariant)
                        .background(selected ? m3.secondaryContainer : Color.clear, in: RoundedRectangle(cornerRadius: selected ? 12 : 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: selected ? 12 : 20, style: .continuous).strokeBorder(selected ? Color.clear : m3.outlineVariant))
                        .animation(.snappy, value: selected)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { roundMenu(trip, r) }
                }
                Button { showNewRound = true } label: {
                    Label("Giro", systemImage: "plus")
                        .font(.m3LabelLarge)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .foregroundStyle(m3.primary)
                        .overlay(Capsule().strokeBorder(m3.outlineVariant))
                }
                .buttonStyle(.plain)
                if let r = trip.activeRound {
                    Menu { roundMenu(trip, r) } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 40, height: 40)
                            .foregroundStyle(m3.onSurfaceVariant)
                            .overlay(Circle().strokeBorder(m3.outlineVariant))
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func roundMenu(_ trip: Trip, _ r: CheckRound) -> some View {
        Button { confirmReset = true; model.updateTrip(trip.id) { $0.activeRoundID = r.id } } label: {
            Label("Azzera spunte", systemImage: "arrow.counterclockwise")
        }
        if r.isCompleted {
            Button { model.updateTrip(trip.id) { $0.reopenRound(r.id) } } label: { Label("Riapri giro", systemImage: "lock.open") }
        } else {
            Button { model.updateTrip(trip.id) { $0.completeRound(r.id) } } label: { Label("Chiudi giro", systemImage: "checkmark.seal") }
        }
        Picker(selection: Binding(get: { r.direction }, set: { d in model.updateTrip(trip.id) { $0.editRound(r.id) { $0.direction = d } } })) {
            Label("Riempi (metto dentro)", systemImage: "arrow.down.to.line").tag(PackDirection.pack)
            Label("Svuota (tiro fuori)", systemImage: "arrow.up.to.line").tag(PackDirection.unpack)
        } label: { Label("Direzione", systemImage: "arrow.up.arrow.down") }
        Button { renameText = r.name; renaming = r } label: { Label("Rinomina", systemImage: "pencil") }
        if trip.rounds.count > 1 {
            Button(role: .destructive) { model.updateTrip(trip.id) { $0.removeRound(r.id) } } label: {
                Label("Elimina giro", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func luggageMenu(_ trip: Trip, _ bag: Luggage) -> some View {
        Button { templateName = bag.name; templateFrom = bag } label: { Label("Salva come template", systemImage: "square.stack.3d.up") }
        ShareLink(item: TextExport.luggage(bag, round: trip.activeRound)) { Label("Condividi", systemImage: "square.and.arrow.up") }
        if let r = trip.activeRound {
            Button { model.updateTrip(trip.id) { $0.resetLuggage(bag.id, roundID: r.id) } } label: {
                Label("Azzera spunte di questo contenitore", systemImage: "arrow.counterclockwise")
            }
        }
        Button(role: .destructive) { luggageToDelete = bag } label: { Label("Elimina dal viaggio", systemImage: "trash") }
    }
}

/// A bag in the trip page.
struct LuggageCard: View {
    @Environment(\.m3) private var m3
    let luggage: Luggage
    let state: LuggageFillState?
    var tripID: UUID?

    var body: some View {
        let tones = m3.tones(luggage.colorHex)
        HStack(spacing: 14) {
            if let state {
                LuggageVisualView(state: state, tripID: tripID, size: 64)
            } else {
                IconBadge(icon: luggage.kind.symbol, tones: tones, size: 56, cookie: true)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(luggage.name)
                        .font(.m3TitleMedium)
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                    Spacer()
                    if let state {
                        Text("\(state.progress.packed)/\(state.progress.total)")
                            .font(.m3TitleSmall)
                            .monospacedDigit()
                            .foregroundStyle(state.progress.isComplete ? m3.success : m3.onSurfaceVariant)
                    } else {
                        Text(ItalianFormat.items(luggage.items.itemCount))
                            .font(.m3LabelMedium)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                Text([luggage.kind.label, VolumeFormat.dimensions(luggage.dimensions)].compactMap { $0 }.joined(separator: " · "))
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
                if luggage.totalWeightGrams > 0 || luggage.maxWeightGrams != nil {
                    WeightGauge(grams: luggage.totalWeightGrams, maxGrams: luggage.maxWeightGrams)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(m3.outline)
        }
        .padding(14)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule().fill(tones.accent).frame(width: 5, height: 36).padding(.leading, 3)
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Add a bag to a trip: from a template (copy) or empty.
struct AddLuggageSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var showBlank = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showBlank = true } label: {
                        Label("Contenitore vuoto", systemImage: "plus.square.dashed").font(.m3TitleSmall)
                    }
                }
                .listRowBackground(m3.surfaceContainerLow)
                Section {
                    ForEach(model.data.templates) { t in
                        Button {
                            model.update { _ = $0.addLuggage(toTrip: tripID, fromTemplate: t.id) }
                            model.show("«\(t.name)» aggiunto")
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                IconBadge(icon: t.luggage.kind.symbol, tones: m3.tones(t.luggage.colorHex), size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.name).font(.m3TitleSmall).foregroundStyle(m3.onSurface)
                                    Text(ItalianFormat.items(t.luggage.items.itemCount)).font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                                }
                            }
                        }
                    }
                } header: { ListHeader(title: "Da template") }
                .listRowBackground(m3.surfaceContainerLow)
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle("Aggiungi contenitore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } } }
            .sheet(isPresented: $showBlank) {
                LuggageEditorView(initial: Luggage(name: "Nuovo contenitore"), title: "Nuovo contenitore") { bag in
                    model.update { _ = $0.addLuggage(toTrip: tripID, fromTemplate: nil, blank: bag) }
                    dismiss()
                }
            }
        }
    }
}
