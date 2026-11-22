import SwiftUI
import ValigiaCore

/// Type, color, size and weight limit of a bag.
struct LuggageEditorView: View {
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    let initial: Luggage
    let title: String
    let onSave: (Luggage) -> Void

    @State private var name = ""
    @State private var kind: LuggageKind = .suitcase
    @State private var color = Palette.defaultAccent
    @State private var useLitres = false
    @State private var width = ""
    @State private var height = ""
    @State private var depth = ""
    @State private var litres = ""
    @State private var maxWeight = ""
    @State private var emptyWeight = ""
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        IconBadge(icon: kind.symbol, tones: m3.tones(color), size: 52, cookie: true)
                        TextField("Nome", text: $name).font(.m3TitleMedium)
                    }
                }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(LuggageKind.allCases, id: \.self) { k in
                            Button { kind = k } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: k.symbol).font(.system(size: 20, weight: .semibold))
                                    Text(k.label).font(.m3LabelSmall).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .foregroundStyle(kind == k ? m3.onSecondaryContainer : m3.onSurfaceVariant)
                                .background(kind == k ? m3.secondaryContainer : m3.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: kind == k ? 14 : 20, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: { ListHeader(title: "Tipo") }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    ColorSwatches(colors: Palette.luggageColors, selection: $color)
                        .padding(.vertical, 4)
                } header: { ListHeader(title: "Colore") }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    Picker("Misura", selection: $useLitres) {
                        Text("Centimetri").tag(false)
                        Text("Litri").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if useLitres {
                        numberRow("Capacità", text: $litres, unit: "L")
                    } else {
                        numberRow("Larghezza", text: $width, unit: "cm")
                        numberRow("Altezza", text: $height, unit: "cm")
                        numberRow("Profondità", text: $depth, unit: "cm")
                        if let v = dimensions.volumeLitres {
                            Text("Volume: \(VolumeFormat.litres(v))").font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                        }
                    }
                } header: { ListHeader(title: "Dimensioni") }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    weightRow("Peso massimo", text: $maxWeight)
                    weightRow("Peso a vuoto", text: $emptyWeight)
                } header: { ListHeader(title: "Peso") } footer: {
                    Text("Scrivi in grammi o in kg (es. 8 kg). Il peso a vuoto si somma alle voci; sopra il massimo l'indicatore diventa rosso.")
                }
                .listRowBackground(m3.surfaceContainerLow)

                Section {
                    TextField("Note", text: $note, axis: .vertical).lineLimit(1...4)
                }
                .listRowBackground(m3.surfaceContainerLow)
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        var bag = initial
                        bag.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? kind.label : name
                        bag.kind = kind
                        bag.colorHex = color
                        bag.dimensions = dimensions
                        bag.maxWeightGrams = parseKg(maxWeight)
                        bag.emptyWeightGrams = parseKg(emptyWeight)
                        bag.note = note
                        onSave(bag)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var dimensions: Dimensions {
        func d(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } }
        if useLitres { return Dimensions(litres: d(litres)) }
        return Dimensions(widthCm: d(width), heightCm: d(height), depthCm: d(depth))
    }

    /// Bare numbers below 100 are kilograms ("8" → 8 kg), otherwise grams.
    private func parseKg(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }
        if let v = Double(t.replacingOccurrences(of: ",", with: ".")), v > 0, v < 100 {
            return Int((v * 1000).rounded())
        }
        return WeightFormat.parse(t).flatMap { $0 > 0 ? $0 : nil }
    }

    private func numberRow(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(m3.onSurfaceVariant)
        }
    }

    private func weightRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("es. 8 kg", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = initial.name
        kind = initial.kind
        color = initial.colorHex
        let d = initial.dimensions
        useLitres = d.litres != nil && !d.hasCentimetres
        func s(_ v: Double?) -> String {
            guard let v else { return "" }
            return v == v.rounded() ? "\(Int(v))" : String(v).replacingOccurrences(of: ".", with: ",")
        }
        width = s(d.widthCm)
        height = s(d.heightCm)
        depth = s(d.depthCm)
        litres = s(d.litres)
        maxWeight = initial.maxWeightGrams.map { WeightFormat.string($0) } ?? ""
        emptyWeight = initial.emptyWeightGrams.map { WeightFormat.string($0) } ?? ""
        note = initial.note
    }
}
