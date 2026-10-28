import Foundation

// Port of the actions in src/lib/store.ts, as mutations on the document.
//
// Pure: no persistence, no clock except the `now` each action is given. The
// app's store calls these inside one `mutate` and persists the result, so
// every rule the original applies on a write (attribute a dose to a vial,
// reconcile on edit, cascade a profile's rows, drop an emptied order) holds
// whichever screen made the change.
//
// Patches are closures over the row rather than partial objects: Swift has no
// `{ ...row, ...patch }`, and a closure says exactly which fields it touches.

extension Array where Element: Row {
    fileprivate mutating func update(_ id: String, _ change: (inout Element) -> Void) {
        if let i = firstIndex(where: { $0.id == id }) { change(&self[i]) }
    }
}

public extension AppData {
    // MARK: Lookups

    var activeProfile: Profile { profiles.first { $0.id == activeProfileId } ?? profiles.first ?? DEFAULT_PROFILE }

    /// Built-in library plus your own compounds, yours winning, by name. A library
    /// blend carries your vial's amounts where you have given them.
    var allPeptides: [Peptide] {
        let mine = Set(customPeptides.map(\.id))
        let amounts = blendAmounts
        return (Library.peptides.filter { !mine.contains($0.id) }.map { withBlendAmounts($0, amounts[$0.id]) } + customPeptides)
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func peptide(_ id: String) -> Peptide? {
        if let mine = customPeptides.first(where: { $0.id == id }) { return mine }
        return Library.byId[id].map { withBlendAmounts($0, blendAmounts[id]) }
    }

    /// Everything belonging to the active profile.
    var mine: AppData {
        var d = self
        let id = activeProfileId
        d.protocols = protocols.filter { $0.profileId == id }
        d.logs = logs.filter { $0.profileId == id }
        d.vials = vials.filter { $0.profileId == id }
        d.measurements = measurements.filter { $0.profileId == id }
        d.labs = labs.filter { $0.profileId == id }
        d.checkIns = checkIns.filter { $0.profileId == id }
        d.orders = orders.filter { $0.profileId == id }
        d.diluents = diluents.filter { $0.profileId == id }
        d.compoundNotes = compoundNotes.filter { $0.profileId == id }
        return d
    }

    // MARK: Profiles

    @discardableResult
    mutating func addProfile(name: String, now: Millis = nowMillis()) -> String {
        let id = uid()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        profiles.append(Profile(id: id, name: trimmed.isEmpty ? "Profile \(profiles.count + 1)" : trimmed,
                                tone: ProfileTone.allCases[profiles.count % ProfileTone.allCases.count], createdAt: now))
        activeProfileId = id
        return id
    }

    mutating func updateProfile(_ id: String, _ change: (inout Profile) -> Void) { profiles.update(id, change) }

    /// Takes the profile's rows with it; never leaves the app with no profile.
    mutating func removeProfile(_ id: String) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        self = withoutProfile(self, id)
        if activeProfileId == id { activeProfileId = profiles[0].id }
    }

    mutating func switchProfile(_ id: String) {
        if profiles.contains(where: { $0.id == id }) { activeProfileId = id }
    }

    // MARK: Protocols

    /// `p.id` and `p.profileId` are assigned here.
    @discardableResult
    mutating func addProtocol(_ p: DoseProtocol) -> String {
        var row = p
        row.id = uid()
        row.profileId = activeProfileId
        protocols.append(row)
        return row.id
    }

    mutating func updateProtocol(_ id: String, _ change: (inout DoseProtocol) -> Void) { protocols.update(id, change) }

    /// Keeps the history, detached from the deleted protocol.
    mutating func removeProtocol(_ id: String) {
        protocols.removeAll { $0.id == id }
        for i in logs.indices where logs[i].protocolId == id { logs[i].protocolId = nil }
    }

    // MARK: Doses

