import Foundation
@testable import BenchCore

/// A local-time instant, as the original tests' `local(y, m, d, h, min)`.
func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Millis {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min; c.second = s
    return LocalTime.calendar.date(from: c)!.millis
}

func hours(_ ms: Millis) -> Int { LocalTime.calendar.component(.hour, from: Date(millis: ms)) }
func minutes(_ ms: Millis) -> Int { LocalTime.calendar.component(.minute, from: Date(millis: ms)) }
func dayOfMonth(_ ms: Millis) -> Int { LocalTime.calendar.component(.day, from: Date(millis: ms)) }

let HOUR: Double = 3_600_000

func makeProtocol(
    id: String = "p1", profileId: String = "me", peptideId: String = "x", name: String = "x",
    active: Bool = true, startedAt: Millis, endedAt: Millis? = nil, doseMcg: Double = 1000,
    route: Route = .subcutaneous, schedule: Schedule, scheduleChangedAt: Millis? = nil,
    titration: [TitrationStep]? = nil, titrationAutoAdvance: Bool = false,
    phases: [ProtocolPhase]? = nil, sites: [InjectionSite]? = nil
) -> DoseProtocol {
    DoseProtocol(id: id, profileId: profileId, peptideId: peptideId, name: name, active: active,
                 startedAt: startedAt, endedAt: endedAt, doseMcg: doseMcg, route: route, schedule: schedule,
                 scheduleChangedAt: scheduleChangedAt, titration: titration,
                 titrationAutoAdvance: titrationAutoAdvance, phases: phases, sites: sites)
}

func isClose(_ a: Double, _ b: Double, digits: Int = 2) -> Bool {
    // vitest toBeCloseTo: |a - b| < 10^-digits / 2
    abs(a - b) < pow(10, Double(-digits)) / 2
}

/// The original's deterministic LCG.
struct LCG {
    var s: UInt32
    init(_ seed: UInt32) { s = seed }
    mutating func next() -> Double {
        s = s &* 1664525 &+ 1013904223
        return Double(s) / 4294967296
    }
}
