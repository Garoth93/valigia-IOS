import Foundation

public struct RGBColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    /// "#rrggbb" or "#rgb" (with or without "#").
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }), let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    /// Lowercase "#rrggbb".
    public var hex: String {
        "#" + [red, green, blue].map { component in
            let s = String(Int((component * 255).rounded()), radix: 16)
            return s.count == 1 ? "0" + s : s
        }.joined()
    }
}

// MARK: - CIE Lab / LCh (D65), used for Material-like tonal palettes

struct LCh: Equatable {
    var l: Double
    var c: Double
    var h: Double // degrees
}

enum ColorMath {
    static func linearize(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func delinearize(_ v: Double) -> Double {
        v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private static let white = (x: 0.95047, y: 1.0, z: 1.08883)

    private static func f(_ t: Double) -> Double {
        t > 216.0 / 24389.0 ? cbrt(t) : (24389.0 / 27.0 * t + 16) / 116
    }

    private static func fInv(_ t: Double) -> Double {
        let t3 = t * t * t
        return t3 > 216.0 / 24389.0 ? t3 : (116 * t - 16) / (24389.0 / 27.0)
    }

    static func lch(_ rgb: RGBColor) -> LCh {
        let r = linearize(rgb.red), g = linearize(rgb.green), b = linearize(rgb.blue)
        let x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
        let fx = f(x / white.x), fy = f(y / white.y), fz = f(z / white.z)
        let l = 116 * fy - 16
        let a = 500 * (fx - fy)
        let bb = 200 * (fy - fz)
        var h = atan2(bb, a) * 180 / .pi
        if h < 0 { h += 360 }
        return LCh(l: l, c: (a * a + bb * bb).squareRoot(), h: h)
    }

    /// Unclamped linear-to-sRGB conversion; `nil` when out of gamut.
    static func rgb(_ lch: LCh) -> (Double, Double, Double) {
        let hr = lch.h * .pi / 180
        let a = cos(hr) * lch.c, bb = sin(hr) * lch.c
        let fy = (lch.l + 16) / 116
        let fx = fy + a / 500
        let fz = fy - bb / 200
        let x = fInv(fx) * white.x, y = fInv(fy) * white.y, z = fInv(fz) * white.z
        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        return (r, g, b)
    }

    static func inGamut(_ v: (Double, Double, Double)) -> Bool {
        let e = 1e-4
        return [v.0, v.1, v.2].allSatisfy { $0 >= -e && $0 <= 1 + e }
    }

    /// Color with lightness `tone` (0…100), hue `h`, and the highest chroma ≤ `c` that fits sRGB.
    static func color(tone: Double, hue: Double, chroma: Double) -> RGBColor {
        let l = min(100, max(0, tone))
        if l <= 0.5 { return RGBColor(red: 0, green: 0, blue: 0) }
        if l >= 99.5 { return RGBColor(red: 1, green: 1, blue: 1) }
        var lo = 0.0, hi = max(0, chroma)
        if inGamut(rgb(LCh(l: l, c: hi, h: hue))) {
            lo = hi
        } else {
            for _ in 0..<24 {
                let mid = (lo + hi) / 2
                if inGamut(rgb(LCh(l: l, c: mid, h: hue))) { lo = mid } else { hi = mid }
            }
        }
        let v = rgb(LCh(l: l, c: lo, h: hue))
        return RGBColor(red: delinearize(max(0, v.0)), green: delinearize(max(0, v.1)), blue: delinearize(max(0, v.2)))
    }
}

/// A hue/chroma pair from which any tone (0 = black … 100 = white) can be taken.
public struct TonalPalette: Equatable, Sendable {
    public let hue: Double
    public let chroma: Double

    public init(hue: Double, chroma: Double) {
        self.hue = hue
        self.chroma = chroma
    }

    public init(hex: String, fallback: String = Palette.defaultAccent) {
        let rgb = RGBColor(hex: hex) ?? RGBColor(hex: fallback) ?? RGBColor(red: 0.4, green: 0.3, blue: 0.6)
        let lch = ColorMath.lch(rgb)
        self.init(hue: lch.h, chroma: max(lch.c, 36))
    }

    public func tone(_ t: Double) -> RGBColor {
        ColorMath.color(tone: t, hue: hue, chroma: chroma)
    }

    public func with(chroma: Double) -> TonalPalette { TonalPalette(hue: hue, chroma: chroma) }

    public func rotated(by degrees: Double) -> TonalPalette {
        TonalPalette(hue: (hue + degrees).truncatingRemainder(dividingBy: 360), chroma: chroma)
    }
}

/// Material 3 color roles generated from a seed color.
public struct MaterialScheme: Equatable, Sendable {
    public let primary: RGBColor
    public let onPrimary: RGBColor
    public let primaryContainer: RGBColor
    public let onPrimaryContainer: RGBColor
    public let secondaryContainer: RGBColor
    public let onSecondaryContainer: RGBColor
    public let tertiary: RGBColor
    public let tertiaryContainer: RGBColor
    public let onTertiaryContainer: RGBColor
    public let surface: RGBColor
    public let surfaceContainerLowest: RGBColor
    public let surfaceContainerLow: RGBColor
    public let surfaceContainer: RGBColor
    public let surfaceContainerHigh: RGBColor
    public let surfaceContainerHighest: RGBColor
    public let onSurface: RGBColor
    public let onSurfaceVariant: RGBColor
    public let outline: RGBColor
    public let outlineVariant: RGBColor
    public let error: RGBColor
    public let errorContainer: RGBColor
    public let onErrorContainer: RGBColor
    public let warning: RGBColor
    public let warningContainer: RGBColor
    public let onWarningContainer: RGBColor
    public let success: RGBColor
    public let successContainer: RGBColor
    public let onSuccessContainer: RGBColor

    public init(seed: String, dark: Bool) {
        let p = TonalPalette(hex: seed)
        let s = p.with(chroma: 16)
        let t = p.rotated(by: 60).with(chroma: 28)
        let n = p.with(chroma: 4)
        let nv = p.with(chroma: 8)
        let e = TonalPalette(hue: 32, chroma: 80)
        let w = TonalPalette(hue: 75, chroma: 70)
        let g = TonalPalette(hue: 140, chroma: 50)
        if dark {
            primary = p.tone(80); onPrimary = p.tone(20)
            primaryContainer = p.tone(30); onPrimaryContainer = p.tone(90)
            secondaryContainer = s.tone(30); onSecondaryContainer = s.tone(90)
            tertiary = t.tone(80); tertiaryContainer = t.tone(30); onTertiaryContainer = t.tone(90)
            surface = n.tone(6); surfaceContainerLowest = n.tone(4); surfaceContainerLow = n.tone(10)
            surfaceContainer = n.tone(12); surfaceContainerHigh = n.tone(17); surfaceContainerHighest = n.tone(22)
            onSurface = n.tone(90); onSurfaceVariant = nv.tone(80)
            outline = nv.tone(60); outlineVariant = nv.tone(30)
            error = e.tone(80); errorContainer = e.tone(30); onErrorContainer = e.tone(90)
            warning = w.tone(80); warningContainer = w.tone(30); onWarningContainer = w.tone(90)
            success = g.tone(80); successContainer = g.tone(30); onSuccessContainer = g.tone(90)
        } else {
            primary = p.tone(40); onPrimary = p.tone(100)
            primaryContainer = p.tone(90); onPrimaryContainer = p.tone(10)
            secondaryContainer = s.tone(90); onSecondaryContainer = s.tone(10)
            tertiary = t.tone(40); tertiaryContainer = t.tone(90); onTertiaryContainer = t.tone(10)
            surface = n.tone(98); surfaceContainerLowest = n.tone(100); surfaceContainerLow = n.tone(96)
            surfaceContainer = n.tone(94); surfaceContainerHigh = n.tone(92); surfaceContainerHighest = n.tone(90)
            onSurface = n.tone(10); onSurfaceVariant = nv.tone(30)
            outline = nv.tone(50); outlineVariant = nv.tone(80)
            error = e.tone(40); errorContainer = e.tone(90); onErrorContainer = e.tone(10)
            warning = w.tone(40); warningContainer = w.tone(90); onWarningContainer = w.tone(10)
            success = g.tone(40); successContainer = g.tone(90); onSuccessContainer = g.tone(10)
        }
    }
}

/// A named seed color the user can pick for the whole app theme.
public struct SeedColor: Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    public let hex: String
    public var id: String { hex }

    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }
}

public enum Palette {
    /// Seed color of the app theme (ocean blue).
    public static let defaultAccent = "#1e6fd9"

    /// Seeds offered in Settings: the whole Material scheme is generated from the chosen one.
    public static let seeds: [SeedColor] = [
        SeedColor(name: "Oceano", hex: "#1e6fd9"),
        SeedColor(name: "Corallo", hex: "#e8604c"),
        SeedColor(name: "Bosco", hex: "#2e7d4f"),
        SeedColor(name: "Lavanda", hex: "#7e57c2"),
        SeedColor(name: "Sabbia", hex: "#c58b2a"),
        SeedColor(name: "Laguna", hex: "#00897b"),
        SeedColor(name: "Ciliegia", hex: "#c2185b"),
        SeedColor(name: "Ardesia", hex: "#546e7a")
    ]

    /// Colors offered for a bag / suitcase.
    public static let luggageColors: [String] = [
        "#1e6fd9", "#e8604c", "#2e7d4f", "#7e57c2", "#c58b2a",
        "#00897b", "#c2185b", "#546e7a", "#f4b400", "#5d4037"
    ]
}
