import SwiftUI
import BenchCore
import BenchStore

/// Which profile is showing, and a way to change it, on every main screen. Shown only
/// with two or more profiles. Colour and initial together, so it does not rely on colour alone.
struct ProfileChip: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let data = store.data
        if data.profiles.count > 1, let active = data.profiles.first(where: { $0.id == data.activeProfileId }) {
            // A tap does nothing, so a brush of the thumb never changes whose data is showing;
            // holding it opens the list of profiles.
            HStack(spacing: 6) {
                ProfileDot(profile: active, size: 22)
                Text(active.name).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .fixedSize()
            .contentShape(Rectangle())
            .contextMenu {
                Picker(t("ios_profile_switch"), selection: Binding(get: { data.activeProfileId }, set: { id in store.mutate { $0.switchProfile(id) } })) {
                    ForEach(data.profiles) { p in Text(p.name).tag(p.id) }
                }
            }
            .accessibilityLabel(t("ios_profile_chip_label", ["name": .string(active.name)]))
            .accessibilityHint(t("ios_profile_chip_hint"))
        }
    }
}

/// The profile's colour with its initial.
struct ProfileDot: View {
    var profile: Profile
    var size: CGFloat = 22
    var body: some View {
        Circle().fill(profile.tone.color).frame(width: size, height: size)
            .overlay(Text(String(profile.name.prefix(1)).uppercased()).font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white))
    }
}

extension View {
    /// Puts the profile chip at the leading edge of the toolbar.
    func profileChip() -> some View {
        toolbar { ToolbarItem(placement: .navigation) { ProfileChip() } }
    }
}
