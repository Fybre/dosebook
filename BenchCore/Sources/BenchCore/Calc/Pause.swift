import Foundation

// Pausing everything for a while: travel, illness. Doses that would have fallen in
// the pause are not scheduled at all, so they are not due, not missed, not
// reminded and not counted against adherence, whether looked at during the pause
// or long after it. Kept on each protocol in `extra`, so a backup stays readable
// by the web app, and so a window survives however the schedule is later edited.

let PAUSES_KEY = "iosPauses"

/// A stretch with no scheduled doses. `until` nil: until resumed.
public struct PauseWindow: Equatable, Sendable {
    public var from: Millis
    public var until: Millis?
    public init(from: Millis, until: Millis? = nil) { self.from = from; self.until = until }

    public func contains(_ at: Millis) -> Bool { at >= from && (until.map { at < $0 } ?? true) }
}

public extension DoseProtocol {
    var pauses: [PauseWindow] {
        get {
            (extra[PAUSES_KEY]?.arrayValue ?? []).compactMap { v in
                guard let from = v["from"]?.numberValue else { return nil }
                return PauseWindow(from: from, until: v["until"]?.numberValue)
            }
        }
        set {
            if newValue.isEmpty { extra.removeValue(forKey: PAUSES_KEY); return }
            extra[PAUSES_KEY] = .array(newValue.map { w in
                var o: JSONObject = ["from": .number(w.from)]
                if let u = w.until { o["until"] = .number(u) }
                return .object(o)
            })
        }
    }
}

public func isPaused(_ p: DoseProtocol, _ at: Millis) -> Bool {
    p.extra[PAUSES_KEY] != nil && p.pauses.contains { $0.contains(at) }
}

/// What a person sees: how long everything is paused for.
public struct PauseState: Equatable, Sendable {
    /// When doses start again; nil until resumed.
    public var until: Millis?
    public var protocols: Int
}

/// Nil when nothing running is paused right now.
public func currentPause(_ protocols: [DoseProtocol], _ now: Millis) -> PauseState? {
    let paused = protocols.filter { $0.active && isPaused($0, now) }
    guard !paused.isEmpty else { return nil }
    let ends = paused.map { p in p.pauses.first { $0.contains(now) }?.until }
    // Any open-ended pause means there is no date to give.
    let until: Millis? = ends.contains(where: { $0 == nil }) ? nil : ends.compactMap { $0 }.max()
    return PauseState(until: until, protocols: paused.count)
}

public extension AppData {
    /// Pauses every running protocol of the active profile from now to `until`, or
    /// until `resumeAll`. A pause already running is replaced.
    mutating func pauseAll(until: Millis?, now: Millis = nowMillis()) {
        for i in protocols.indices where protocols[i].profileId == activeProfileId && protocols[i].active && protocols[i].endedAt == nil {
            var windows = protocols[i].pauses.filter { w in w.until.map { $0 <= now } ?? false }
            windows.append(PauseWindow(from: now, until: until))
            protocols[i].pauses = windows
        }
    }

    /// Doses start again from now. Windows that have not begun are dropped.
    mutating func resumeAll(now: Millis = nowMillis()) {
        for i in protocols.indices where protocols[i].profileId == activeProfileId {
            var windows: [PauseWindow] = []
            for var w in protocols[i].pauses {
                if w.from > now { continue }
                if w.until.map({ $0 > now }) ?? true { w.until = now }
                windows.append(w)
            }
            protocols[i].pauses = windows
        }
    }
}
