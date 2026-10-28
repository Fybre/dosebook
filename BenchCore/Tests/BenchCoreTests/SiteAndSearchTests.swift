import Foundation
import Testing
@testable import BenchCore

@Suite struct SiteAndSearchTests {
    @Test func neverSitesComeOutOfWhatIsAllowed() {
        #expect(allowedSites(pinned: nil, never: []) == nil)
        #expect(allowedSites(pinned: [.thighL], never: []) == [.thighL])
        let all = allowedSites(pinned: nil, never: [.armL, .armR])
        #expect(all?.count == InjectionSite.allCases.count - 2 && all?.contains(.armL) == false)
        #expect(allowedSites(pinned: [.thighL, .armL], never: [.armL]) == [.thighL])
        // Every pin excluded: the pins give way, never the exclusion.
        let fallback = allowedSites(pinned: [.armL], never: [.armL])
        #expect(fallback?.contains(.armL) == false && fallback?.isEmpty == false)
    }

    @Test func suggestionsAvoidExcludedSites() {
        var d = AppData()
        d.settings.neverInjectSites = [.abdomenUL, .abdomenUM, .abdomenUR]
        let p = makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), schedule: Schedule(kind: .daily, timeOfDay: "08:00"))
        let site = suggestSite([], local(2026, 7, 3), allowed: d.allowedSites(for: p))
        #expect(![InjectionSite.abdomenUL, .abdomenUM, .abdomenUR].contains(site))
    }

    @Test func neverSitesRoundTripThroughSettings() {
        var s = Settings()
        s.neverInjectSites = [.gluteR, .armL]
        #expect(s.neverInjectSites == [.armL, .gluteR].sorted { InjectionSite.allCases.firstIndex(of: $0)! < InjectionSite.allCases.firstIndex(of: $1)! })
        s.neverInjectSites = []
        #expect(s.extra["iosNeverSites"] == nil)
    }

    @Test func searchFindsEveryWordAnywhere() {
        var l = DoseLog(id: "1", profileId: "", peptideId: "bpc-157", at: local(2026, 7, 3), doseMcg: 250, route: .subcutaneous, site: .thighL)
        l.notes = "Felt a bit sore"
        #expect(logMatches(l, query: "", peptideName: "BPC-157"))
        #expect(logMatches(l, query: "bpc thigh", peptideName: "BPC-157"))
        #expect(logMatches(l, query: "SORE", peptideName: "BPC-157"))
        #expect(!logMatches(l, query: "bpc glute", peptideName: "BPC-157"))
        #expect(!logMatches(l, query: "skipped", peptideName: "BPC-157"))
    }

    @Test func vialHistoryCountsOnlyItsOwnDoses() {
        var d = AppData()
        _ = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 250, schedule: Schedule(kind: .daily, timeOfDay: "08:00")))
        let id = d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2))
        _ = d.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: local(2026, 7, 2, 8), doseMcg: 250, route: .subcutaneous, vialId: id))
        _ = d.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: local(2026, 7, 3, 8), doseMcg: 250, route: .subcutaneous, vialId: id))
        _ = d.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: local(2026, 7, 3, 20), doseMcg: 250, route: .subcutaneous, vialId: "other"))
        let v = d.vials.first { $0.id == id }!
        let h = vialHistory(d, v, nowMs: local(2026, 7, 4))
        #expect(h.doses.count == 2 && h.doses.first?.at == local(2026, 7, 3, 8))
        #expect(h.averageMcg == 250 && h.firstAt == local(2026, 7, 2, 8))
        #expect(h.remainingMcg == 4500 && h.daysLeft == 18)
    }
}

@Suite struct WeightSourceTests {
    @Test func theProfileFollowsTheLatestWeighIn() {
        var d = AppData()
        let pid = d.activeProfileId
        d.updateProfile(pid) { $0.weightKg = 90 }
        #expect(d.latestWeight(profileId: pid) == WeightReading(kg: 90, at: nil, fromHealth: false))
        d.addMeasurement(BodyMeasurement(id: "", profileId: "", at: local(2026, 7, 1), weightKg: 88))
        d.addMeasurement(BodyMeasurement(id: "", profileId: "", at: local(2026, 7, 5), weightKg: 87, source: .healthConnect))
        #expect(d.latestWeight(profileId: pid) == WeightReading(kg: 87, at: local(2026, 7, 5), fromHealth: true))
        #expect(d.profiles.first { $0.id == pid }?.weightKg == 87)
        // An older reading added later does not take over.
        d.addMeasurement(BodyMeasurement(id: "", profileId: "", at: local(2026, 6, 1), weightKg: 95))
        #expect(d.profiles.first { $0.id == pid }?.weightKg == 87)
        d.removeMeasurement(d.measurements.first { $0.weightKg == 87 }!.id)
        #expect(d.profiles.first { $0.id == pid }?.weightKg == 88)
    }
}

@Suite struct ImportKeepsDeviceSettingsTests {
    @Test func aBackupThatKnowsNothingOfThemDoesNotResetThem() {
        var d = AppData()
        d.settings.neverInjectSites = [.armL]
        d.settings.stockSort = .alphabetical
        d.settings.protocolSort = .alphabetical
        d.settings.lowStockUnit = .days
        // A backup from before any of that existed.
        d.importData(AppData())
        #expect(d.settings.neverInjectSites == [.armL])
        #expect(d.settings.stockSort == .alphabetical && d.settings.protocolSort == .alphabetical && d.settings.lowStockUnit == .days)
    }

    @Test func aBackupThatDoesSetThemWins() {
        var d = AppData()
        d.settings.neverInjectSites = [.armL]
        var backup = AppData()
        backup.settings.neverInjectSites = [.gluteR]
        d.importData(backup)
        #expect(d.settings.neverInjectSites == [.gluteR])
    }
}
