import SwiftUI
import BenchCore

/// Switches to one of the main tabs, from inside a guide page.
extension EnvironmentValues {
    @Entry var goToTab: @MainActor (String) -> Void = { _ in }
}

/// How to use the app: short pages by task, searchable. English only for now.
struct GuideView: View {
    @State private var query = ""
    #if DEBUG
    @State private var debugTopic: GuideTopic?
    #endif

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let topics = q.isEmpty ? GUIDE_TOPICS : GUIDE_TOPICS.filter { $0.searchText.contains(q) }
        GroupedList {
            Section { Text(t("ios_guide_subtitle")).font(.subheadline).foregroundStyle(.secondary) }
            Section {
                ForEach(topics) { topic in
                    NavigationLink(value: topic) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title).font(.body)
                                Text(topic.summary).font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: topic.symbol) }
                    }
                }
                if topics.isEmpty { Text(t("ios_guide_none")).foregroundStyle(.secondary) }
            }
        }
        .readableWidth()
        .searchable(text: $query)
        .navigationDestination(for: GuideTopic.self) { GuideTopicView(topic: $0) }
        #if DEBUG
        .navigationDestination(item: $debugTopic) { GuideTopicView(topic: $0) }
        .onAppear {
            // `-guideTopic <id>`: opens that page, for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if debugTopic == nil, let i = args.firstIndex(of: "-guideTopic"), i + 1 < args.count { debugTopic = GUIDE_TOPICS.first { $0.id == args[i + 1] } }
        }
        #endif
        .navigationTitle(t("ios_guide_title"))
    }
}

private struct GuideTopicView: View {
    var topic: GuideTopic
    @Environment(\.goToTab) private var goToTab

    var body: some View {
        GroupedList {
            ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let s):
                    Section { RichText(s) }
                case .points(let items):
                    Section {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("•").foregroundStyle(.secondary)
                                RichText(s)
                            }
                        }
                    }
                case .steps(let items):
                    Section {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, s in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(.footnote.weight(.bold)).foregroundStyle(Color.accentColor).frame(width: 18)
                                RichText(s)
                            }
                        }
                    }
                case .tip(let s):
                    Section { RichText(s).font(.footnote).callout(.sky) }
                case .caution(let s):
                    Section { RichText(s).font(.footnote).callout(.tangerine) }
                case .open(let tab):
                    Section {
                        Button { goToTab(tab) } label: { Label(t("ios_guide_open", ["screen": .string(tabName(tab))]), systemImage: "arrow.right.circle") }
                    }
                }
            }
        }
        .readableWidth()
        .font(.subheadline)
        .navigationTitle(topic.title)
        .inlineTitle()
    }

    private func tabName(_ tab: String) -> String {
        switch tab {
        case "now": t("nav_now")
        case "plan": t("nav_plan")
        case "log": t("nav_log")
        default: t("nav_stock")
        }
    }
}