    /// Logs a dose and draws it from this profile's stock, from the container
    /// the compound actually comes in. Records the barrel reading at the time
    /// when the caller did not.
    @discardableResult
    mutating func addLog(_ l: DoseLog) -> String {
        var entry = l
        entry.id = uid()
        entry.profileId = activeProfileId
        let id = entry.id
        defer { logs.sort { $0.at > $1.at } }
        if l.isSkipped || !(l.doseMcg > 0) { logs.append(entry); return id }

        let myVials = vials.filter { $0.profileId == activeProfileId }
        let container = containerForDose(peptide(l.peptideId)?.preparation, l.route)
        guard let vialId = l.vialId ?? pickVialForDose(myVials, l.peptideId, l.doseMcg, l.at, container)?.id else {
            logs.append(entry); return id
        }
        entry.vialId = vialId
        let spec = syringeById(settings.defaultSyringeId) ?? SYRINGES[2]
        if l.units == nil, let drawn = marksFromVial(vials.first { $0.id == vialId }, l.doseMcg, spec.scale) {
            entry.units = jsFixed(drawn, 2)
            entry.syringeId = l.syringeId ?? spec.id
            entry.syringeScale = l.syringeScale ?? spec.scale
        }
        logs.append(entry)
        vials = drawFromVial(vials, vialId, l.doseMcg, l.at)
        return id
    }

    /// The dose a reminder was for, logged now from the notification: the protocol's
    /// scheduled amount, the next site in its rotation, and the vial `addLog` would pick.
    /// nil when the protocol is gone, or when that dose was already logged or skipped,
    /// so a second tap on an old notification does not log it twice.
    @discardableResult
    mutating func logFromReminder(protocolId: String, doseAt: Millis, now: Millis = nowMillis()) -> String? {
        guard let p = protocols.first(where: { $0.id == protocolId && $0.profileId == activeProfileId }) else { return nil }
        // A dose answers the scheduled time it is nearest to, so the morning's
        // dose never counts for the evening's reminder.
        let window: Millis = 12 * HOUR_MS
        let times = protocolDoseTimesBetween(p, doseAt - 2 * window, doseAt + 2 * window)
        let answered = logs.contains { l in
            guard l.profileId == activeProfileId, l.protocolId == p.id || (l.protocolId == nil && l.peptideId == p.peptideId),
                  abs(l.at - doseAt) < window else { return false }
            return times.min { abs($0 - l.at) < abs($1 - l.at) }.map { abs($0 - doseAt) < 60_000 } ?? true
        }
        if answered { return nil }
        let mine = logs.filter { $0.profileId == activeProfileId && $0.peptideId == p.peptideId }
        let site = routeHasSite(p.route) ? suggestSite(mine, now, allowed: allowedSites(for: p)) : nil
        return addLog(DoseLog(id: "", profileId: "", protocolId: p.id, peptideId: p.peptideId, at: now,
                              doseMcg: scheduledDoseMcg(p, doseAt), route: p.route, site: site))
    }

    /// Edits a dose, undoing what it used to take out of stock before applying what it takes now.
    mutating func updateLog(_ id: String, _ change: (inout DoseLog) -> Void) {
        guard let i = logs.firstIndex(where: { $0.id == id }) else { return }
        let before = logs[i]
        var after = before
        change(&after)
        if after.peptideId != before.peptideId, let vid = after.vialId {
            if vials.first(where: { $0.id == vid })?.peptideId != after.peptideId { after.vialId = nil }
        }
        logs[i] = after
        logs.sort { $0.at > $1.at }
        vials = reconcileVials(vials, Consumption(before), Consumption(after))
    }

    mutating func removeLog(_ id: String) {
        guard let removed = logs.first(where: { $0.id == id }) else { return }
        logs.removeAll { $0.id == id }
        if !removed.isSkipped, let vid = removed.vialId { vials = returnToVial(vials, vid, removed.doseMcg) }
    }

    // MARK: Measurements and labs

    @discardableResult
    mutating func addMeasurement(_ m: BodyMeasurement) -> String {
        var row = m
        row.id = uid(); row.profileId = activeProfileId
        measurements.append(row)
        measurements.sort { $0.at > $1.at }
        syncProfileWeights()
        return row.id
    }

    mutating func updateMeasurement(_ id: String, _ change: (inout BodyMeasurement) -> Void) {
        measurements.update(id, change)
        measurements.sort { $0.at > $1.at }
        syncProfileWeights()
    }

    mutating func removeMeasurement(_ id: String) {
        measurements.removeAll { $0.id == id }
        syncProfileWeights()
    }

