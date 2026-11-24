import SwiftUI
import ValigiaCore

struct TripsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var showNew = false
    @State private var query = ""
    @State private var showArchived = false
    @State private var toDelete: Trip?

    var body: some View {
        @Bindable var model = model
        let now = Date()
        let sections = model.data.tripSections(now: now)
        let next = model.data.nextTrip(now: now)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.data.trips.isEmpty {
                    EmptyStateView(icon: "suitcase.rolling.fill", title: "Nessun viaggio",
                                   message: "Crea un viaggio e scegli i contenitori partendo dai template: zaino, trolley, borsa…")
                    PillButton(title: "Nuovo viaggio", icon: "plus", tones: m3.primaryTones) { showNew = true }
                        .padding(.horizontal, 32)
                } else {
                    if query.isEmpty, let next {
                        NavigationLink(value: next.id) { NextTripCard(trip: next, now: now) }
                            .buttonStyle(PressableStyle())
                            .contextMenu { menu(for: next) }
                    }
                    let current = filtered(sections.current).filter { !(query.isEmpty && $0.id == next?.id) }
                    if !current.isEmpty {
                        SectionTitle(query.isEmpty ? "Altri viaggi" : "Viaggi", trailing: nil)
                        ForEach(current) { trip in tripLink(trip, now: now) }
                    }
                    let past = filtered(sections.past)
                    if !past.isEmpty {
                        SectionTitle("Passati", trailing: "\(past.count)")
                        ForEach(past) { trip in tripLink(trip, now: now) }
                    }
                    let archived = filtered(sections.archived)
                    if !archived.isEmpty {
                        Button {
                            withAnimation(.snappy) { showArchived.toggle() }
                        } label: {
                            HStack {
                                SectionTitle("Archiviati", trailing: "\(archived.count)")
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(showArchived ? 180 : 0))
                                    .foregroundStyle(m3.onSurfaceVariant)
                                    .padding(.top, 8)
                            }
                        }
                        .buttonStyle(.plain)
                        if showArchived || !query.isEmpty {
                            ForEach(archived) { trip in tripLink(trip, now: now) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .background(m3.surface)
        .navigationTitle("Viaggi")
        .searchable(text: $query, prompt: "Cerca viaggio o destinazione")
        .overlay(alignment: .bottomTrailing) {
            if !model.data.trips.isEmpty {
                ExtendedFAB(title: "Viaggio", icon: "plus") { showNew = true }
                    .padding(20)
            }
        }
        .sheet(isPresented: $showNew) {
            TripEditorView(mode: .new)
        }
        .navigationDestination(for: UUID.self) { id in
            TripDetailView(tripID: id)
        }
        .navigationDestination(for: ListRef.self) { ref in
            LuggageView(ref: ref)
        }
        .navigationDestination(item: $model.openTripID) { id in
            TripDetailView(tripID: id)
        }
        .confirmationDialog("Eliminare il viaggio?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Elimina \(toDelete?.name ?? "")", role: .destructive) {
                if let t = toDelete { model.update { $0.deleteTrip(t.id) } }
                toDelete = nil
            }
        } message: {
            Text("Liste, spunte e giri di questo viaggio verranno eliminati. I template non cambiano.")
        }
    }

    private func filtered(_ trips: [Trip]) -> [Trip] {
        let q = TextKey.normalized(query)
        guard !q.isEmpty else { return trips }
        return trips.filter { TextKey.normalized($0.name + " " + $0.destination).contains(q) }
    }

    private func tripLink(_ trip: Trip, now: Date) -> some View {
        NavigationLink(value: trip.id) { TripCard(trip: trip, now: now) }
            .buttonStyle(PressableStyle())
            .contextMenu { menu(for: trip) }
    }

    @ViewBuilder
    private func menu(for trip: Trip) -> some View {
        Button {
            model.update { _ = $0.duplicateTrip(trip.id) }
            model.show("Viaggio duplicato")
        } label: { Label("Duplica", systemImage: "plus.square.on.square") }
        ShareLink(item: TextExport.trip(trip)) { Label("Condividi lista", systemImage: "square.and.arrow.up") }
        Button {
            model.updateTrip(trip.id) { $0.isArchived.toggle() }
        } label: {
            Label(trip.isArchived ? "Ripristina" : "Archivia", systemImage: trip.isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        Button(role: .destructive) { toDelete = trip } label: { Label("Elimina", systemImage: "trash") }
    }
}

/// Large card of the next (or ongoing) trip.
struct NextTripCard: View {
    @Environment(\.m3) private var m3
    let trip: Trip
    let now: Date

    var body: some View {
        let p = trip.progress()
        let fill = TripFillState(trip: trip)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.m3LabelLarge)
                        .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                    Text(trip.name)
                        .font(.m3HeadlineMedium)
                        .foregroundStyle(m3.onPrimaryContainer)
                        .lineLimit(2)
                    if !trip.subtitle(now: now).isEmpty {
                        Text(trip.subtitle(now: now))
                            .font(.m3BodyMedium)
                            .foregroundStyle(m3.onPrimaryContainer.opacity(0.85))
                    }
                }
                Spacer()
                ZStack {
                    CookieShape(lobes: 10, depth: 0.06).fill(m3.primary)
                    VStack(spacing: -2) {
                        Text("\(p.percent)").font(.m3TitleLarge).monospacedDigit()
                        Text("%").font(.m3LabelSmall)
                    }
                    .foregroundStyle(m3.onPrimary)
                }
                .frame(width: 72, height: 72)
            }
            WavyProgressBar(fraction: p.fraction, color: m3.primary, track: m3.onPrimaryContainer.opacity(0.18), height: 12)
            HStack(spacing: 8) {
                if let r = trip.activeRound {
                    TagLabel(text: r.name, icon: r.kind.symbol, tones: Tones(accent: m3.primary, onAccent: m3.onPrimary, container: m3.surface.opacity(0.7), onContainer: m3.onSurface))
                }
                Text(p.total == 0 ? "Lista vuota" : "\(p.packed) di \(ItalianFormat.items(p.total)) pronte")
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onPrimaryContainer)
                Spacer()
                HStack(spacing: -8) {
                    ForEach(fill.luggage.prefix(4)) { bag in
                        Image(systemName: bag.kind.symbol)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(m3.tones(bag.colorHex).onContainer)
                            .frame(width: 32, height: 32)
                            .background(m3.tones(bag.colorHex).container, in: Circle())
                            .overlay(Circle().strokeBorder(m3.primaryContainer, lineWidth: 2))
                    }
                }
            }
        }
        .padding(20)
        .background(m3.primaryContainer, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var headline: String {
        switch trip.phase(now: now) {
        case .ongoing: return "IN VIAGGIO"
        case .upcoming(let d): return d == 1 ? "SI PARTE DOMANI" : "PROSSIMO VIAGGIO"
        default: return "PROSSIMO VIAGGIO"
        }
    }
}

struct TripCard: View {
    @Environment(\.m3) private var m3
    let trip: Trip
    let now: Date

    var body: some View {
        let p = trip.progress()
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(fraction: p.fraction, color: m3.primary, track: m3.surfaceContainerHighest, lineWidth: 5)
                Image(systemName: trip.luggage.first?.kind.symbol ?? "suitcase.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(m3.primary)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name)
                    .font(.m3TitleMedium)
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                Text(trip.subtitle(now: now).isEmpty ? ItalianFormat.plural(trip.luggage.count, "contenitore", "contenitori") : trip.subtitle(now: now))
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(p.packed)/\(p.total)")
                    .font(.m3TitleSmall)
                    .monospacedDigit()
                    .foregroundStyle(m3.onSurface)
                if let r = trip.activeRound {
                    Text(r.name).font(.m3LabelSmall).foregroundStyle(m3.onSurfaceVariant)
                }
            }
        }
        .padding(14)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
