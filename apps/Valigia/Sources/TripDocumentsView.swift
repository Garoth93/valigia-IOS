import SwiftUI
import ValigiaCore

/// All the documents of a trip: its own (tickets, bookings…) and those
/// attached to items, with where each one is ("Zaino › Astuccio documenti › Passaporto").
struct TripDocumentsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let tripID: UUID

    var body: some View {
        if let trip = model.data.trip(tripID) {
            let itemDocs = trip.documents.filter { $0.source != .trip }
            List {
                if !DocumentLock.shared.canShow {
                    Section {
                        Button {
                            Task { await DocumentLock.shared.unlock() }
                        } label: {
                            Label("Sblocca con \(DeviceAuth.biometryName) per vedere le anteprime", systemImage: "lock.fill")
                                .font(.m3TitleSmall)
                        }
                    }
                    .listRowBackground(m3.surfaceContainerHigh)
                }
                Section {
                    AttachmentsEditor(attachments: Binding(
                        get: { model.data.trip(tripID)?.attachments ?? [] },
                        set: { newValue in model.update { $0.editTripAttachments(tripID) { $0 = newValue } } }
                    ), emptyText: "Biglietti, carte d'imbarco, prenotazioni, assicurazione: aggiungili qui per averli a portata di mano.")
                } header: {
                    ListHeader(title: "Del viaggio", trailing: trip.attachments.isEmpty ? nil : "\(trip.attachments.count)")
                }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    if itemDocs.isEmpty {
                        Text("Nessuna voce ha allegati. Aggiungili dalla scheda della voce (es. il passaporto nell'astuccio documenti).")
                            .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                    }
                    ForEach(Array(itemDocs.enumerated()), id: \.element.id) { index, doc in
                        Button {
                            AttachmentPreview.open(itemDocs.map(\.attachment), at: index)
                        } label: {
                            HStack(spacing: 12) {
                                AttachmentThumb(attachment: doc.attachment, size: 48)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(doc.attachment.title)
                                        .font(.m3TitleSmall).foregroundStyle(m3.onSurface).lineLimit(1)
                                    Text(doc.location)
                                        .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant).lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: doc.attachment.kind.symbol)
                                    .foregroundStyle(m3.onSurfaceVariant)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    ListHeader(title: "Dalle voci", trailing: itemDocs.isEmpty ? nil : "\(itemDocs.count)")
                }
                .listRowBackground(m3.surfaceContainerLow)
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle("Documenti")
            .task { await DocumentLock.shared.unlock() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(ByteFormat.string(trip.attachmentsByteSize))
                        .font(.m3LabelMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
            }
        } else {
            EmptyStateView(icon: "doc", title: "Viaggio non trovato", message: "")
        }
    }
}

/// Card in the trip page that opens the documents.
struct TripDocumentsCard: View {
    @Environment(\.m3) private var m3
    let trip: Trip

    var body: some View {
        let docs = trip.documents
        HStack(spacing: 14) {
            IconBadge(icon: "doc.text.fill", tones: m3.tertiaryTones, size: 48, cookie: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Documenti").font(.m3TitleMedium).foregroundStyle(m3.onSurface)
                Text(docs.isEmpty ? "Biglietti, prenotazioni e allegati delle voci" : "\(ItalianFormat.plural(docs.count, "documento", "documenti")) · \(ByteFormat.string(trip.attachmentsByteSize))")
                    .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant).lineLimit(1)
            }
            Spacer()
            HStack(spacing: -10) {
                ForEach(docs.prefix(3)) { d in
                    AttachmentThumb(attachment: d.attachment, size: 34)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(m3.surfaceContainerLow, lineWidth: 2))
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(m3.outline)
        }
        .padding(14)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