    /// Weigh-ins are the one record of a person's weight. The profile's own `weightKg`, which
    /// the web and Android apps read, follows the latest of them, so every screen and every
    /// export agrees. With no weigh-ins at all it keeps whatever an import brought.
    mutating func syncProfileWeights() {
        for i in profiles.indices {
            if let kg = latestWeight(profileId: profiles[i].id)?.kg, profiles[i].weightKg != kg { profiles[i].weightKg = kg }
        }
    }

    @discardableResult
    mutating func addImportedLab(_ result: LabResult) -> Bool {
        guard !isDuplicateLab(markerId: result.markerId, value: result.value, at: result.at, existing: mine.labs) else { return false }
        _ = addLab(result)
        return true
    }

    @discardableResult
    mutating func addLab(_ l: LabResult) -> String {
        var row = l
        row.id = uid(); row.profileId = activeProfileId
        labs.append(row)
        labs.sort { $0.at > $1.at }
        return row.id
    }

    mutating func updateLab(_ id: String, _ change: (inout LabResult) -> Void) {
        labs.update(id, change)
        labs.sort { $0.at > $1.at }
    }

    mutating func removeLab(_ id: String) { labs.removeAll { $0.id == id } }

    // MARK: Check-ins and vitals

    /// Upserts on the local day; refuses a day that has not happened (returns nil).
    @discardableResult
    mutating func saveCheckIn(at: Millis, ratings: [String: Double], notes: String?, now: Millis = nowMillis()) -> String? {
        guard let day = ratableDay(at, nowMs: now) else { return nil }
        let id = checkIns.first { $0.profileId == activeProfileId && $0.at == day }?.id ?? uid()
        checkIns.removeAll { $0.id == id }
        checkIns.append(CheckIn(id: id, profileId: activeProfileId, at: day, ratings: ratings, notes: notes))
        checkIns.sort { $0.at > $1.at }
        return id
    }

    mutating func removeCheckIn(_ id: String) { checkIns.removeAll { $0.id == id } }

    /// Sleep and resting heart rate from HealthKit, upserted on a per-day id.
    mutating func recordVitals(dayMs: Millis, sleepHours: Double?, restingHrBpm: Double?) {
        guard sleepHours != nil || restingHrBpm != nil else { return }
        let day = startOfLocalDay(dayMs)
        let externalId = "hc-vitals:\(jsNumberString(day))"
        if let i = measurements.firstIndex(where: { $0.profileId == activeProfileId && $0.externalId == externalId }) {
            if let s = sleepHours { measurements[i].sleepHours = s }
            if let r = restingHrBpm { measurements[i].restingHrBpm = r }
            return
        }
        measurements.append(BodyMeasurement(id: uid(), profileId: activeProfileId, at: day, sleepHours: sleepHours,
                                            restingHrBpm: restingHrBpm, source: .healthConnect, externalId: externalId))
        measurements.sort { $0.at > $1.at }
    }

    // MARK: Stock

    @discardableResult
    mutating func addVial(_ v: Vial) -> String {
        var row = v
        row.id = uid(); row.profileId = activeProfileId
        vials.append(row)
        return row.id
    }

    mutating func updateVial(_ id: String, _ change: (inout Vial) -> Void) { vials.update(id, change) }

    /// Correct one stock record without rewriting dose history or drawing water twice.
    /// Identity and delivery links belong to the existing record, including newly added batches.
    /// False, with nothing changed, when the record is not found or the draft does not hold together.
    @discardableResult
    mutating func editVialDetails(_ draft: Vial, fromBottleId: String? = nil) -> Bool {
        guard let index = vials.firstIndex(where: { $0.id == draft.id && $0.profileId == activeProfileId }),
              draft.strengthMg.isFinite, draft.strengthMg > 0,
              (draft.drawnMcg ?? 0).isFinite, (draft.drawnMcg ?? 0) >= 0,
              (draft.drawnMcg ?? 0) <= vialCapacityMcg(draft) else { return false }
        let old = vials[index]
        let startsMixing = old.state != .reconstituted && draft.state == .reconstituted && !isPack(draft)
        if draft.state == .reconstituted && !isPack(draft) {
            guard let ml = draft.diluentMl, ml.isFinite, ml > 0 else { return false }
        }
        var updated = draft
        updated.id = old.id; updated.profileId = old.profileId
        updated.peptideId = old.peptideId; updated.orderId = old.orderId
        updated.acquiredAt = old.acquiredAt
        updated.container = old.container; updated.filledFromVialId = old.filledFromVialId
        updated.mlPerSpray = old.mlPerSpray; updated.extra = old.extra
        if old.state == .reconstituted && updated.state == .reconstituted {
            updated.diluentBottleId = old.diluentBottleId
            if old.reconstitutedAt == updated.reconstitutedAt { updated.budAt = old.budAt }
        } else if startsMixing {
            updated.diluentBottleId = fromBottleId
        }
        vials[index] = updated
        if startsMixing, let bottle = fromBottleId, let ml = updated.diluentMl {
            diluents = drawFromBottle(diluents, bottle, ml, updated.reconstitutedAt ?? nowMillis())
        }
        return true
    }

