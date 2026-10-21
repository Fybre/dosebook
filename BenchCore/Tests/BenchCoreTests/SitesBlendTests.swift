import Foundation
import Testing
@testable import BenchCore

// Ports of sites.test.ts and blend.test.ts.

private let NOW: Millis = 1_785_326_400_000
private func slog(_ site: InjectionSite?, _ daysAgo: Double, skipped: Bool = false, route: Route = .subcutaneous, at: Millis? = nil) -> DoseLog {
    DoseLog(id: UUID().uuidString, profileId: "me", peptideId: "x", at: at ?? NOW - daysAgo * DAY_MS, doseMcg: 1,
            route: route, site: site, skipped: skipped)
}
private let ALL = INJECTION_SITES.map(\.id)

@Suite struct SiteUsageTests {
    @Test func cases() {
        let u = siteUsage([], NOW)
        #expect(u.count == INJECTION_SITES.count && u.allSatisfy { $0.lastUsedAt == nil && $0.rested == 1 })
        let thigh = siteUsage([slog(.thighL, 5), slog(.thighL, 1)], NOW).first { $0.site == .thighL }!
        #expect(isClose(thigh.daysSince, 1, digits: 6) && thigh.recentCount == 2)
        #expect(siteUsage([slog(.abdomenUL, 0)], NOW).first { $0.site == .abdomenUL }!.rested == 0)
        #expect(siteUsage([slog(.abdomenUL, 20)], NOW).first { $0.site == .abdomenUL }!.rested == 1)
        #expect(isClose(siteUsage([slog(.abdomenUL, 7)], NOW).first { $0.site == .abdomenUL }!.rested, 0.5, digits: 6))
        #expect(siteUsage([slog(.thighR, 0, skipped: true)], NOW).first { $0.site == .thighR }!.lastUsedAt == nil)
        #expect(siteUsage([slog(nil, 0)], NOW).allSatisfy { $0.lastUsedAt == nil })
        #expect(siteUsage([slog(.armL, 30), slog(.armL, 2)], NOW).first { $0.site == .armL }!.recentCount == 1)
        let sorted = siteUsage([slog(.abdomenUL, 0), slog(.abdomenUR, 10)], NOW)
        #expect(sorted[0].rested >= sorted.last!.rested && sorted.last!.site == .abdomenUL)
    }
}

@Suite struct SuggestSiteTests {
    @Test func cases() {
        #expect(suggestSite(ALL.prefix(9).enumerated().map { slog($1, Double($0)) }, NOW) == ALL[9])
        let all = ALL.enumerated().map { slog($1, Double($0 + 1)) }
        #expect(suggestSite(all, NOW) == ALL.last!)
        #expect(suggestSite(all, NOW) != ALL[0])
        let tie = [slog(.thighL, 3), slog(.thighL, 5), slog(.thighL, 6), slog(.thighR, 3)]
            + ALL.filter { $0 != .thighL && $0 != .thighR }.map { slog($0, 1) }
        #expect(suggestSite(tie, NOW) == .thighR)
        var logs: [DoseLog] = []
        var picked: [InjectionSite] = []
        for i in 0..<ALL.count {
            let at = NOW + Double(i) * 1000
            let s = suggestSite(logs, at)
            picked.append(s); logs.append(slog(s, 0, at: at))
        }
        #expect(Set(picked).count == ALL.count)
    }

