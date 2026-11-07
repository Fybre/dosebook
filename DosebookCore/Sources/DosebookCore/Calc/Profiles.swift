import Foundation

// Port of src/lib/calc/profiles.ts.

/// Collections whose rows each belong to exactly one profile.
public let PROFILE_OWNED_KEYS = [
    "protocols", "logs", "vials", "measurements", "labs", "checkIns", "orders", "diluents",
    // How a compound treats you is not how it treats the person sharing the device.
    "compoundNotes",
]

/// Shared by the whole install, with the reason.
public let SHARED_KEYS: [String: String] = [
    "version": "a stamp on the document, not on anyone",
    "profiles": "the list of owners itself",
    "activeProfileId": "which owner is on screen, a property of the device",
    "settings": "one set of preferences per install, including the sync address",
    "customPeptides": "a compound you added is a fact about the compound, not about you",
    "halfLifeOverrides": "a belief about a compound, deliberately not per profile",
]

/// The document with one profile's rows removed. Only owned collections are touched.
public func withoutProfile(_ data: AppData, _ profileId: String) -> AppData {
    var out = data
    out.protocols.removeAll { $0.profileId == profileId }
    out.logs.removeAll { $0.profileId == profileId }
    out.vials.removeAll { $0.profileId == profileId }
    out.measurements.removeAll { $0.profileId == profileId }
    out.labs.removeAll { $0.profileId == profileId }
    out.checkIns.removeAll { $0.profileId == profileId }
    out.orders.removeAll { $0.profileId == profileId }
    out.diluents.removeAll { $0.profileId == profileId }
    out.compoundNotes.removeAll { $0.profileId == profileId }
    return out
}

/// Whether a row is visible to nobody, given the profiles that exist.
public func isOrphaned(_ profileId: String?, _ profileIds: Set<String>) -> Bool {
    guard let id = profileId, !id.isEmpty else { return true }
    return !profileIds.contains(id)
}
