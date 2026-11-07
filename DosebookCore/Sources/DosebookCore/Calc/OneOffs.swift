import Foundation

/// A compound taken recently with no active protocol behind it: a one-off dose logged by hand,
/// or the tail of a protocol since stopped. It is in the body whether or not it was planned.
public struct OneOffCompound: Equatable, Sendable, Identifiable {
    public var peptideId: String
    /// Every logged dose of it, newest first. Skipped ones never count.
    public var doses: [DoseLog]
    public var id: String { peptideId }
    public var last: DoseLog { doses[0] }
}

/// Compounds with a dose in the last `lookbackDays` and no active protocol, most recent first.
public func oneOffCompounds(_ data: AppData, nowMs: Millis, lookbackDays: Double = 14) -> [OneOffCompound] {
    let mine = data.mine
    let planned = Set(mine.protocols.filter(\.active).map(\.peptideId))
    let since = nowMs - lookbackDays * DAY_MS
    var byCompound: [String: [DoseLog]] = [:]
    for l in mine.logs where !l.isSkipped && l.doseMcg > 0 && l.at <= nowMs {
        byCompound[l.peptideId, default: []].append(l)
    }
    return byCompound.compactMap { id, doses -> OneOffCompound? in
        guard !planned.contains(id) else { return nil }
        let newestFirst = doses.stableSorted { $0.at > $1.at }
        return newestFirst[0].at >= since ? OneOffCompound(peptideId: id, doses: newestFirst) : nil
    }
    .sorted { $0.last.at != $1.last.at ? $0.last.at > $1.last.at : $0.peptideId < $1.peptideId }
}

/// Colour subjects for the one-offs, to go after the protocols' so no protocol's colour moves.
public func oneOffColorSubjects(_ oneOffs: [OneOffCompound], resolve: @escaping (String) -> Peptide?) -> [ColorSubject] {
    oneOffs.map { o in
        let peptide = resolve(o.peptideId)
        let parts = peptide.map { isBlend($0) ? decomposeDose($0, o.last.doseMcg, resolve: resolve) : [] } ?? []
        return ColorSubject(protocolId: "oneoff:\(o.peptideId)", peptideId: o.peptideId,
                            componentKeys: modellableComponents(parts).map { $0.peptideId ?? $0.name })
    }
}