    /// Several vials added together share an order (a delivery); one vial with no postage does not.
    mutating func addOrder(_ newVials: [Vial], shippingCost: Double?, currency: String?, now: Millis = nowMillis()) {
        let paid = (shippingCost ?? 0) > 0
        let orderId: String? = newVials.count > 1 || paid ? uid() : nil
        for v in newVials {
            var row = v
            row.id = uid(); row.profileId = activeProfileId; row.orderId = orderId
            vials.append(row)
        }
        if let orderId {
            orders.append(Order(id: orderId, profileId: activeProfileId, shippingCost: paid ? shippingCost : nil,
                                currency: paid ? currency : nil, placedAt: now))
        }
    }

    /// Removing the last vial of an order removes the order.
    mutating func removeVial(_ id: String) {
        let gone = vials.first { $0.id == id }
        vials.removeAll { $0.id == id }
        if let oid = gone?.orderId, !vials.contains(where: { $0.orderId == oid }) { orders.removeAll { $0.id == oid } }
    }

    /// Empties a made-up vial into a spray bottle, in one write. Returns the bottle's id.
    @discardableResult
    mutating func transferToSpray(vialId: String, addedMl: Double, mlPerSpray: Double, diluent: DiluentKind? = nil,
                                  fromBottleId: String? = nil, now: Millis = nowMillis()) -> String? {
        guard let source = vials.first(where: { $0.id == vialId }),
              let plan = BenchCore.transferToSpray(source, addedMl: addedMl, mlPerSpray: mlPerSpray, diluent: diluent,
                                                   diluentBottleId: fromBottleId, atMs: now) else { return nil }
        var bottle = plan.bottle
        bottle.id = uid(); bottle.profileId = activeProfileId
        vials.update(vialId) { $0 = plan.source }
        vials.append(bottle)
        if let b = fromBottleId { diluents = drawFromBottle(diluents, b, plan.drawnMl, now) }
        return bottle.id
    }

    /// Makes up a vial; the water leaves its bottle in the same write.
    mutating func reconstituteVial(_ id: String, diluentMl: Double, diluent: DiluentKind?, at: Millis = nowMillis(), fromBottleId: String? = nil) {
        vials.update(id) { v in
            v.state = .reconstituted
            v.reconstitutedAt = at
            v.diluentMl = diluentMl
            v.diluent = diluent
            v.diluentBottleId = fromBottleId
            v.drawnMcg = v.drawnMcg ?? 0
            v.budAt = beyondUseDate(at)
        }
        if let b = fromBottleId { diluents = drawFromBottle(diluents, b, diluentMl, at) }
    }

    /// Corrects how much is left in a vial, as counted by eye: what was drawn
    /// becomes whatever makes the remainder this, never below empty or above full.
    mutating func setVialRemaining(_ id: String, remainingMcg: Double) {
        vials.update(id) { v in
            let cap = vialCapacityMcg(v)
            v.drawnMcg = jsFixed(cap - min(max(0, remainingMcg), cap), 6)
        }
    }

    /// More solvent into an open vial. The beyond-use date does not move.
    mutating func topUpVial(_ id: String, addedMl: Double, fromBottleId: String? = nil, now: Millis = nowMillis()) {
        guard let target = vials.first(where: { $0.id == id }), let d = diluentAfterTopUp(target, addedMl) else { return }
        vials.update(id) { $0.diluentMl = d }
        if let b = fromBottleId { diluents = drawFromBottle(diluents, b, addedMl, now) }
    }

    @discardableResult
    mutating func addDiluent(_ b: DiluentBottle) -> String {
        var row = b
        row.id = uid(); row.profileId = activeProfileId
        diluents.append(row)
        return row.id
    }

