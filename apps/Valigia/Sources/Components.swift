import SwiftUI
import UniformTypeIdentifiers
import ValigiaCore

// MARK: - Surfaces

/// Material 3 card: tonal surface, large continuous corners.
struct M3Card<Content: View>: View {
    @Environment(\.m3) private var m3
    var color: Color?
    var padding: CGFloat
    var corner: CGFloat
    let content: Content

    init(color: Color? = nil, padding: CGFloat = 16, corner: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.color = color
        self.padding = padding
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct SectionTitle: View {
    @Environment(\.m3) private var m3
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.m3TitleMedium)
                .foregroundStyle(m3.onSurface)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Buttons

/// Pressed-state scale used by tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Material 3 filled / tonal pill button.
struct PillButton: View {
    let title: String
    let icon: String
    let tones: Tones
    var filled = true
    var height: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.m3TitleMedium)
            }
            .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(filled ? tones.accent : tones.container, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Small selectable chip (filter / house switcher).
struct Chip: View {
    @Environment(\.m3) private var m3
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.m3LabelLarge)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(selected ? m3.onSecondaryContainer : m3.onSurfaceVariant)
            .background(selected ? m3.secondaryContainer : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : m3.outlineVariant, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toast

struct ToastView: View {
    @Environment(\.m3) private var m3
    let toast: Toast

    var body: some View {
        let tones: Tones = {
            switch toast.style {
            case .success: return m3.successTones
            case .info: return m3.neutral
            case .error: return m3.errorTones
            }
        }()
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .bold))
            Text(toast.message)
                .font(.m3LabelLarge)
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(tones.container, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @Environment(\.m3) private var m3
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(icon: icon, tones: m3.primaryTones, size: 88, cookie: true)
            Text(title)
                .font(.m3TitleLarge)
                .foregroundStyle(m3.onSurface)
            Text(message)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

// MARK: - Pieces

/// Big number + label tile.
struct StatTile: View {
    @Environment(\.m3) private var m3
    let value: String
    let label: String
    var icon: String?
    var tones: Tones?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tones?.accent ?? m3.primary)
            }
            Text(value)
                .font(.m3TitleLarge)
                .foregroundStyle(tones?.onContainer ?? m3.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.m3LabelMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tones?.container ?? m3.surfaceContainer, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Small colored capsule (class, role).
struct TagLabel: View {
    let text: String
    let icon: String?
    let tones: Tones

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.m3LabelSmall)
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tones.container, in: Capsule())
    }
}

/// Plain file wrapper used by `fileExporter` for the JSON backup and CSV export.
struct DataFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
