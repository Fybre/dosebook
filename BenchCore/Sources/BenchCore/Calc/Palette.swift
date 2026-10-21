import Foundation

// Port of src/lib/calc/palette.ts. One colour per thing, agreed across every
// screen: a colour belongs to a position, handed out in list order, so adding a
// protocol shifts colours everywhere at once rather than in one place.

public let SERIES_TONES: [Tone] = [.mint, .grape, .tangerine, .sky, .rose, .leaf]

public struct ColorSubject: Equatable, Sendable {
    public var protocolId: String
    public var peptideId: String?
    /// The parts a blend is drawn as; empty for an ordinary compound.
    public var componentKeys: [String]
    public init(protocolId: String, peptideId: String? = nil, componentKeys: [String] = []) {
        self.protocolId = protocolId; self.peptideId = peptideId; self.componentKeys = componentKeys
    }
}

public struct Palette: Equatable, Sendable {
    /// A protocol id, or "protocolId:component".
    public var byKey: [String: Tone] = [:]
    /// A blend's first component's colour.
    public var byProtocol: [String: Tone] = [:]
    /// Only compounds exactly one active protocol runs.
    public var byPeptide: [String: Tone] = [:]
}

public func assignColors(_ subjects: [ColorSubject]) -> Palette {
    var p = Palette()
    var next = 0
    var runners: [String: Int] = [:]
    for s in subjects { if let id = s.peptideId { runners[id, default: 0] += 1 } }
    for s in subjects {
        let keys = s.componentKeys.isEmpty ? [s.protocolId] : s.componentKeys.map { "\(s.protocolId):\($0)" }
        for key in keys {
            let tone = SERIES_TONES[next % SERIES_TONES.count]
            next += 1
            p.byKey[key] = tone
            if p.byProtocol[s.protocolId] == nil {
                p.byProtocol[s.protocolId] = tone
                if let id = s.peptideId, runners[id] == 1 { p.byPeptide[id] = tone }
            }
        }
    }
    return p
}

/// The subjects the app is running today, built the same way wherever asked.
public func colorSubjects(_ protocols: [DoseProtocol], resolve: @escaping (String) -> Peptide?, nowMs: Millis) -> [ColorSubject] {
    protocols.map { p in
        let peptide = resolve(p.peptideId)
        let parts = peptide.map { isBlend($0) ? decomposeDose($0, scheduledDoseMcg(p, nowMs), resolve: resolve, dosesPerWeek: protocolDosesPerWeek(p, nowMs)) : [] } ?? []
        return ColorSubject(protocolId: p.id, peptideId: p.peptideId,
                            componentKeys: modellableComponents(parts).map { $0.peptideId ?? $0.name })
    }
}

/// The colour for a dose already taken: its protocol's, else its compound's when unambiguous.
public func doseColor(_ palette: Palette, protocolId: String?, peptideId: String) -> Tone? {
    protocolId.flatMap { palette.byProtocol[$0] } ?? palette.byPeptide[peptideId]
}
