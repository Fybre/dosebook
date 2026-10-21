import Foundation
import Testing
@testable import BenchCore

// Ports of custom.test.ts and infer.test.ts (the Shotsy-fixture half of the
// infer tests lives with the import tests).

private func draft(name: String = "Mystery peptide", category: PeptideCategory = .repair, routes: [Route] = [.subcutaneous],
                   preparation: Preparation = .powder, aka: String? = nil, halfLifeHours: Double? = nil, doseLowMcg: Double? = nil,
                   doseHighMcg: Double? = nil, frequency: String? = nil, perWeek: Double? = nil, vialSizeMg: Double? = nil,
                   iuPerMg: Double? = nil) -> CustomDraft {
    CustomDraft(name: name, category: category, aka: aka, halfLifeHours: halfLifeHours, routes: routes, preparation: preparation,
                doseLowMcg: doseLowMcg, doseHighMcg: doseHighMcg, frequency: frequency, perWeek: perWeek, vialSizeMg: vialSizeMg, iuPerMg: iuPerMg)
}
private let PEPTIDES = Library.peptides

@Suite struct CustomTests {
    @Test func slugs() {
        #expect(slugifyCompound("Mystery peptide") == "custom-mystery-peptide" && isCustomId(slugifyCompound("anything")))
        #expect(slugifyCompound("BPC-157") == "custom-bpc-157")
        #expect(PEPTIDES.allSatisfy { !$0.id.hasPrefix(CUSTOM_PREFIX) })
        #expect(slugifyCompound("  Péptide  X²  ") == "custom-peptide-x2")
        #expect(slugifyCompound("AOD, 9604") == "custom-aod-9604")
        #expect(slugifyCompound("!!!") == "custom-compound")
    }

    @Test func validation() {
        #expect(validateDraft(draft(), existing: PEPTIDES).isEmpty)
        #expect(validateDraft(draft(name: "   "), existing: PEPTIDES)[0].field == .name)
        let dup = validateDraft(draft(name: "Tirzepatide"), existing: PEPTIDES)
        #expect(dup[0].field == .name && dup[0].message.contains("already in the library"))
        #expect(validateDraft(draft(name: "tirzepatide"), existing: PEPTIDES).count == 1)
        let mine = draftToPeptide(draft())
        #expect(validateDraft(draft(), existing: PEPTIDES + [mine])[0].field == .name)
        #expect(validateDraft(draft(name: "Mystery  Peptide!"), existing: PEPTIDES + [mine])[0].message.contains("already have a compound"))
        #expect(validateDraft(draft(routes: []), existing: PEPTIDES)[0].field == .routes)
        #expect(validateDraft(draft(doseLowMcg: 500, doseHighMcg: 100), existing: PEPTIDES)[0].field == .doseHighMcg)
        #expect(validateDraft(draft(doseLowMcg: 500, doseHighMcg: 500), existing: PEPTIDES).isEmpty)
        #expect(validateDraft(draft(perWeek: 0), existing: PEPTIDES)[0].field == .perWeek)
        #expect(validateDraft(draft(halfLifeHours: 0), existing: PEPTIDES)[0].field == .halfLifeHours)
        #expect(validateDraft(draft(iuPerMg: 0), existing: PEPTIDES)[0].field == .iuPerMg)
        #expect(validateDraft(draft(vialSizeMg: 0), existing: PEPTIDES)[0].field == .vialSizeMg)
        #expect(validateDraft(draft(doseLowMcg: -5), existing: PEPTIDES)[0].field == .doseLowMcg)
        #expect(validateDraft(draft(halfLifeHours: 4000, doseLowMcg: 1, doseHighMcg: 5_000_000), existing: PEPTIDES).isEmpty)
    }

