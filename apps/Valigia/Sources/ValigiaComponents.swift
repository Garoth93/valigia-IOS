import SwiftUI
import ValigiaCore

// MARK: - Floating action button

/// Material 3 Expressive extended FAB: large rounded square that hugs a label.
struct ExtendedFAB: View {
    @Environment(\.m3) private var m3
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20, weight: .bold))
                Text(title).font(.m3TitleMedium)
            }
            .foregroundStyle(m3.onPrimaryContainer)
            .padding(.horizontal, 22)
            .frame(height: 60)
            .background(m3.primaryContainer, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Check control

/// The round check: empty ring, partial, packed, not found, left behind.
struct CheckControl: View {
    @Environment(\.m3) private var m3
    let state: CheckState
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            switch state {
            case .none:
                Circle().strokeBorder(m3.outline, lineWidth: size * 0.08)
            case .partial:
                Circle().strokeBorder(m3.primary, lineWidth: size * 0.08)
                Circle().trim(from: 0, to: 0.5)
                    .fill(m3.primary.opacity(0.35))
                    .rotationEffect(.degrees(90))
                    .padding(size * 0.16)
            case .done(let status):
                let tones = m3.tones(for: status)
                if status == .packed {
                    CookieShape(lobes: 8, depth: 0.07).fill(tones.accent)
                } else {
                    Circle().fill(tones.container)
                }
                Image(systemName: icon(status))
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(status == .packed ? tones.onAccent : tones.onContainer)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
    }

    private func icon(_ s: ItemStatus) -> String {
        switch s {
        case .packed: return "checkmark"
        case .notFound: return "questionmark"
        case .leftBehind: return "house.fill"
        }
    }

    private var label: String {
        switch state {
        case .none: return "Da preparare"
        case .partial: return "In parte preparata"
        case .done(let s): return s.label
        }
    }
}

// MARK: - Bag visuals

/// A view that draws a bag from its fill state and reacts to packing events.
/// Implementations: `SimpleLuggageVisual` (icon + ring) and `ThreeDLuggageVisual`
/// (RealityKit). The illustrated SwiftUI suitcase will conform to the same protocol.
/// `eventID` changes with every new batch of events (even identical ones).
protocol LuggageVisual: View {
    init(state: LuggageFillState, lastEvents: [PackingEvent], eventID: UUID?, size: CGFloat)
}

/// Picks the visual chosen in Settings. The 3D suitcase is used only where
/// there is room for it (`allowsLarge`, the header of a bag); small places
/// (cards) always use the simple icon, so only one 3D view renders at a time.
struct LuggageVisualView: View {
    @Environment(AppModel.self) private var model
    let state: LuggageFillState
    var tripID: UUID?
    var size: CGFloat = 64
    var allowsLarge = false

    static func usesLarge(_ style: LuggageVisualStyle, allowsLarge: Bool) -> Bool {
        allowsLarge && style == .threeD
    }

    var body: some View {
        let batch = model.events.lastBatch
        let events = relevantEvents(batch)
        if Self.usesLarge(model.data.settings.visualStyle, allowsLarge: allowsLarge) {
            ThreeDLuggageVisual(state: state, lastEvents: events, eventID: events.isEmpty ? nil : batch?.id, size: size)
        } else {
            SimpleLuggageVisual(state: state, lastEvents: events, eventID: batch?.id, size: size)
        }
    }

    /// Events of the last batch that concern this bag (or the whole round).
    private func relevantEvents(_ batch: PackingEventCenter.Batch?) -> [PackingEvent] {
        guard let batch, batch.tripID == tripID else { return [] }
        return batch.events.filter { $0.luggageID == nil || $0.luggageID == state.luggageID }
    }
}

/// Phase 1 visual: bag icon on a tonal cookie, surrounded by the progress ring.
struct SimpleLuggageVisual: LuggageVisual {
    @Environment(\.m3) private var m3
    let state: LuggageFillState
    let lastEvents: [PackingEvent]
    let eventID: UUID?
    let size: CGFloat

    init(state: LuggageFillState, lastEvents: [PackingEvent], eventID: UUID?, size: CGFloat) {
        self.state = state
        self.lastEvents = lastEvents
        self.eventID = eventID
        self.size = size
    }

    var body: some View {
        let tones = m3.tones(state.colorHex)
        ZStack {
            ProgressRing(fraction: state.progress.total == 0 ? 0 : state.checkedFraction,
                         color: state.isOverweight ? m3.error : tones.accent,
                         track: tones.container,
                         lineWidth: max(3, size * 0.07))
            CookieShape(lobes: 9, depth: 0.05)
                .fill(tones.container)
                .padding(size * 0.14)
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(tones.onContainer)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(state.name), \(state.progress.packed) su \(state.progress.total)")
    }

    private var symbol: String {
        if state.isClosed { return "checkmark" }
        if state.isEmptied { return "house.fill" }
        return state.kind.symbol
    }
}

// MARK: - Small pieces

/// Weight "3,2 kg / 7 kg" with a bar that turns red above the limit.
struct WeightGauge: View {
    @Environment(\.m3) private var m3
    let grams: Int
    let maxGrams: Int?
    var compact = false

    var body: some View {
        let level: WeightLevel = {
            guard let maxGrams, maxGrams > 0 else { return .unknown }
            let f = Double(grams) / Double(maxGrams)
            return f > 1 ? .over : (f >= 0.9 ? .near : .ok)
        }()
        let tones = m3.tones(for: level)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: level == .over ? "exclamationmark.triangle.fill" : "scalemass.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(WeightFormat.ratio(grams, max: maxGrams))
                    .font(.m3LabelMedium)
                    .monospacedDigit()
            }
            .foregroundStyle(level == .over ? m3.error : m3.onSurfaceVariant)
            if let maxGrams, maxGrams > 0, !compact {
                CapsuleBar(fraction: Double(grams) / Double(maxGrams), color: tones.accent, track: m3.surfaceContainerHighest, height: 6)
            }
        }
    }
}