    @Test func pinned() {
        let pinned: [InjectionSite] = [.thighL, .thighR, .gluteL]
        let pl = pinned.enumerated().map { slog($1, Double($0 + 1)) }
        for i in 0..<20 { #expect(pinned.contains(suggestSite(pl, NOW + Double(i), allowed: pinned))) }
        #expect(suggestSite([slog(.thighL, 1), slog(.thighR, 9), slog(.gluteL, 4)], NOW, allowed: pinned) == .thighR)
        var logs: [DoseLog] = []
        var picked: [InjectionSite] = []
        for i in 0..<pinned.count {
            let at = NOW + Double(i) * 1000
            let s = suggestSite(logs, at, allowed: pinned)
            picked.append(s); logs.append(slog(s, 0, at: at))
        }
        #expect(Set(picked).count == pinned.count)
        let nine = ALL.prefix(9).enumerated().map { slog($1, Double($0 + 1)) }
        #expect(suggestSite(nine, NOW, allowed: []) == ALL[9] && suggestSite(nine, NOW, allowed: nil) == ALL[9])
        let noisy = (0..<5).map { slog(.abdomenUL, Double($0 + 1)) } + [slog(.thighL, 2), slog(.thighR, 8), slog(.gluteL, 5)]
        #expect(suggestSite(noisy, NOW, allowed: pinned) == .thighR)
        #expect(pinned.contains(suggestSite([slog(.abdomenUL, 1), slog(.abdomenUR, 2)], NOW, allowed: pinned)))
        #expect(suggestSite([slog(.thighL, 0)], NOW, allowed: [.thighL]) == .thighL)
    }

    @Test func choices() {
        let pinned: [InjectionSite] = [.thighL, .thighR, .gluteL]
        var logs: [DoseLog] = []
        for i in 0..<12 {
            let at = NOW + Double(i) * DAY_MS
            #expect(siteChoices(logs, at, allowed: pinned)[0].site == suggestSite(logs, at, allowed: pinned))
            logs.append(slog(suggestSite(logs, at, allowed: pinned), 0, at: at))
        }
        let nine = ALL.prefix(9).enumerated().map { slog($1, Double($0 + 1)) }
        #expect(siteChoices(nine, NOW)[0].site == suggestSite(nine, NOW))
        #expect(siteChoices([slog(.abdomenLL, 30), slog(.thighL, 1)], NOW, allowed: pinned).allSatisfy { pinned.contains($0.site) })
        #expect(siteChoices([], NOW, limit: 3).count == 3 && siteChoices([], NOW, limit: 5).count == 5)
        #expect(!siteChoices([], NOW, allowed: ["not-a-site"]).isEmpty)
        #expect(jsRound(siteChoices([slog(.thighL, 3)], NOW, allowed: [.thighL])[0].daysSince) == 3)
    }

    @Test func overused() {
        #expect(overusedSites([slog(.abdomenLR, 1), slog(.abdomenLR, 3), slog(.abdomenLR, 5)], NOW).map(\.site).contains(.abdomenLR))
        #expect(overusedSites([slog(.abdomenLR, 1), slog(.abdomenLR, 3)], NOW).isEmpty)
        #expect(overusedSites([slog(.abdomenLR, 20), slog(.abdomenLR, 25), slog(.abdomenLR, 30)], NOW).isEmpty)
    }

    @Test func routes() {
        #expect(routeHasSite(.subcutaneous) && routeHasSite(.intramuscular))
        #expect(!routeHasSite(.oral) && !routeHasSite(.intranasal) && !routeHasSite(.topical) && !routeHasSite(.intravenous))
        let t = siteUsage([slog(.thighL, 1, route: .oral), slog(.thighL, 2, route: .intranasal)], NOW).first { $0.site == .thighL }!
        #expect(t.lastUsedAt == nil && t.recentCount == 0)
        let mixed = siteUsage([slog(.thighL, 1, route: .oral), slog(.thighL, 2)], NOW).first { $0.site == .thighL }!
        #expect(mixed.recentCount == 1 && isClose(mixed.daysSince, 2, digits: 6))
        let fresh = ALL.filter { $0 != .thighL }.map { slog($0, 1) }
        #expect(suggestSite(fresh + [slog(.thighL, 0, route: .oral)], NOW) == .thighL)
    }
}

@Suite struct SiteMapTests {
    func dot(_ id: InjectionSite) -> SiteDot { SITE_DOTS.first { $0.id == id }! }

