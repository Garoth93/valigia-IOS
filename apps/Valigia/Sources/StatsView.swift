import SwiftUI
import Charts
import ValigiaCore

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        let s = PackingStats(data: model.data, now: Date())
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatTile(value: "\(s.tripsDone)", label: s.tripsDone == 1 ? "viaggio fatto" : "viaggi fatti", icon: "airplane", tones: m3.primaryTones)
                    StatTile(value: "\(s.daysAway)", label: s.daysAway == 1 ? "giorno in viaggio" : "giorni in viaggio", icon: "calendar", tones: m3.tertiaryTones)
                    StatTile(value: "\(s.itemsPacked)", label: "voci spuntate", icon: "checkmark.circle", tones: m3.successTones)
                    StatTile(value: "\(s.roundsCompleted)", label: "giri chiusi", icon: "flag.checkered", tones: m3.neutral)
                }

                SectionTitle("Dimenticate più spesso")
                M3Card {
                    if s.forgotten.isEmpty {
                        Text("Ancora niente: qui finiscono le voci «non trovate», «lasciate» o rimaste senza spunta in un giro chiuso.")
                            .font(.m3BodyMedium).foregroundStyle(m3.onSurfaceVariant)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(s.forgotten.prefix(10)) { f in
                                HStack(spacing: 12) {
                                    ItemGlyph(emoji: f.emoji, size: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.name).font(.m3TitleSmall).foregroundStyle(m3.onSurface)
                                        Text(detail(f)).font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                                    }
                                    Spacer()
                                    Text("\(f.count)×")
                                        .font(.m3TitleMedium)
                                        .foregroundStyle(m3.onWarningContainer)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(m3.warningContainer, in: Capsule())
                                }
                            }
                        }
                    }
                }

                SectionTitle("Peso medio per contenitore")
                M3Card {
                    if s.weightByKind.isEmpty {
                        Text("Aggiungi i pesi alle voci per vedere quanto pesano in media zaini e valigie.")
                            .font(.m3BodyMedium).foregroundStyle(m3.onSurfaceVariant)
                    } else {
                        Chart(s.weightByKind) { k in
                            BarMark(
                                x: .value("Peso (kg)", Double(k.averageGrams) / 1000),
                                y: .value("Tipo", k.kind.label)
                            )
                            .foregroundStyle(m3.primary)
                            .cornerRadius(8)
                            .annotation(position: .trailing) {
                                Text(WeightFormat.string(k.averageGrams)).font(.m3LabelSmall).foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisGridLine().foregroundStyle(m3.outlineVariant)
                                AxisValueLabel().foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                        .frame(height: CGFloat(max(1, s.weightByKind.count)) * 44 + 20)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(s.weightByKind) { k in
                                Text("\(k.kind.label): media \(WeightFormat.string(k.averageGrams)), max \(WeightFormat.string(k.maxGrams)) su \(ItalianFormat.plural(k.samples, "contenitore", "contenitori"))")
                                    .font(.m3BodySmall).foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                if !s.templateUse.isEmpty {
                    SectionTitle("Template più usati")
                    M3Card {
                        VStack(spacing: 8) {
                            ForEach(s.templateUse.prefix(6)) { t in
                                HStack {
                                    Text(t.name).font(.m3BodyLarge).foregroundStyle(m3.onSurface)
                                    Spacer()
                                    Text("\(t.count)×").font(.m3TitleSmall).foregroundStyle(m3.primary)
                                }
                            }
                        }
                    }
                }

                if !s.topDestinations.isEmpty {
                    SectionTitle("Destinazioni")
                    M3Card {
                        Text(s.topDestinations.prefix(8).joined(separator: " · "))
                            .font(.m3BodyLarge).foregroundStyle(m3.onSurface)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
        .background(m3.surface)
        .navigationTitle("Statistiche")
    }

    private func detail(_ f: PackingStats.Forgotten) -> String {
        var parts: [String] = []
        if f.notFound > 0 { parts.append("\(f.notFound) non trovata") }
        if f.leftBehind > 0 { parts.append("\(f.leftBehind) lasciata") }
        let other = f.count - f.notFound - f.leftBehind
        if other > 0 { parts.append("\(other) senza spunta") }
        parts.append("ultima: \(f.lastTripName)")
        return parts.joined(separator: " · ")
    }
}
