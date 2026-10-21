import Foundation

// Port of src/lib/calc/sites.ts. Injection site rotation: repeated injection into
// one spot causes lipohypertrophy, which absorbs erratically, so rotation is a
// dosing-accuracy matter.

/// Routes that put a needle into tissue, and so have a site to rotate.
public func routeHasSite(_ route: Route) -> Bool { route == .subcutaneous || route == .intramuscular }

/// The body figure the site map is drawn on, in its own coordinate units.
/// The dots below must stay inside it; a test holds them there.
public enum BODY {
    public static let torsoTop: Double = 40
    public static let torsoLeft: Double = 74
    public static let torsoRight: Double = 126
    public static let crotchY: Double = 118
    public static let kneeY: Double = 162
    public static let ankleY: Double = 230
    public static let gapLeft: Double = 90
    public static let gapRight: Double = 110
    public static let armTopY: Double = 52
    public static let armBottomY: Double = 85
}

public struct SiteDot: Sendable {
    public var id: InjectionSite
    public var cx: Double
    public var cy: Double
}

public let SITE_DOTS: [SiteDot] = [
    SiteDot(id: .abdomenUL, cx: 84, cy: 94), SiteDot(id: .abdomenUM, cx: 100, cy: 92), SiteDot(id: .abdomenUR, cx: 116, cy: 94),
    SiteDot(id: .abdomenLL, cx: 84, cy: 108), SiteDot(id: .abdomenLM, cx: 100, cy: 110), SiteDot(id: .abdomenLR, cx: 116, cy: 108),
    SiteDot(id: .armL, cx: 68, cy: 68), SiteDot(id: .armR, cx: 132, cy: 68),
    SiteDot(id: .gluteL, cx: 80, cy: 128), SiteDot(id: .gluteR, cx: 120, cy: 128),
    SiteDot(id: .thighL, cx: 83, cy: 146), SiteDot(id: .thighR, cx: 117, cy: 146),
]

public struct SiteUsage: Equatable, Sendable, Identifiable {
    public var site: InjectionSite
    public var lastUsedAt: Millis?
    /// Infinity when never used.
    public var daysSince: Double
    public var recentCount: Int
    /// 0 = freshly used, 1 = fully rested.
    public var rested: Double
    public var id: String { site.rawValue }
}

/// How rested every site is, most rested first. Doses whose route has no site
/// (or skipped doses) never count.
public func siteUsage(_ logs: [DoseLog], _ nowMs: Millis, restDays: Double = 14) -> [SiteUsage] {
    let windowStart = nowMs - restDays * DAY_MS
    let relevant = logs.filter { !$0.isSkipped && $0.site != nil && routeHasSite($0.route) }
    return INJECTION_SITES.map { info -> SiteUsage in
        let uses = relevant.filter { $0.site == info.id }.map(\.at)
        let last = uses.max()
        let daysSince = last.map { (nowMs - $0) / DAY_MS } ?? .infinity
        return SiteUsage(site: info.id, lastUsedAt: last, daysSince: daysSince,
                         recentCount: uses.filter { $0 >= windowStart }.count,
                         rested: max(0, min(1, daysSince / restDays)))
    }.stableSorted { a, b in a.rested != b.rested ? a.rested > b.rested : a.recentCount < b.recentCount }
}

/// The site to use next: whichever has rested longest, within `allowed` when given.
public func suggestSite(_ logs: [DoseLog], _ nowMs: Millis, restDays: Double = 14, allowed: [InjectionSite]? = nil) -> InjectionSite {
    let ranked = siteUsage(logs, nowMs, restDays: restDays)
    if let allowed, !allowed.isEmpty {
        let set = Set(allowed)
        if let first = ranked.first(where: { set.contains($0.site) }) { return first.site }
    }
    return ranked[0].site
}

/// The sites worth offering for the next dose, best first. The first entry is
/// always `suggestSite`'s answer.
public func siteChoices(_ logs: [DoseLog], _ nowMs: Millis, restDays: Double = 14, allowed: [InjectionSite]? = nil, limit: Int = 5) -> [SiteUsage] {
    let ranked = siteUsage(logs, nowMs, restDays: restDays)
    let within = (allowed?.isEmpty == false) ? ranked.filter { Set(allowed!).contains($0.site) } : ranked
    return Array((within.isEmpty ? ranked : within).prefix(max(1, limit)))
}

/// Sites hit hard enough recently that they are worth resting.
public func overusedSites(_ logs: [DoseLog], _ nowMs: Millis, restDays: Double = 14, threshold: Int = 3) -> [SiteUsage] {
    siteUsage(logs, nowMs, restDays: restDays).filter { $0.recentCount >= threshold }
}
