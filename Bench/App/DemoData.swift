#if DEBUG
import Foundation
import BenchCore
import BenchStore

/// Sample data for screenshots and manual checks: launch with `-demo`.
/// Debug builds only, held in memory, never written to iCloud.
@MainActor
enum DemoData {
    /// `-demoLarge`: three years of twice-daily history on top, for performance checks.
    static func seedLarge(_ store: AppStore) {
        let now = nowMillis(), day = DAY_MS
        store.mutate { d in
            let bpc = d.protocols.first { $0.peptideId == "bpc-157" }?.id
            for i in 1...(3 * 365) {
                let at = startOfLocalDay(now) - Double(i) * day
                for h in [8.0, 20.0] {
                    d.logs.append(DoseLog(id: "big-\(i)-\(Int(h))", profileId: d.activeProfileId, protocolId: bpc, peptideId: "bpc-157",
                                          at: at + h * HOUR_MS, doseMcg: 250, route: .subcutaneous, site: [.abdomenUL, .abdomenUR, .thighL][i % 3]))
                }
                d.measurements.append(BodyMeasurement(id: "bigw-\(i)", profileId: d.activeProfileId, at: at + 7 * HOUR_MS, weightKg: 98 + Double(i) / 200))
            }
            d.logs.sort { $0.at > $1.at }
        }
    }

    /// `-seedInjectly a.csv,b.csv,...`: an Injectly export applied as the import screen would,
    /// with ambiguous blend parts settled on the first choice. For reproducing layouts with real data.
    static func seedInjectly(_ store: AppStore, _ paths: [String]) {
        var meds: [InjectlyMedication] = [], history: [CanonicalRecord] = []
        for path in paths {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let table = toTable(parseDelimited(text))
            switch injectlyFileKind(table.headers) {
            case .medications?: meds += parseInjectlyMedications(table)
            case .logs?, .weight?: history += injectlyProfile.read(table.records, table.headers).records
            default: break
            }
        }
        let data = store.data
        var items = planInjectlySetup(meds, peptides: data.allPeptides, activeProtocols: [], logs: history)
        for i in items.indices {
            if case .newBlend(var parts) = items[i].compound {
                for k in parts.indices where parts[k].chosen == nil { parts[k].chosen = parts[k].candidates.last }
                items[i].compound = .newBlend(parts)
            }
        }
        let results = items.map { injectlyResult($0, peptides: data.allPeptides, logs: history) }
        let peptides = data.allPeptides + results.compactMap(\.newPeptide)
        let plan = buildImportPlan(records: history, problems: [], peptides: peptides, existingLogs: [], existingMeasurements: [], blendDoseIsFirstPart: true)
        store.mutate { d in
            for r in results { if let p = r.newPeptide { d.addCustomPeptide(p) }; _ = d.addProtocol(r.protocol_) }
            d.importHistory(logs: plan.doses.map { DoseLog(id: "", profileId: "", peptideId: $0.peptideId, at: $0.at, doseMcg: $0.doseMcg, route: .subcutaneous, site: $0.site) },
                            measurements: plan.weights.map { BodyMeasurement(id: "", profileId: "", at: $0.at, weightKg: $0.weightKg) })
            d.settings.lastBackupAt = nowMillis()
        }
    }

    static func seed(_ store: AppStore) {
        let now = nowMillis()
        let day = DAY_MS
        store.mutate { d in
            d.updateSettings { $0.currency = "EUR" }
            // The demo is for showing the app, so it does not nag about a backup.
            d.updateSettings { $0.lastBackupAt = now; $0.dataChangedAt = now }
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
                // Four days ago nothing was logged at all, so the week strip shows a missed day.
                if at < now && i / 2 != 5 { d.addLog(DoseLog(id: "", profileId: "", protocolId: bpc, peptideId: "bpc-157", at: at, doseMcg: 250, route: .subcutaneous, site: sites[i % 3])) }
            }
            // A custom blend: CJC-1295 without DAC and ipamorelin, 10 mg of each.
            var blend = CustomDraft(name: "CJC/Ipa", category: .blend, doseLowMcg: 200, doseHighMcg: 300, perWeek: 7)
            blend.components = [BlendComponent(peptideId: "cjc-1295-no-dac", name: "CJC-1295 without DAC", mgPerVial: 10),
                                BlendComponent(peptideId: "ipamorelin", name: "Ipamorelin", mgPerVial: 10)]
            let cjcIpa = draftToPeptide(blend)
            d.addCustomPeptide(cjcIpa)
            let gh = d.addProtocol(DoseProtocol(id: "", profileId: "", peptideId: cjcIpa.id, name: "CJC/Ipa nightly",
                                                startedAt: startOfLocalDay(now - 6 * day), doseMcg: 200, route: .subcutaneous,
                                                schedule: Schedule(kind: .daily, timeOfDay: "22:00")))
            d.addVial(Vial(id: "", profileId: "", peptideId: cjcIpa.id, strengthMg: 20, state: .reconstituted, cost: 60, currency: "EUR",
                           reconstitutedAt: now - 6 * day, diluentMl: 2, diluent: .bacteriostatic, budAt: now + 22 * day))
            for i in 0..<6 {
                let at = startOfLocalDay(now - 6 * day) + Double(i) * day + 22 * HOUR_MS
                if at < now && i != 2 { d.addLog(DoseLog(id: "", profileId: "", protocolId: gh, peptideId: cjcIpa.id, at: at, doseMcg: 200, route: .subcutaneous, site: .abdomenLL)) }
            }
            for i in 0..<8 {
                d.addMeasurement(BodyMeasurement(id: "", profileId: "", at: now - Double(40 - i * 5) * day, weightKg: 98 - Double(i) * 0.7))
            }
            // Synthetic vitals give the Health trend review enough dated rows
            // to exercise its comparison layout in screenshots.
            for i in 0..<30 {
                d.recordVitals(dayMs: addLocalDays(startOfLocalDay(now), Double(-i)),
                               sleepHours: 6.8 + Double(i % 5) * 0.15,
                               restingHrBpm: 61 + Double(i % 4))
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

import SwiftUI

extension View {
    /// Debug builds: launch with `-anchor <id>` to scroll a screen to a section for screenshots.
    func debugAnchor(_ proxy: ScrollViewProxy) -> some View {
        #if DEBUG
        onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-anchor"), i + 1 < args.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo(args[i + 1], anchor: .top) }
            }
        }
        #else
        self
        #endif
    }
}
