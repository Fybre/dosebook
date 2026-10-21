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

/// The original tests' `vial({ id, ...over })`: klow, 80 mg, sealed, owned by "me".
func vial(_ id: String = "a", peptideId: String = "klow", strengthMg: Double = 80, state: VialState = .sealed,
          diluentMl: Double? = nil, drawnMcg: Double? = nil, budAt: Millis? = nil, expiresAt: Millis? = nil,
          cost: Double? = nil, currency: String? = nil, orderId: String? = nil, supplier: String? = nil,
          acquiredAt: Millis? = nil, container: ContainerKind? = nil, mgPerTablet: Double? = nil,
          mlPerSpray: Double? = nil, reconstitutedAt: Millis? = nil) -> Vial {
    Vial(id: id, profileId: "me", peptideId: peptideId, strengthMg: strengthMg, state: state, supplier: supplier,
         cost: cost, currency: currency, orderId: orderId, acquiredAt: acquiredAt, expiresAt: expiresAt,
         reconstitutedAt: reconstitutedAt, diluentMl: diluentMl, drawnMcg: drawnMcg, budAt: budAt,
         container: container, mgPerTablet: mgPerTablet, mlPerSpray: mlPerSpray)
}

extension Vial {
    func with(_ change: (inout Vial) -> Void) -> Vial { var v = self; change(&v); return v }
}
