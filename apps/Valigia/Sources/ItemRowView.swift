import SwiftUI
import ValigiaCore

/// One line of the tree: indentation, disclosure, check, emoji, name and details.
struct ItemRowView: View {
    @Environment(\.m3) private var m3
    let row: TreeRow
    /// nil in templates (no ticks).
    let state: CheckState?
    let place: String
    let isFiltering: Bool
    let onToggleExpand: () -> Void
    let onCheck: () -> Void
    let onOpen: () -> Void

    private var item: Item { row.item }

    var body: some View {
        HStack(spacing: 8) {
            // Indentation guides
            if row.depth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<row.depth, id: \.self) { _ in
                        Rectangle()
                            .fill(m3.outlineVariant.opacity(0.7))
                            .frame(width: 1.5)
                            .frame(width: 16)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            if let state {
                Button(action: onCheck) {
                    CheckControl(state: state, size: 30)
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
            }
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    ItemGlyph(emoji: item.emoji, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.name.isEmpty ? "Senza nome" : item.name)
                                .font(row.hasChildren ? .m3TitleSmall : .m3BodyLarge)
                                .foregroundStyle(nameColor)
                                .strikethrough(state == .done(.packed) && !row.hasChildren, color: m3.onSurfaceVariant)
                                .lineLimit(2)
                            if item.quantity > 1 {
                                Text("×\(item.quantity)")
                                    .font(.m3LabelMedium)
                                    .foregroundStyle(m3.onSecondaryContainer)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(m3.secondaryContainer, in: Capsule())
                            }
                            if !item.attachments.isEmpty {
                                HStack(spacing: 2) {
                                    Image(systemName: "paperclip").font(.system(size: 11, weight: .bold))
                                    Text("\(item.attachments.count)").font(.m3LabelSmall)
                                }
                                .foregroundStyle(m3.onSurfaceVariant)
                                .accessibilityLabel(ItalianFormat.plural(item.attachments.count, "allegato", "allegati"))
                            }
                            if !item.owned {
                                Image(systemName: "cart.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(m3.tertiary)
                            }
                        }
                        if let detail = detail {
                            Text(detail)
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if let image = item.attachments.firstImage {
                        AttachmentThumb(attachment: image, size: 34)
                    }
                    if item.hasWeight {
                        Text(WeightFormat.string(item.totalWeightGrams))
                            .font(.m3LabelMedium)
                            .monospacedDigit()
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if row.hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .rotationEffect(.degrees(row.isExpanded ? 0 : -90))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(width: 32, height: 32)
                        .background(m3.surfaceContainerHighest, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isFiltering)
                .opacity(isFiltering ? 0.4 : 1)
                .accessibilityLabel(row.isExpanded ? "Comprimi" : "Espandi")
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(background, in: RoundedRectangle(cornerRadius: row.depth == 0 ? 20 : 16, style: .continuous))
    }

    private var background: Color {
        row.depth == 0 ? m3.surfaceContainerLow : m3.surfaceContainerLow.opacity(0.55)
    }

    private var nameColor: Color {
        if case .done(.packed)? = state, !row.hasChildren { return m3.onSurfaceVariant }
        return m3.onSurface
    }

    private var detail: String? {
        var parts: [String] = []
        if row.hasChildren {
            let total = item.leafIDs.count
            parts.append(ItalianFormat.plural(item.children.count, "voce", "voci") + (total != item.children.count ? " (\(total) in tutto)" : ""))
        }
        if case .done(.leftBehind)? = state {
            parts.append(place.isEmpty ? "lasciata" : "lasciata: \(place)")
        } else if case .done(.notFound)? = state {
            parts.append("non trovata")
        }
        if !item.note.isEmpty { parts.append(item.note) }
        if !item.tags.isEmpty { parts.append(item.tags.map { "#" + $0 }.joined(separator: " ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