    mutating func updateDiluent(_ id: String, _ change: (inout DiluentBottle) -> Void) { diluents.update(id, change) }
    mutating func removeDiluent(_ id: String) { diluents.removeAll { $0.id == id } }
    mutating func openDiluent(_ id: String, now: Millis = nowMillis()) { diluents = openBottle(diluents, id, now) }
    /// Water used for something this app does not track. Only ever takes water out.
    mutating func drawDiluent(_ id: String, ml: Double, now: Millis = nowMillis()) { diluents = drawFromBottle(diluents, id, ml, now) }

    // MARK: Settings and compounds

    mutating func updateSettings(_ change: (inout Settings) -> Void) { change(&settings) }

    mutating func addCustomPeptide(_ p: Peptide) {
        customPeptides.removeAll { $0.id == p.id }
        customPeptides.append(p)
    }

    /// The id never changes: protocols, doses and vials point at it.
    mutating func updateCustomPeptide(_ id: String, _ next: Peptide) {
        customPeptides.update(id) { var n = next; n.id = id; $0 = n }
    }

    mutating func removeCustomPeptide(_ id: String) { customPeptides.removeAll { $0.id == id } }

    /// Your own half-life for a compound, or nil to drop it. Shared by every profile.
    mutating func setHalfLifeOverride(_ peptideId: String, hours: Double?, note: String? = nil, now: Millis = nowMillis()) {
        if let h = hours, h > 0 { halfLifeOverrides[peptideId] = HalfLifeOverride(hours: h, setAt: now, note: note) }
        else { halfLifeOverrides.removeValue(forKey: peptideId) }
    }

    /// Upserts on profile and compound; blank text removes the note.
    mutating func setCompoundNote(_ peptideId: String, text: String, now: Millis = nowMillis()) {
        let mineMatch: (CompoundNote) -> Bool = { $0.profileId == activeProfileId && $0.peptideId == peptideId }
        let existing = compoundNotes.first(where: mineMatch)
        compoundNotes.removeAll(where: mineMatch)
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        compoundNotes.insert(CompoundNote(id: existing?.id ?? uid(), profileId: activeProfileId, peptideId: peptideId,
                                          text: body, updatedAt: now), at: 0)
    }

    // MARK: Whole document

    /// Replace everything with a backup, through the same migration as stored data.
    /// Settings this device keeps for itself (`sync`) survive.
    mutating func importData(_ data: AppData) {
        let sync = settings.extra["sync"]
        self = migrateAppData(data)
        if let sync { settings.extra["sync"] = sync } else { settings.extra.removeValue(forKey: "sync") }
    }

    /// Merges another app's history. Imported doses carry no vial and leave stock alone.
    mutating func importHistory(logs newLogs: [DoseLog], measurements newMeasurements: [BodyMeasurement]) {
        for l in newLogs { var r = l; r.id = uid(); r.profileId = activeProfileId; r.vialId = nil; logs.append(r) }
        for m in newMeasurements { var r = m; r.id = uid(); r.profileId = activeProfileId; measurements.append(r) }
        logs.sort { $0.at > $1.at }
        measurements.sort { $0.at > $1.at }
        syncProfileWeights()
    }

    /// The document for a backup file: everything, minus this device's own sync note.
    var exportDocument: AppData {
        var d = self
        d.settings.extra.removeValue(forKey: "sync")
        return d
    }

    mutating func resetAll() { self = AppData() }

    mutating func putRecordsBack(_ rescue: Rescue) { self = restoreLost(self, rescue) }
}

public struct VialStatus: Equatable, Sendable {
    public var vial: Vial
    public var concentrationMcgPerMl: Double
    public var remainingMl: Double
    public var remainingMcg: Double
    public var fractionRemaining: Double
    /// Days until the beyond-use date; negative when past it.
    public var daysToBud: Double?
    public var expired: Bool
}

public func vialStatus(_ v: Vial, nowMs: Millis = nowMillis()) -> VialStatus {
    VialStatus(vial: v, concentrationMcgPerMl: vialConcentration(v), remainingMl: vialRemainingMl(v),
               remainingMcg: vialRemainingMcg(v), fractionRemaining: vialFractionRemaining(v),
               daysToBud: v.budAt.map { ($0 - nowMs) / DAY_MS }, expired: vialExpired(v, nowMs))
}
