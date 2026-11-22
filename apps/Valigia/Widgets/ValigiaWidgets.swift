import WidgetKit
import SwiftUI
import ValigiaCore

@main
struct ValigiaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextTripWidget()
    }
}

// MARK: - Timeline

struct TripEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var trip: WidgetSnapshot.TripInfo? { snapshot?.trip }
    var seed: String { snapshot?.seedHex ?? Palette.defaultAccent }
}

struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry {
        TripEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) {
        let snap = SharedStore.loadSnapshot()
        completion(TripEntry(date: Date(), snapshot: (context.isPreview && snap?.trip == nil) ? .placeholder : snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        let now = Date()
        let snap = SharedStore.loadSnapshot()
        // "tra N giorni" changes at midnight.
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [TripEntry(date: now, snapshot: snap)], policy: .after(midnight)))
    }
}

// MARK: - Widget

struct NextTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ValigiaNextTrip", provider: TripProvider()) { entry in
            NextTripWidgetView(entry: entry)
        }
        .configurationDisplayName("Prossimo viaggio")
        .description("Quanto manca da preparare per il prossimo viaggio.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

private func tripURL(_ trip: WidgetSnapshot.TripInfo?) -> URL {
    if let id = trip?.id { return URL(string: "valigia://trip/\(id.uuidString)")! }
    return URL(string: "valigia://open")!
}

private func whenText(_ trip: WidgetSnapshot.TripInfo, now: Date) -> String {
    guard let start = trip.startDate else { return trip.roundName }
    let d = ItalianFormat.daysBetween(now, start)
    if d > 0 { return d == 1 ? "domani" : "tra \(d) giorni" }
    if let end = trip.endDate, ItalianFormat.daysBetween(now, end) >= 0 { return "in viaggio" }
    return "oggi"
}

struct NextTripWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: TripEntry

    var body: some View {
        let m3 = M3Theme(seed: entry.seed, dark: colorScheme == .dark)
        Group {
            switch family {
            case .accessoryInline:
                if let t = entry.trip {
                    Label("\(t.name): \(t.packed)/\(t.total)", systemImage: "suitcase.fill")
                } else {
                    Label("Nessun viaggio", systemImage: "suitcase")
                }
            case .accessoryCircular:
                Gauge(value: entry.trip?.fraction ?? 0) {
                    Image(systemName: "suitcase.fill")
                } currentValueLabel: {
                    Text("\(Int(((entry.trip?.fraction ?? 0) * 100).rounded()))")
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label(entry.trip?.name ?? "Valigia", systemImage: "suitcase.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .widgetAccentable()
                        .lineLimit(1)
                    if let t = entry.trip {
                        Text(t.total == t.packed && t.total > 0 ? "Tutto pronto" : "Mancano \(t.total - t.packed) voci")
                            .font(.system(size: 13, design: .rounded))
                        Gauge(value: t.fraction) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                    } else {
                        Text("Nessun viaggio in programma").font(.system(size: 12))
                    }
                }
            case .systemMedium:
                medium(m3)
            default:
                small(m3)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall || family == .systemMedium {
                m3.primaryContainer
            } else {
                Color.clear
            }
        }
        .widgetURL(tripURL(entry.trip))
    }

    private func small(_ m3: M3Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let t = entry.trip {
                HStack {
                    ZStack {
                        ProgressRing(fraction: t.fraction, color: m3.primary, track: m3.onPrimaryContainer.opacity(0.15), lineWidth: 6)
                        Text("\(Int((t.fraction * 100).rounded()))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(m3.onPrimaryContainer)
                    }
                    .frame(width: 50, height: 50)
                    Spacer()
                    Image(systemName: t.bags.first?.symbol ?? "suitcase.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(m3.primary)
                }
                Spacer(minLength: 0)
                Text(t.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(m3.onPrimaryContainer)
                    .lineLimit(2)
                Text("\(whenText(t, now: entry.date)) · \(t.packed)/\(t.total)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                    .lineLimit(1)
            } else {
                Image(systemName: "suitcase.rolling.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(m3.primary)
                Spacer(minLength: 0)
                Text("Nessun viaggio in programma")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(m3.onPrimaryContainer)
            }
        }
        .padding(14)
    }

    private func medium(_ m3: M3Theme) -> some View {
        HStack(alignment: .top, spacing: 14) {
            small(m3).frame(width: 150)
            VStack(alignment: .leading, spacing: 8) {
                if let t = entry.trip {
                    ForEach(t.bags.prefix(3)) { bag in
                        let tones = m3.tones(bag.colorHex)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: bag.symbol).font(.system(size: 11, weight: .bold))
                                Text(bag.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                                Spacer(minLength: 2)
                                Text("\(bag.packed)/\(bag.total)").font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                            }
                            .foregroundStyle(m3.onPrimaryContainer)
                            CapsuleBar(fraction: bag.fraction, color: tones.accent, track: m3.onPrimaryContainer.opacity(0.12), height: 6)
                        }
                    }
                    if !t.missingNames.isEmpty {
                        Text("Manca: " + t.missingNames.prefix(3).joined(separator: ", "))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(m3.onPrimaryContainer.opacity(0.75))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 14)
            .padding(.trailing, 14)
        }
    }
}
