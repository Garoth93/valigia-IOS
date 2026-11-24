import SwiftUI
import ValigiaCore

// Progress indicators in the Material 3 Expressive style (shared with the widgets).

/// Sine wave from the leading edge to `fraction` of the width.
struct WaveShape: Shape {
    var fraction: Double
    var amplitude: CGFloat = 3
    var wavelength: CGFloat = 18

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let end = rect.width * CGFloat(min(1, max(0, fraction)))
        guard end > 0 else { return p }
        let mid = rect.midY
        var x: CGFloat = 0
        p.move(to: CGPoint(x: 0, y: mid))
        while x <= end {
            let y = mid + sin(x / wavelength * 2 * .pi) * amplitude
            p.addLine(to: CGPoint(x: x, y: y))
            x += 1
        }
        return p
    }
}

/// Wavy linear progress: wave on the done part, flat track for the rest.
struct WavyProgressBar: View {
    let fraction: Double
    var color: Color
    var track: Color
    var height: CGFloat = 10
    /// A complete bar becomes flat (calm), like M3 Expressive.
    var flatWhenComplete = true

    var body: some View {
        GeometryReader { geo in
            let f = min(1, max(0, fraction))
            let gap: CGFloat = f > 0 && f < 1 ? 6 : 0
            let doneWidth = geo.size.width * f
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                    .frame(width: max(0, geo.size.width - doneWidth - gap), height: height * 0.4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if f >= 1 && flatWhenComplete {
                    Capsule().fill(color).frame(height: height * 0.4)
                } else {
                    WaveShape(fraction: 1, amplitude: height * 0.28, wavelength: max(12, height * 1.8))
                        .stroke(color, style: StrokeStyle(lineWidth: height * 0.4, lineCap: .round))
                        .frame(width: doneWidth, height: height)
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) per cento")
    }
}

/// Plain capsule bar (weight against the limit).
struct CapsuleBar: View {
    let fraction: Double
    var color: Color
    var track: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, fraction)))))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

/// Circular progress with round caps.
struct ProgressRing: View {
    let fraction: Double
    var color: Color
    var track: Color
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, fraction))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

extension Color {
    init(hex: String) {
        self.init(rgb: RGBColor(hex: hex) ?? RGBColor(red: 0.12, green: 0.43, blue: 0.85))
    }
}