    @Test func toPeptide() {
        let p = draftToPeptide(draft(halfLifeHours: 6))
        #expect(p.id == "custom-mystery-peptide" && p.name == "Mystery peptide" && p.category == .repair && p.halfLifeHours == 6 && p.routes == [.subcutaneous])
        let bare = draftToPeptide(draft())
        #expect(bare.halfLifeHours == nil && !(bare.halfLifeNote ?? "").isEmpty)
        let ranged = draftToPeptide(draft(doseLowMcg: 250, doseHighMcg: 500))
        #expect(ranged.doseRanges[0].evidence == .anecdotal && ranged.doseRanges[0].note!.lowercased().contains("not from any published source"))
        #expect(bare.citations.isEmpty && !(bare.cautionBanner ?? "").isEmpty && bare.doseRanges.isEmpty)
        #expect(draftToPeptide(draft(aka: "MP, Compound X, ")).aka == ["MP", "Compound X"])
        #expect(draftToPeptide(draft(preparation: .powder)).reconstitutedDays == 28 && draftToPeptide(draft(preparation: .solution)).reconstitutedDays == nil)
        #expect(draftToPeptide(draft(iuPerMg: 3)).iuPerMg == 3 && bare.iuPerMg == nil)
        let d = draft(name: "Round trip", doseLowMcg: 100, doseHighMcg: 200, perWeek: 3)
        #expect(validateDraft(d, existing: PEPTIDES).isEmpty)
        let r = draftToPeptide(d).doseRanges[0]
        #expect(r.lowMcg == 100 && r.highMcg == 200 && r.perWeek == 3)
    }

    @Test func editing() {
        func made(name: String = "SS-31", aka: String? = nil, halfLifeHours: Double? = nil) -> Peptide {
            draftToPeptide(draft(name: name, category: .longevity, aka: aka, halfLifeHours: halfLifeHours, doseLowMcg: 10_000, doseHighMcg: 10_000,
                                 frequency: "once daily", perWeek: 7, vialSizeMg: 50))
        }
        let d = peptideToDraft(made(aka: "Elamipretide, MTP-131", halfLifeHours: 4))
        #expect(d.name == "SS-31" && d.category == .longevity && d.halfLifeHours == 4 && d.routes == [.subcutaneous])
        #expect(d.doseLowMcg == 10_000 && d.perWeek == 7 && d.vialSizeMg == 50 && d.aka == "Elamipretide, MTP-131")
        let p = made(halfLifeHours: 4)
        #expect(draftToPeptide(peptideToDraft(p)) == p)
        let bare = draftToPeptide(draft(name: "Mystery"))
        let bd = peptideToDraft(bare)
        #expect(bd.halfLifeHours == nil && bd.doseLowMcg == nil && draftToPeptide(bd) == bare)
        let mine = made(name: "Something Of My Own")
        #expect(validateDraft(peptideToDraft(mine), existing: PEPTIDES + [mine], editingId: mine.id).isEmpty)
        #expect(!validateDraft(peptideToDraft(mine), existing: PEPTIDES + [mine]).isEmpty)
        let other = draftToPeptide(draft(name: "Taken"))
        var renamed = peptideToDraft(mine); renamed.name = "Taken"
        #expect(validateDraft(renamed, existing: PEPTIDES + [mine, other], editingId: mine.id).map(\.field).contains(.name))
        let ss = made(name: "SS-31")
        #expect(PEPTIDES.contains { $0.name == "SS-31" })
        #expect(validateDraft(peptideToDraft(ss), existing: PEPTIDES + [ss], editingId: ss.id).isEmpty)
        #expect(curveFor(mine) == nil)
        var withH = peptideToDraft(mine); withH.halfLifeHours = 4
        #expect(curveFor(draftToPeptide(withH)) == Curve(params: CurveParams(halfLifeHours: 4), basis: .published))
    }
}

private func resolve(_ id: String) -> Peptide? { Library.byId[id] }

@Suite struct InferTests {
    let START = local(2026, 2, 8, 13)
    func l(_ at: Millis, peptideId: String = "tirzepatide", doseMcg: Double = 10_000, site: InjectionSite? = nil, skipped: Bool? = nil) -> DoseLog {
        DoseLog(id: UUID().uuidString, profileId: "me", peptideId: peptideId, at: at, doseMcg: doseMcg, route: .subcutaneous, site: site, skipped: skipped)
    }
    func series(_ n: Int, _ every: Double, _ start: Millis, peptideId: String = "tirzepatide", doseMcg: Double = 10_000, site: InjectionSite? = nil) -> [DoseLog] {
        (0..<n).map { l(start + Double($0) * every * DAY_MS, peptideId: peptideId, doseMcg: doseMcg, site: site) }
    }
    func days(_ ds: [Double]) -> [DoseLog] { ds.map { l(START + $0 * DAY_MS) } }