/// Emoji or a neutral dot for an item.
struct ItemGlyph: View {
    @Environment(\.m3) private var m3
    let emoji: String?
    var size: CGFloat = 30

    var body: some View {
        Group {
            if let emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: size * 0.62))
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: size * 0.22))
                    .foregroundStyle(m3.outlineVariant)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Thumbnail of an item photo.
struct PhotoThumb: View {
    let name: String
    var size: CGFloat = 36
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.15)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .task(id: name) {
            let n = name
            image = await Task.detached { PhotoStore.image(named: n)?.preparingThumbnail(of: CGSize(width: 160, height: 160)) }.value
        }
    }
}

/// Section header inside a List.
struct ListHeader: View {
    @Environment(\.m3) private var m3
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title).font(.m3TitleSmall).foregroundStyle(m3.onSurface)
            Spacer()
            if let trailing { Text(trailing).font(.m3LabelMedium).foregroundStyle(m3.onSurfaceVariant) }
        }
        .textCase(nil)
    }
}

/// Color swatch picker.
struct ColorSwatches: View {
    @Environment(\.m3) private var m3
    let colors: [String]
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            ForEach(colors, id: \.self) { hex in
                Button {
                    selection = hex
                } label: {
                    ZStack {
                        Circle().fill(Color(hex: hex))
                        if selection.lowercased() == hex.lowercased() {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                        }
                    }
                    .frame(height: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension Trip {
    /// "12–14 dic 2026 · tra 3 giorni"
    func subtitle(now: Date) -> String {
        var parts: [String] = []
        if !destination.isEmpty { parts.append(destination) }
        if let d = dateLabel { parts.append(d) }
        switch phase(now: now) {
        case .upcoming(let days): parts.append(days == 1 ? "domani" : "tra \(days) giorni")
        case .ongoing: parts.append("in corso")
        default: break
        }
        return parts.joined(separator: " · ")
    }
}
