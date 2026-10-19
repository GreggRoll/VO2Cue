import Foundation

// Compact, bounded graph data. The Watch owns coordinates and continuity; iPhone never
// reconstructs sample timing from its own clock. Seconds follow the planned workout
// timeline, with pauses excluded and skipped remainders left blank.
struct HeartRateTracePoint: Codable, Equatable, Sendable, Identifiable {
    let deciseconds: Int
    let bpm: Int
    let segment: Int
    var seconds: Double { Double(deciseconds) / 10 }
    var id: Int { deciseconds }
    var isValid: Bool { deciseconds >= 0 && (20...260).contains(bpm) && segment >= 0 }

    init(deciseconds: Int, bpm: Int, segment: Int) {
        self.deciseconds = deciseconds
        self.bpm = bpm
        self.segment = segment
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        deciseconds = try values.decode(Int.self)
        bpm = try values.decode(Int.self)
        segment = try values.decode(Int.self)
        guard isValid else { throw DecodingError.dataCorruptedError(in: values, debugDescription: "Invalid heart-rate point") }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(deciseconds)
        try values.encode(bpm)
        try values.encode(segment)
    }
}

struct WorkoutHeartRateTrace: Codable, Equatable, Sendable {
    static let capacity = 480
    private(set) var points: [HeartRateTracePoint] = []

    var isValid: Bool {
        points.count <= Self.capacity && points.allSatisfy(\.isValid)
            && zip(points, points.dropFirst()).allSatisfy { $0.deciseconds < $1.deciseconds && $0.segment <= $1.segment }
    }

    mutating func append(seconds: Double, bpm: Double, breakBefore: Bool = false) {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 10),
              bpm.isFinite, (20...260).contains(bpm) else { return }
        let time = Int((seconds * 10).rounded(.down))
        let last = points.last
        guard last == nil || time > last!.deciseconds else { return }
        // Two-second sampling bounds graph churn. Keep a new point at a continuity break.
        guard breakBefore || last == nil || time - last!.deciseconds >= 20 else { return }
        let segment = (last?.segment ?? 0) + ((breakBefore || (last.map { time - $0.deciseconds > 150 } ?? false)) ? 1 : 0)
        merge(HeartRateTracePoint(deciseconds: time, bpm: Int(bpm.rounded()), segment: segment))
    }

    mutating func merge(_ point: HeartRateTracePoint) {
        guard point.isValid, points.last.map({ point.deciseconds > $0.deciseconds && point.segment >= $0.segment }) ?? true else { return }
        if points.count >= Self.capacity {
            // Retain the entire workout, including its first reading, at a lower resolution.
            points = points.enumerated().filter { $0.offset.isMultiple(of: 2) || $0.offset == points.count - 1 }.map(\.element)
        }
        points.append(point)
    }
}

enum HeartRateHalfwayCue: String, Equatable {
    case up = "Heart rate up"
    case down = "Heart rate down"
    case good = "Heart rate good"

    static func resolve(presentation: HeartRatePresentation, phase: WorkoutPhaseKind,
                        guidance: HeartRateGuidance?, at now: Date) -> Self? {
        guard guidance?.enabled == true, guidance?.cuesEnabled == true,
              let range = guidance?.target(for: phase),
              let sample = presentation.sample, sample.isFresh(at: now),
              presentation.status != .paused else { return nil }
        let bpm = presentation.trendBPM ?? sample.bpm
        guard bpm.isFinite else { return nil }
        if bpm > Double(range.upper) { return .down }
        if bpm < Double(range.lower), phase == .work { return .up }
        return .good
    }
}