    @Test func geometry() {
        #expect(SITE_DOTS.map(\.id.rawValue).sorted() == ALL.map(\.rawValue).sorted())
        for s in SITE_DOTS where s.id.rawValue.hasPrefix("abdomen") {
            #expect(s.cy > BODY.torsoTop && s.cy < BODY.crotchY && s.cx > BODY.torsoLeft && s.cx < BODY.torsoRight)
            #expect(!(s.cx > BODY.gapLeft && s.cx < BODY.gapRight && s.cy >= BODY.crotchY))
        }
        for id in [InjectionSite.thighL, .thighR, .gluteL, .gluteR] { #expect(dot(id).cy > BODY.crotchY && dot(id).cy < BODY.kneeY) }
        #expect(dot(.gluteL).cy < dot(.thighL).cy && dot(.gluteR).cy < dot(.thighR).cy)
        #expect(dot(.thighL).cy - dot(.gluteL).cy >= 16 && dot(.thighR).cy - dot(.gluteR).cy >= 16)
        #expect(dot(.thighL).cx < BODY.gapLeft && dot(.gluteL).cx < BODY.gapLeft)
        #expect(dot(.thighR).cx > BODY.gapRight && dot(.gluteR).cx > BODY.gapRight)
        for id in [InjectionSite.armL, .armR] { #expect(dot(id).cy > BODY.armTopY && dot(id).cy < BODY.armBottomY) }
        #expect(dot(.armL).cx < BODY.torsoLeft && dot(.armR).cx > BODY.torsoRight)
        for (l, r) in [(InjectionSite.abdomenUL, InjectionSite.abdomenUR), (.abdomenLL, .abdomenLR), (.armL, .armR), (.gluteL, .gluteR), (.thighL, .thighR)] {
            #expect(dot(l).cx + dot(r).cx == 200 && dot(l).cy == dot(r).cy)
        }
        for s in SITE_DOTS { #expect(s.cx > 0 && s.cx < 200 && s.cy > 0 && s.cy < 240) }
    }
}

private func resolve(_ id: String) -> Peptide? { Library.byId[id] }
private let klow = Library.byId["klow"]!
private let wolverine = Library.byId["wolverine"]!
private let cagrisema = Library.byId["cagrisema"]!
private let bpc = Library.byId["bpc-157"]!

@Suite struct BlendTests {
    func by(_ parts: [ComponentDose], _ id: String) -> ComponentDose { parts.first { $0.peptideId == id }! }

    @Test func identity() {
        #expect(isBlend(klow) && isBlend(wolverine) && isBlend(cagrisema) && !isBlend(bpc) && !isBlend(nil))
        #expect(blendDosing(klow) == .split && blendDosing(wolverine) == .split && blendDosing(cagrisema) == .perComponent)
    }

    @Test func klowRatio() {
        let parts = decomposeDose(klow, 4000, resolve: resolve)
        #expect(parts.count == 4)
        #expect(isClose(by(parts, "ghk-cu").fraction, 50.0 / 80, digits: 12) && isClose(by(parts, "ghk-cu").mcg, 2500, digits: 9))
        for id in ["bpc-157", "tb-500", "kpv"] { #expect(isClose(by(parts, id).fraction, 10.0 / 80, digits: 12) && isClose(by(parts, id).mcg, 500, digits: 9)) }
        #expect(isClose(parts.reduce(0) { $0 + $1.mcg }, 4000, digits: 9) && isClose(parts.reduce(0) { $0 + $1.fraction }, 1, digits: 12))
        #expect(isClose(by(decomposeDose(klow, 8000, resolve: resolve), "bpc-157").mcg, 1000, digits: 9))
        #expect(by(parts, "bpc-157").peptide?.name == "BPC-157" && by(parts, "ghk-cu").peptide?.halfLifeHours == nil)
        let dose = blendDoseForComponent(klow, "bpc-157", 250)
        let p = decomposeDose(klow, dose, resolve: resolve)
        #expect(isClose(by(p, "bpc-157").mcg, 250, digits: 6) && isClose(by(p, "ghk-cu").mcg, 1250, digits: 6))
    }

    @Test func position() {
        #expect(by(decomposeDose(klow, 4000, resolve: resolve), "bpc-157").relativeToTypical == .within)
        #expect(by(decomposeDose(klow, 8000, resolve: resolve), "bpc-157").relativeToTypical == .above)
        #expect(by(decomposeDose(klow, 800, resolve: resolve), "bpc-157").relativeToTypical == .below)
        var mystery = klow; mystery.id = "mystery"; mystery.components = [BlendComponent(name: "Unnamed", mgPerVial: 10)]
        #expect(decomposeDose(mystery, 1000, resolve: resolve)[0].relativeToTypical == .unknown)
        for dpw in [nil, 7.0] {
            let m = decomposeDose(mystery, 1000, resolve: resolve, dosesPerWeek: dpw)[0]
            #expect(m.relativeToTypical == .unknown && m.comparedOn == ComparedOn.none)
        }
    }

    @Test func perComponentAndEven() {
        let parts = decomposeDose(cagrisema, 2400, resolve: resolve)
        #expect(parts.count == 2 && parts.allSatisfy { $0.fraction == 1 && isClose($0.mcg, 2400, digits: 9) })
        #expect(isClose(parts.reduce(0) { $0 + $1.mcg }, 4800, digits: 9))
        let w = decomposeDose(wolverine, 1000, resolve: resolve)
        #expect(w.count == 2 && w.allSatisfy { isClose($0.fraction, 0.5, digits: 12) && isClose($0.mcg, 500, digits: 9) })
    }

    @Test func edges() {
        #expect(decomposeDose(bpc, 1000, resolve: resolve).isEmpty)
        let zero = decomposeDose(klow, 0, resolve: resolve)
        #expect(zero.allSatisfy { $0.mcg == 0 && $0.fraction.isFinite })
        #expect(decomposeDose(klow, -500, resolve: resolve).allSatisfy { $0.mcg == 0 })
        let bare = decomposeDose(klow, 4000)
        #expect(bare.count == 4 && bare[0].peptide == nil && bare[0].relativeToTypical == .unknown)
        #expect(isClose(bare.reduce(0) { $0 + $1.mcg }, 4000, digits: 9))
    }

    @Test func inverse() {
        #expect(isClose(blendDoseForComponent(klow, "bpc-157", 250), 2000, digits: 9))
        #expect(isClose(blendDoseForComponent(klow, "ghk-cu", 2500), 4000, digits: 9))
        for target in [100.0, 250, 500, 1000] {
            #expect(isClose(by(decomposeDose(klow, blendDoseForComponent(klow, "bpc-157", target), resolve: resolve), "bpc-157").mcg, target, digits: 6))
        }
        #expect(isClose(blendDoseForComponent(cagrisema, "semaglutide", 1700), 1700, digits: 9))
        #expect(blendDoseForComponent(klow, "nope", 250).isNaN && blendDoseForComponent(klow, "bpc-157", 0).isNaN)
    }

    @Test func modellableAndDescribe() {
        #expect(modellableComponents(decomposeDose(klow, 4000, resolve: resolve)).map(\.peptideId) == ["bpc-157"])
        #expect(modellableComponents(decomposeDose(cagrisema, 2400, resolve: resolve)).count == 2)
        let s = describeBlendDose(decomposeDose(klow, 8000, resolve: resolve))!
        #expect(s.contains("BPC-157") && s.contains("above"))
        let within = decomposeDose(klow, 4000, resolve: resolve).map { var p = $0; p.relativeToTypical = .within; return p }
        #expect(describeBlendDose(within) == nil)
        let below = decomposeDose(klow, 4000, resolve: resolve).map { var p = $0; p.relativeToTypical = .below; return p }
        #expect(describeBlendDose(below)!.contains("Every component"))
    }

    @Test func weekly() {
        let tb = by(decomposeDose(klow, 4000, resolve: resolve), "tb-500")
        #expect(tb.comparedOn == .perDose && tb.relativeToTypical == .below && tb.typicalLowMcg == 2000 && tb.typicalHighMcg == 2500)
        let wk = by(decomposeDose(klow, 4000, resolve: resolve, dosesPerWeek: 7), "tb-500")
        #expect(wk.comparedOn == .weekly && isClose(wk.weeklyMcg!, 3500, digits: 6))
        #expect(isClose(wk.typicalWeeklyLowMcg!, 4000, digits: 6) && isClose(wk.typicalWeeklyHighMcg!, 5000, digits: 6) && wk.relativeToTypical == .below)
        let perDoseShortfall = tb.typicalLowMcg! / tb.mcg, weeklyShortfall = wk.typicalWeeklyLowMcg! / wk.weeklyMcg!
        #expect(isClose(perDoseShortfall, 4, digits: 6) && isClose(weeklyShortfall, 1.143, digits: 2) && weeklyShortfall < perDoseShortfall)
        for id in ["bpc-157", "kpv"] {
            let p = by(decomposeDose(klow, 4000, resolve: resolve, dosesPerWeek: 7), id)
            #expect(isClose(p.weeklyMcg!, 3500, digits: 6) && p.relativeToTypical == .within, "\(id)")
        }
        let ghk = by(decomposeDose(klow, 4000, resolve: resolve, dosesPerWeek: 7), "ghk-cu")
        #expect(isClose(ghk.weeklyMcg!, 17_500, digits: 6) && ghk.relativeToTypical == .within)
        #expect(wk.typicalPerWeek == 2 && wk.typicalFrequency?.contains("weekly") == true)
        #expect(tb.weeklyMcg == nil)
        #expect(describeBlendDose(decomposeDose(klow, 4000, resolve: resolve, dosesPerWeek: 7))!.contains("for a week"))
        #expect(describeBlendDose(decomposeDose(klow, 8000, resolve: resolve))!.contains("at this dose"))
        let twice = by(decomposeDose(klow, 4000, resolve: resolve, dosesPerWeek: 2), "tb-500")
        #expect(isClose(twice.weeklyMcg!, 1000, digits: 6) && twice.relativeToTypical == .below)
    }
}
