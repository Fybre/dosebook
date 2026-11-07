import Foundation
import Testing
@testable import DosebookCore

@Suite struct AppReleaseTests {
    @Test func numericVersions() throws {
        #expect(try #require(AppVersion("v1.0.10")) > #require(AppVersion("1.0.9")))
        #expect(AppVersion("1.0") == AppVersion("1.0.0"))
        #expect(try #require(AppVersion("2.0")) > #require(AppVersion("1.99.99")))
        for text in ["", "v", "1..0", "1.0-beta", "-1.0", "1.0.0.1", "latest", "1. 0", "999999999999999999999999"] {
            #expect(AppVersion(text) == nil)
        }
    }

    private func release(tag: String = "v1.0.10", draft: Bool = false, preview: Bool = false,
                         asset: String = "Dosebook.dmg", state: String = "uploaded") throws -> AppRelease {
        let data = try JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": draft, "prerelease": preview,
            "assets": [["name": asset, "state": state]]
        ])
        return try JSONDecoder().decode(AppRelease.self, from: data)
    }

    @Test func onlyReadyStableNewerMacReleases() throws {
        #expect(try release().isUpdate(for: "1.0.9"))
        #expect(try !release().isUpdate(for: "1.0.10"))
        #expect(try !release().isUpdate(for: "2.0"))
        #expect(try !release().isUpdate(for: "Unknown"))
        #expect(try !release(draft: true).isUpdate(for: "1.0"))
        #expect(try !release(preview: true).isUpdate(for: "1.0"))
        #expect(try !release(tag: "v2.0-beta").isUpdate(for: "1.0"))
        #expect(try !release(asset: "source.zip").isUpdate(for: "1.0"))
        #expect(try !release(state: "new").isUpdate(for: "1.0"))
        #expect(try release().url.absoluteString == "https://github.com/Fybre/dosebook/releases/tag/v1.0.10")
    }
}
