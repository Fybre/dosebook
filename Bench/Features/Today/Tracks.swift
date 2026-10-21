import Foundation
import BenchCore

/// Everything Today knows about one active protocol at one instant.
struct Track: Identifiable {
    var protocol_: DoseProtocol
    var peptide: Peptide?
    var doses: [DoseEvent]
    var targetMcg: Double
    var referenceMcg: Double
    var due: DueStatus
    var stock: Stock
    var snap: LevelSnapshot?
    var blendParts: [ComponentDose]
    var curve: Curve?
    var lastLog: DoseLog?
    var lastLoggedAt: Millis?
    var phase: TimelinePhase?
    var supplyDays: Double?
    var perDay: Int
    var tone: Tone
    var id: String { protocol_.id }
    var name: String { peptide?.name ?? protocol_.peptideId }
}

/// A line on the levels chart: a compound, or one component of a blend.
struct PkSeries: Identifiable {
    var id: String
    var label: String
    var doses: [DoseEvent]
    var params: CurveParams
    var referenceMcg: Double
    var basis: CurveBasis?
    var tone: Tone
}

enum TodayModel {
    static func tracks(_ data: AppData, now: Millis, palette: Palette) -> [Track] {
        let mine = data.mine
        return mine.protocols.filter(\.active).map { p in
            let peptide = data.peptide(p.peptideId)
            let answered = mine.logs.filter { $0.protocolId == p.id || $0.peptideId == p.peptideId }
            let taken = answered.filter { !$0.isSkipped }
            let doses = taken.map { DoseEvent(at: $0.at, amountMcg: $0.doseMcg, vialId: $0.vialId) }
            let lastLog = taken.max { $0.at < $1.at }
            let target = scheduledDoseMcg(p, now)
            // A skip answers the slot, so it counts for what is due; it is not a dose for the curve.
            let due = dueStatus(p, now, DueOptions(lastLoggedAt: answered.map(\.at).max()))
            let stock = stockFor(mine.vials, p.peptideId, target, now, containerForDose(peptide?.preparation, p.route))
            let reference = (lastLog?.doseMcg).flatMap { $0 > 0 ? $0 : nil } ?? (target > 0 ? target : 1)
            let parts = peptide.map { isBlend($0) ? decomposeDose($0, target, resolve: { data.peptide($0) }, dosesPerWeek: protocolDosesPerWeek(p, now)) : [] } ?? []
            let curve = peptide.flatMap { curveFor($0, yours: data.halfLifeOverrides[$0.id]) }
            let snap = curve.flatMap { isMeasuredInPeople($0.basis) ? snapshot(now, doses, $0.params, reference) : nil }
            return Track(protocol_: p, peptide: peptide, doses: doses, targetMcg: target, referenceMcg: reference, due: due,
                         stock: stock, snap: snap, blendParts: parts, curve: curve, lastLog: lastLog, lastLoggedAt: lastLog?.at,
                         phase: peptide.flatMap { timelinePhaseAt($0, hoursSince(lastLog?.at, now) ?? -1) },
                         supplyDays: daysOfSupplyForProtocol(stock, p, now),
                         perDay: dosesPerDoseDay(phaseSpanAt(p, now)?.schedule ?? p.schedule),
                         tone: palette.byProtocol[p.id] ?? .neutral)
        }
    }

    static func series(_ tracks: [Track], palette: Palette) -> [PkSeries] {
        var out: [PkSeries] = []
        for track in tracks {
            let parts = modellableComponents(track.blendParts)
            if !parts.isEmpty {
                for part in parts {
                    let id = "\(track.id):\(part.peptideId ?? part.name)"
                    out.append(PkSeries(id: id, label: "\(part.name) · in \(track.name)",
                                        doses: track.doses.map { DoseEvent(at: $0.at, amountMcg: $0.amountMcg * part.fraction, vialId: $0.vialId) },
                                        params: CurveParams(halfLifeHours: part.peptide!.halfLifeHours!, tmaxHours: part.peptide!.tmaxHours),
                                        referenceMcg: part.mcg > 0 ? part.mcg : 1, basis: nil, tone: palette.byKey[id] ?? .neutral))
                }
                continue
            }
            if let curve = track.curve {
                out.append(PkSeries(id: track.id, label: track.name, doses: track.doses, params: curve.params,
                                    referenceMcg: track.referenceMcg, basis: curve.basis, tone: palette.byKey[track.id] ?? .neutral))
            }
        }
        return out
    }
}
