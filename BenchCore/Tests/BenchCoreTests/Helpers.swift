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

/// A file under Tests/BenchCoreTests/Fixtures, read from the source tree.
func fixture(_ name: String) -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    return try! Data(contentsOf: url)
}

extension CanonicalRecord {
    var at: Millis { switch self { case .dose(let at, _, _, _, _, _), .weight(let at, _, _): at } }
    var sourceRow: Int { switch self { case .dose(_, _, _, _, _, let r), .weight(_, _, let r): r } }
    var isDose: Bool { if case .dose = self { true } else { false } }
    var label: String? { if case .dose(_, let l, _, _, _, _) = self { l } else { nil } }
    var doseMcg: Double? { if case .dose(_, _, let d, _, _, _) = self { d } else { nil } }
    var site: InjectionSite? { if case .dose(_, _, _, let s, _, _) = self { s } else { nil } }
    var notes: String? { if case .dose(_, _, _, _, let n, _) = self { n } else { nil } }
    var weightKg: Double? { if case .weight(_, let w, _) = self { w } else { nil } }
}

func month(_ ms: Millis) -> Int { LocalTime.calendar.component(.month, from: Date(millis: ms)) }
func year(_ ms: Millis) -> Int { LocalTime.calendar.component(.year, from: Date(millis: ms)) }

import Compression

/// Raw DEFLATE, for building zip and PDF fixtures.
func deflateRaw(_ input: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: input.count + 1024)
    let n = compression_encode_buffer(&out, out.count, input, input.count, nil, COMPRESSION_ZLIB)
    return Array(out.prefix(n))
}

/// A zlib stream: header, DEFLATE, Adler-32.
func zlibStream(_ input: [UInt8]) -> [UInt8] {
    var a: UInt32 = 1, b: UInt32 = 0
    for byte in input { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
    let adler = b << 16 | a
    return [0x78, 0x9C] + deflateRaw(input) + [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
}

/// A minimal zip; even-numbered entries are deflated, odd ones stored. CRCs are
/// left zero, which the reader does not check.
func zipOf(_ files: [(String, String)]) -> [UInt8] {
    var body: [UInt8] = [], central: [UInt8] = []
    func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
    func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16(v >> 16 & 0xFFFF) }
    for (i, (name, text)) in files.enumerated() {
        let raw = Array(text.utf8), nameBytes = Array(name.utf8)
        let method = i % 2 == 0 ? 8 : 0
        let data = method == 8 ? deflateRaw(raw) : raw
        let offset = body.count
        body += le32(0x0403_4b50) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0) + le32(0)
            + le32(data.count) + le32(raw.count) + le16(nameBytes.count) + le16(0) + nameBytes + data
        central += le32(0x0201_4b50) + le16(20) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0) + le32(0)
            + le32(data.count) + le32(raw.count) + le16(nameBytes.count) + le16(0) + le16(0) + le16(0) + le16(0)
            + le32(0) + le32(offset) + nameBytes
    }
    let eocd = le32(0x0605_4b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count) + le32(central.count) + le32(body.count) + le16(0)
    return body + central + eocd
}
