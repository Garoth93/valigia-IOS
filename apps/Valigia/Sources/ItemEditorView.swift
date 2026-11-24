import SwiftUI
import PhotosUI
import ValigiaCore

enum ItemEditorTarget: Identifiable {
    case new(parentID: UUID?)
    case edit(Item)

    var id: String {
        switch self {
        case .new(let p): return "new-\(p?.uuidString ?? "root")"
        case .edit(let i): return i.id.uuidString
        }
    }
}

/// Name, quantity, note, photo, weight, emoji, tags of an item.
struct ItemEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let ref: ListRef
    let target: ItemEditorTarget

    @State private var name = ""
    @State private var emoji = ""
    @State private var quantity = 1
    @State private var weightText = ""
    @State private var note = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var owned = true
    @State private var attachments: [Attachment] = []
    @State private var addAnother = false
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private static let emojis = ["👕", "👖", "🧦", "🩲", "🧥", "🧤", "🧣", "🧢", "👟", "🥾", "🩴", "🩱",
                                 "🪥", "🧴", "💊", "🩹", "🔌", "🔋", "📱", "💻", "🎧", "📷", "🪪", "🔑",
                                 "👛", "🎫", "📚", "🕶️", "☂️", "🧳", "🎒", "⛷️", "🚴", "🏃", "🏊", "⛺"]

    private var isNew: Bool { if case .new = target { return true } else { return false } }

    private var parentName: String? {
        guard case .new(let p) = target, let p else { return nil }
        return model.data.items(at: ref)?.find(p)?.name
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("🙂", text: $emoji)
                            .font(.system(size: 28))
                            .multilineTextAlignment(.center)
                            .frame(width: 52, height: 52)
                            .background(m3.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onChange(of: emoji) { _, v in
                                if v.count > 1, let last = v.last { emoji = String(last) }
                            }
                        TextField("Nome", text: $name)
                            .font(.m3TitleMedium)
                            .focused($nameFocused)
                            .submitLabel(.done)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Self.emojis, id: \.self) { e in
                                Button { emoji = e } label: {
                                    Text(e).font(.system(size: 22))
                                        .frame(width: 38, height: 38)
                                        .background(emoji == e ? m3.secondaryContainer : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let parentName {
                        Label("Dentro «\(parentName)»", systemImage: "arrow.turn.down.right")
                            .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    Stepper(value: $quantity, in: 1...999) {
                        HStack {
                            Text("Quantità")
                            Spacer()
                            Text("\(quantity)").monospacedDigit().foregroundStyle(m3.onSurfaceVariant)
                        }
                    }
                    HStack {
                        Text("Peso unitario")
                        Spacer()
                        TextField("es. 250 o 1,2 kg", text: $weightText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 150)
                        Text("g").foregroundStyle(m3.onSurfaceVariant)
                    }
                    if let g = WeightFormat.parse(weightText), quantity > 1 {
                        Text("Totale: \(WeightFormat.string(g * quantity))")
                            .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                    }
                    Toggle("Ce l'ho già", isOn: $owned)
                } footer: {
                    Text("Se non ce l'hai ancora finisce nella lista «Da comprare».")
                }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    TextField("Nota", text: $note, axis: .vertical).lineLimit(1...5)
                }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    if !tags.isEmpty {
                        FlowTags(tags: tags) { t in tags.removeAll { $0 == t } }
                    }
                    HStack {
                        Image(systemName: "number").foregroundStyle(m3.onSurfaceVariant)
                        TextField("Nuovo tag (es. inverno, volo)", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addTag)
                        if !newTag.isEmpty {
                            Button("Aggiungi", action: addTag)
                        }
                    }
                    let suggestions = model.allTags.filter { !tags.contains($0) }
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestions, id: \.self) { s in
                                    Chip(title: s, icon: "plus", selected: false) { tags.append(s) }
                                }
                            }
                        }
                    }
                } header: { ListHeader(title: "Tag") }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    AttachmentsEditor(attachments: $attachments)
                } header: {
                    ListHeader(title: "Allegati", trailing: attachments.isEmpty ? nil : "\(attachments.count)")
                } footer: {
                    Text("Tocca per aprire a schermo intero, tieni premuto per rinominare, spostare o eliminare. La prima foto fa da miniatura nella lista.")
                }
                .listRowBackground(m3.surfaceContainerLow)

                if isNew {
                    Section {
                        Toggle("Aggiungine un'altra dopo", isOn: $addAnother)
                    }
                    .listRowBackground(m3.surfaceContainerLow)
                }
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle(isNew ? "Nuova voce" : "Modifica voce")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Aggiungi" : "Salva", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func addTag() {
        let t = TextKey.tag(newTag)
        if !t.isEmpty, !tags.contains(t) { tags.append(t) }
        newTag = ""
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if case .edit(let item) = target {
            let current = model.data.items(at: ref)?.find(item.id) ?? item
            name = current.name
            emoji = current.emoji ?? ""
            quantity = current.quantity
            weightText = current.weightGrams.map(String.init) ?? ""
            note = current.note
            tags = current.tags
            owned = current.owned
            attachments = current.attachments
        } else {
            nameFocused = true
        }
    }

    private func save() {
        addTag()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let e = emoji.trimmingCharacters(in: .whitespaces)
        let weight = WeightFormat.parse(weightText)
        switch target {
        case .new(let parentID):
            let item = Item(name: trimmedName, quantity: quantity, note: note, emoji: e.isEmpty ? nil : e, weightGrams: weight, tags: tags, attachments: attachments, owned: owned)
            model.editItems(ref) { $0.insert(item, into: parentID, at: nil) }
            if addAnother {
                name = ""
                emoji = ""
                quantity = 1
                weightText = ""
                note = ""
                attachments = []
                nameFocused = true
                model.show("«\(trimmedName)» aggiunta")
                return
            }
        case .edit(let original):
            model.editItems(ref) { items in
                items.update(original.id) { i in
                    i.name = trimmedName
                    i.quantity = quantity
                    i.note = note
                    i.emoji = e.isEmpty ? nil : e
                    i.weightGrams = weight
                    i.tags = tags
                    i.attachments = attachments
                    i.owned = owned
                }
            }
        }
        dismiss()
    }
}

/// Removable tag chips laid out in rows.
struct FlowTags: View {
    @Environment(\.m3) private var m3
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { t in
                    Button { onRemove(t) } label: {
                        HStack(spacing: 4) {
                            Text("#" + t).font(.m3LabelLarge)
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .foregroundStyle(m3.onSecondaryContainer)
                        .background(m3.secondaryContainer, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Camera via UIImagePickerController.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
