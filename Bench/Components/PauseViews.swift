import SwiftUI
import BenchCore
import BenchStore

/// While everything is paused: until when, and a way back. Nothing when it is not.
struct PauseBanner: View {
    @Environment(AppStore.self) private var store
    var now: Millis

    var body: some View {
        if let pause = currentPause(store.data.mine.protocols, now) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "pause.circle.fill").foregroundStyle(Tone.sky.color)
                    Text(pause.until.map { t("ios_pause_until", ["date": .string(formatDate($0, nowMs: now))]) } ?? t("ios_pause_open"))
                        .font(.subheadline.weight(.semibold))
                }
                Text(t("ios_pause_banner_hint")).font(.footnote).foregroundStyle(.secondary)
                Button { store.mutate { $0.resumeAll() } } label: { Label(t("ios_pause_resume"), systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

/// Choose how long everything is paused for.
struct PauseSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var untilResumed = false
    @State private var resumeOn = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()

    var body: some View {
        let running = store.data.mine.protocols.filter { $0.active && $0.endedAt == nil }.count
        Form {
            Section {
                Toggle(t("ios_pause_until_resumed"), isOn: $untilResumed)
                if !untilResumed {
                    DatePicker(t("ios_pause_resume_on"), selection: $resumeOn, in: Date().addingTimeInterval(86_400)..., displayedComponents: .date)
                }
            } header: { Text(t("ios_pause_title")) } footer: {
                FooterWrap { Text(t("ios_pause_hint", ["protocols": .string(t("count_protocols", ["n": .number(Double(running))]))])) }
            }
            FooterRow { Text(t("ios_pause_hint", ["protocols": .string(t("count_protocols", ["n": .number(Double(running))]))])) }
        }
        .navigationTitle(t("ios_pause_title"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("ios_pause_start")) {
                    // Doses from the start of the chosen day come back.
                    let until: Millis? = untilResumed ? nil : startOfLocalDay(resumeOn.millis)
                    store.mutate { $0.pauseAll(until: until) }
                    dismiss()
                }
                .disabled(running == 0)
            }
        }
    }
}

/// A vial has been used up: say so, and how many are left. No button to open another;
/// that waits until a dose needs it.
struct EmptyVialCards: View {
    @Environment(AppStore.self) private var store
    @Environment(\.goToTab) private var goToTab
    var watcher = StockWatcher.shared
    var now: Millis

    var body: some View {
        let data = store.data
        ForEach(watcher.pending, id: \.self) { id in
            if let v = data.mine.vials.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "flask").foregroundStyle(Tone.tangerine.color)
                        Text(emptyVialText(data, v, now: now)).font(.subheadline)
                    }
                    HStack {
                        Button { goToTab("stock") } label: { Label(t("nav_stock"), systemImage: "arrow.right.circle") }
                            .buttonStyle(.bordered).controlSize(.small)
                        Button(t("dismiss")) { watcher.dismiss(id) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }
}