    @Test func schedules() {
        let weekly = inferProtocol(series(10, 7, START), resolve: resolve)!
        #expect(weekly.schedule.kind == .daysOfWeek && weekly.schedule.daysOfWeek == [localWeekday(START)] && weekly.confidence == .clear)
        let daily = inferProtocol(series(14, 1, START), resolve: resolve)!
        #expect(daily.schedule.kind == .daily && daily.confidence == .clear)
        let third = inferProtocol(series(10, 3, START), resolve: resolve)!
        #expect(third.schedule.kind == .intervalDays && third.schedule.intervalDays == 3 && third.confidence == .clear)
        let drift = inferProtocol(days([0, 7, 14.1, 20.9, 28]), resolve: resolve)!
        #expect(drift.schedule.kind == .daysOfWeek && drift.confidence == .clear)
        let gap = inferProtocol(days([0, 7, 14, 21, 60, 67, 74, 81]), resolve: resolve)!
        #expect(gap.schedule.kind == .daysOfWeek && gap.confidence == .clear)
        #expect(inferProtocol(days([0, 3, 11, 12, 30, 31]), resolve: resolve)!.confidence == .rough)
        let one = inferProtocol([l(START)], resolve: resolve)!
        #expect(one.confidence == .rough && one.schedule.kind == .daysOfWeek && one.doseCount == 1)
        #expect(inferProtocol(days([0, 0.1, 7, 14, 21]), resolve: resolve)!.schedule.kind == .daysOfWeek)
    }

    @Test func doseSitesDates() {
        #expect(inferProtocol([l(START, doseMcg: 2500), l(START + 7 * DAY_MS, doseMcg: 5000), l(START + 14 * DAY_MS, doseMcg: 10_000)], resolve: resolve)!.doseMcg == 10_000)
        let rot = series(12, 7, START, site: .abdomenUL) + [l(START + 84 * DAY_MS, site: .thighL), l(START + 91 * DAY_MS, site: .thighR)]
        #expect(inferProtocol(rot, resolve: resolve, siteWindow: 3)!.sites.map(\.rawValue).sorted() == ["abdomen-ul", "thigh-l", "thigh-r"])
        #expect(inferProtocol(series(5, 7, START), resolve: resolve)!.sites.isEmpty)
        let p = inferProtocol(series(5, 7, START), resolve: resolve)!
        #expect(p.startedAt == START && p.lastAt == START + 28 * DAY_MS)
        #expect(inferProtocol(series(6, 7, local(2026, 2, 8, 9, 40)), resolve: resolve)!.schedule.timeOfDay == "09:30")
        #expect(inferProtocol(series(6, 7, local(2026, 2, 8, 0, 0)), resolve: resolve)!.schedule.timeOfDay == nil)
        let odd = series(6, 7, local(2026, 2, 8, 13)) + [l(local(2026, 6, 1, 3, 15)), l(local(2026, 6, 8, 22, 45))]
        #expect(inferProtocol(odd, resolve: resolve)!.schedule.timeOfDay == "13:00")
    }

    @Test func refusalsAndChoice() {
        #expect(inferProtocol([], resolve: resolve) == nil)
        #expect(inferProtocol([l(START, skipped: true)], resolve: resolve) == nil)
        #expect(inferProtocol([l(START, doseMcg: 0)], resolve: resolve) == nil)
        #expect(inferProtocol([l(START, peptideId: "nope")], resolve: resolve) == nil)
        let recent = series(5, 7, START, peptideId: "semaglutide", doseMcg: 1000) + [l(START + 40 * DAY_MS)]
        #expect(inferProtocol(recent, resolve: resolve)!.peptideId == "tirzepatide")
        let interleaved = series(5, 7, START) + series(5, 7, START + 3 * DAY_MS, peptideId: "semaglutide", doseMcg: 1000) + [l(START + 35 * DAY_MS)]
        let p = inferProtocol(interleaved, resolve: resolve)!
        #expect(p.peptideId == "tirzepatide" && p.schedule.kind == .daysOfWeek)
        let all = inferAllProtocols(series(4, 7, START, peptideId: "semaglutide", doseMcg: 1000) + series(4, 7, START + 40 * DAY_MS), resolve: resolve)
        #expect(all.map(\.peptideId) == ["tirzepatide", "semaglutide"])
        #expect(inferAllProtocols([], resolve: resolve).isEmpty)
    }
}
