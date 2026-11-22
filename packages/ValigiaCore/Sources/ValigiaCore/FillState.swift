import Foundation

// Architecture for the bag visuals (phase 2: illustrated suitcase, 3D suitcase).
// Any visual only needs:
//   1. `LuggageFillState` — how full the bag is (ticks and weight), and
//   2. `PackingEvent`s — what just happened ("item ticked", "round completed"…).
// Both are computed here, independent of SwiftUI, and tested.

/// Everything a bag visual needs to draw itself.
public struct LuggageFillState: Equatable, Sendable, Identifiable {
    public let luggageID: UUID
    public let name: String
    public let kind: LuggageKind
    public let colorHex: String
    public let direction: PackDirection
    public let progress: ProgressCount
    public let weightGrams: Int
    public let maxWeightGrams: Int?
    public let volumeLitres: Double?

    public var id: UUID { luggageID }

    /// Ticked fraction (0…1).
    public var checkedFraction: Double { progress.fraction }

    /// How full the bag looks: grows while packing, shrinks while unpacking.
    public var fillLevel: Double {
        guard progress.total > 0 else { return 0 }
        return direction == .pack ? progress.fraction : 1 - progress.fraction
    }

    /// Weight over the limit (nil without a limit).
    public var weightFraction: Double? {
        guard let max = maxWeightGrams, max > 0 else { return nil }
        return Double(weightGrams) / Double(max)
    }

    public var isOverweight: Bool { (weightFraction ?? 0) > 1 }

    /// Packing round done: the lid can close.
    public var isClosed: Bool { direction == .pack && progress.isComplete }

    /// Unpacking round done: the bag is empty.
    public var isEmptied: Bool { direction == .unpack && progress.isComplete }

    public init(luggage: Luggage, round: CheckRound?) {
        luggageID = luggage.id
        name = luggage.name
        kind = luggage.kind
        colorHex = luggage.colorHex
        direction = round?.direction ?? .pack
        progress = ProgressCount(leafIDs: luggage.items.leafIDs, marks: round?.markIndex ?? [:])
        weightGrams = luggage.totalWeightGrams
        maxWeightGrams = luggage.maxWeightGrams
        volumeLitres = luggage.dimensions.volumeLitres
    }
}

/// Fill state of a whole trip in one round.
public struct TripFillState: Equatable, Sendable {
    public let tripID: UUID
    public let roundID: UUID?
    public let direction: PackDirection
    public let luggage: [LuggageFillState]

    public var progress: ProgressCount { luggage.reduce(ProgressCount()) { $0 + $1.progress } }

    public init(trip: Trip, roundID: UUID? = nil) {
        let r = trip.round(roundID)
        tripID = trip.id
        self.roundID = r?.id
        direction = r?.direction ?? .pack
        luggage = trip.luggage.map { LuggageFillState(luggage: $0, round: r) }
    }

    public func luggage(_ id: UUID) -> LuggageFillState? { luggage.first { $0.luggageID == id } }
}

/// Something that just happened, for animations and haptics.
public enum PackingEvent: Equatable, Sendable {
    /// A unit was ticked: goes INTO the bag (pack round) or OUT of it (unpack round).
    case itemChecked(itemID: UUID, luggageID: UUID, direction: PackDirection)
    /// A tick was removed.
    case itemUnchecked(itemID: UUID, luggageID: UUID, direction: PackDirection)
    /// Marked as not found / left behind.
    case itemFlagged(itemID: UUID, luggageID: UUID, status: ItemStatus)
    /// One bag reached 100% in a packing round (close the lid).
    case luggageClosed(luggageID: UUID)
    /// One bag reached 100% in an unpacking round.
    case luggageEmptied(luggageID: UUID)
    /// The whole round reached 100%.
    case roundCompleted(roundID: UUID)
    /// The return (unpacking) round reached 100%: everything came back.
    case returnRoundEmptied(roundID: UUID)
}

public enum PackingEvents {
    /// Events between two versions of the same trip, in one round.
    public static func diff(before: Trip, after: Trip, roundID: UUID? = nil) -> [PackingEvent] {
        guard let r1 = after.round(roundID) else { return [] }
        let r0 = before.rounds.first { $0.id == r1.id }
        let old = r0?.markIndex ?? [:]
        let new = r1.markIndex
        var events: [PackingEvent] = []

        for bag in after.luggage {
            for id in bag.items.leafIDs {
                let a = old[id]?.status, b = new[id]?.status
                guard a != b else { continue }
                if b == .packed {
                    events.append(.itemChecked(itemID: id, luggageID: bag.id, direction: r1.direction))
                } else if a == .packed {
                    events.append(.itemUnchecked(itemID: id, luggageID: bag.id, direction: r1.direction))
                }
                if let b, b != .packed {
                    events.append(.itemFlagged(itemID: id, luggageID: bag.id, status: b))
                }
            }
        }

        let fillBefore = TripFillState(trip: before, roundID: r1.id)
        let fillAfter = TripFillState(trip: after, roundID: r1.id)
        for bag in fillAfter.luggage where bag.progress.isComplete {
            let was = fillBefore.luggage(bag.luggageID)?.progress.isComplete ?? false
            if !was {
                events.append(r1.direction == .pack ? .luggageClosed(luggageID: bag.luggageID) : .luggageEmptied(luggageID: bag.luggageID))
            }
        }
        if fillAfter.progress.isComplete, !fillBefore.progress.isComplete {
            events.append(.roundCompleted(roundID: r1.id))
            if r1.direction == .unpack {
                events.append(.returnRoundEmptied(roundID: r1.id))
            }
        }
        return events
    }
}

/// Whether an event makes something go into the bag or come out of it
/// (what a visual animates).
public enum ItemMotion: Equatable, Sendable {
    case enter
    case exit
}

public extension PackingEvent {
    /// Ticking in a packing round = goes in; ticking in an unpacking round = comes out.
    /// Removing a tick does the opposite. Other events move nothing.
    var motion: ItemMotion? {
        switch self {
        case .itemChecked(_, _, let d): return d == .pack ? .enter : .exit
        case .itemUnchecked(_, _, let d): return d == .pack ? .exit : .enter
        default: return nil
        }
    }

    /// The bag the event refers to (nil for whole-round events).
    var luggageID: UUID? {
        switch self {
        case .itemChecked(_, let l, _), .itemUnchecked(_, let l, _), .itemFlagged(_, let l, _): return l
        case .luggageClosed(let l), .luggageEmptied(let l): return l
        case .roundCompleted, .returnRoundEmptied: return nil
        }
    }
}
