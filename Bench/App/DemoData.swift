#if DEBUG
import Foundation
import BenchCore
import BenchStore

/// Sample data for screenshots and manual checks: launch with `-demo`.
/// Debug builds only, held in memory, never written to iCloud.
@MainActor
enum DemoData {
    static func seed(_ store: AppStore) {
        let now = nowMillis()
        let day = DAY_MS
        store.mutate { d in
            d.updateSettings { $0.currency = "EUR" }
            let tirz = d.addProtocol(DoseProtocol(id: "", profileId: "", peptideId: "tirzepatide", name: "Tirzepatide weekly",
                                                  startedAt: startOfLocalDay(now - 40 * day) + 8 * HOUR_MS, doseMcg: 5000, route: .subcutaneous,
                                                  schedule: Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "08:00"),
                                                  phases: [ProtocolPhase(step: 1, doseMcg: 2500, weeks: 4), ProtocolPhase(step: 2, doseMcg: 5000, weeks: 4)]))
            let bpc = d.addProtocol(DoseProtocol(id: "", profileId: "", peptideId: "bpc-157", name: "BPC-157 recovery",
                                                 startedAt: startOfLocalDay(now - 10 * day), doseMcg: 500, route: .subcutaneous,
                                                 schedule: Schedule(kind: .daily, timesOfDay: ["07:00", "19:00"]),
                                                 sites: [.abdomenUL, .abdomenUR, .thighL]))
            d.addVial(Vial(id: "", profileId: "", peptideId: "tirzepatide", strengthMg: 30, state: .reconstituted, supplier: "Demo Labs",
                           cost: 120, currency: "EUR", reconstitutedAt: now - 20 * day, diluentMl: 3, diluent: .bacteriostatic, budAt: now + 8 * day))
            d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, cost: 35, currency: "EUR",
                           reconstitutedAt: now - 5 * day, diluentMl: 2, diluent: .bacteriostatic, budAt: now + 23 * day))
            d.addOrder([Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .sealed, cost: 35, currency: "EUR"),
                        Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .sealed, cost: 35, currency: "EUR")],
                       shippingCost: 12, currency: "EUR")
            d.addDiluent(DiluentBottle(id: "", profileId: "", kind: .bacteriostatic, volumeMl: 30, drawnMl: 5, state: .open, budAt: now + 20 * day))
            for w in 0..<6 {
                let at = startOfLocalDay(now - 40 * day) + Double(w * 7) * day + 8 * HOUR_MS
                if at < now { d.addLog(DoseLog(id: "", profileId: "", protocolId: tirz, peptideId: "tirzepatide", at: at, doseMcg: w < 4 ? 2500 : 5000, route: .subcutaneous, site: [.abdomenLL, .abdomenLR, .thighR][w % 3], feeling: 3 + w % 3)) }
            }
            let sites: [InjectionSite] = [.abdomenUL, .abdomenUR, .thighL]
            for i in 0..<16 {
                let at = startOfLocalDay(now - 9 * day) + Double(i / 2) * day + (i % 2 == 0 ? 7.1 : 19.2) * HOUR_MS
                if at < now { d.addLog(DoseLog(id: "", profileId: "", protocolId: bpc, peptideId: "bpc-157", at: at, doseMcg: 250, route: .subcutaneous, site: sites[i % 3])) }
            }
            for i in 0..<8 {
                d.addMeasurement(BodyMeasurement(id: "", profileId: "", at: now - Double(40 - i * 5) * day, weightKg: 98 - Double(i) * 0.7))
            }
            for i in 0..<12 {
                _ = d.saveCheckIn(at: now - Double(i) * day, ratings: ["energy": Double(3 + i % 3), "mood": 4, "sleep": Double(2 + i % 4), "appetite": 2, "foodNoise": Double(1 + i % 2)], notes: i == 3 ? "Slept badly after the late dose." : nil, now: now)
            }
            d.addLab(LabResult(id: "", profileId: "", at: now - 60 * day, markerId: "hba1c", value: 6.1))
            d.addLab(LabResult(id: "", profileId: "", at: now - 5 * day, markerId: "hba1c", value: 5.6))
        }
    }
}
#endif
