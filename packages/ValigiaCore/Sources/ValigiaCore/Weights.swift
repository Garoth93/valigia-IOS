import Foundation

public extension Item {
    /// Weight of this item alone (unit weight × quantity), without children.
    var ownWeightGrams: Int { (weightGrams ?? 0) * Swift.max(1, quantity) }

    /// Weight of the whole branch.
    var totalWeightGrams: Int {
        ownWeightGrams + children.reduce(0) { $0 + $1.totalWeightGrams }
    }

    /// True when the item or any descendant has a weight.
    var hasWeight: Bool {
        weightGrams != nil || children.contains { $0.hasWeight }
    }
}

public extension Array where Element == Item {
    var totalWeightGrams: Int { reduce(0) { $0 + $1.totalWeightGrams } }
    var hasWeight: Bool { contains { $0.hasWeight } }
}

/// How full a bag is in weight.
public enum WeightLevel: Equatable, Sendable {
    /// No limit set.
    case unknown
    case ok
    /// Above 90% of the limit.
    case near
    case over
}

public extension Luggage {
    var contentWeightGrams: Int { items.totalWeightGrams }

    /// Content plus the empty bag.
    var totalWeightGrams: Int { contentWeightGrams + (emptyWeightGrams ?? 0) }

    /// 0…∞ (above 1 = overweight); nil without a limit.
    var weightFraction: Double? {
        guard let max = maxWeightGrams, max > 0 else { return nil }
        return Double(totalWeightGrams) / Double(max)
    }

    var isOverweight: Bool {
        guard let max = maxWeightGrams, max > 0 else { return false }
        return totalWeightGrams > max
    }

    var weightLevel: WeightLevel {
        guard let f = weightFraction else { return .unknown }
        if f > 1 { return .over }
        if f >= 0.9 { return .near }
        return .ok
    }
}

public extension Trip {
    var totalWeightGrams: Int { luggage.reduce(0) { $0 + $1.totalWeightGrams } }
    var itemCount: Int { luggage.reduce(0) { $0 + $1.items.itemCount } }
}

/// Italian weight formatting: "850 g", "1,25 kg", "12,5 kg".
public enum WeightFormat {
    public static func string(_ grams: Int) -> String {
        if abs(grams) < 1000 { return "\(grams) g" }
        let kg = Double(grams) / 1000
        let decimals = abs(kg) < 10 ? 2 : 1
        var s = String(format: "%.\(decimals)f", kg)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s.replacingOccurrences(of: ".", with: ",") + " kg"
    }

    /// "3,2 kg / 7 kg" or just the weight without a limit.
    public static func ratio(_ grams: Int, max: Int?) -> String {
        guard let max, max > 0 else { return string(grams) }
        return "\(string(grams)) / \(string(max))"
    }

    /// Parses "1,2 kg", "850", "850 g", "1.5kg" into grams.
    public static func parse(_ text: String) -> Int? {
        var s = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var factor = 1.0
        if s.hasSuffix("kg") {
            factor = 1000
            s.removeLast(2)
        } else if s.hasSuffix("g") {
            s.removeLast()
        }
        s = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let v = Double(s), v >= 0 else { return nil }
        return Int((v * factor).rounded())
    }
}

public enum VolumeFormat {
    /// "40 L", "38,5 L"
    public static func litres(_ l: Double) -> String {
        let rounded = (l * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) L" }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",") + " L"
    }

    /// "55 × 40 × 20 cm · 44 L"
    public static func dimensions(_ d: Dimensions) -> String? {
        var parts: [String] = []
        if let w = d.widthCm, let h = d.heightCm, let p = d.depthCm {
            parts.append("\(number(w)) × \(number(h)) × \(number(p)) cm")
        }
        if let l = d.volumeLitres { parts.append(litres(l)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func number(_ v: Double) -> String {
        if v == v.rounded() { return "\(Int(v))" }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}
