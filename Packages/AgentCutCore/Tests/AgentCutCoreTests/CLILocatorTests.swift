import Foundation
import Testing
@testable import AgentCutCore

struct CLILocatorTests {
    let a = URL(fileURLWithPath: "/a")
    let b = URL(fileURLWithPath: "/b")

    func locator(_ executables: Set<String>) -> CLILocator {
        CLILocator(searchDirectories: [a, b], isExecutable: { executables.contains($0.path) })
    }

    @Test func findsInFirstDirectory() {
        #expect(locator(["/a/claude"]).locate("claude", override: "")?.path == "/a/claude")
    }

    @Test func respectsOrder() {
        #expect(locator(["/a/claude", "/b/claude"]).locate("claude", override: "")?.path == "/a/claude")
        #expect(locator(["/b/claude"]).locate("claude", override: "")?.path == "/b/claude")
    }

    @Test func overrideWins() {
        #expect(locator(["/a/claude", "/opt/x/claude"]).locate("claude", override: "/opt/x/claude")?.path == "/opt/x/claude")
    }

    @Test func invalidOverrideReturnsNil() {
        #expect(locator(["/a/claude"]).locate("claude", override: "/nope/claude") == nil)
    }

    @Test func missingReturnsNil() {
        #expect(locator([]).locate("codex", override: "") == nil)
    }

    @Test func defaultDirectoriesOrder() {
        let home = URL(fileURLWithPath: "/Users/u")
        #expect(CLILocator.defaultDirectories(home: home).map(\.path) == [
            "/Users/u/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/Users/u/.npm-global/bin", "/Users/u/.bun/bin",
        ])
    }

    @Test func loginShellOutputIgnoresNoise() {
        let output = "Last login: oggi\n\u{1B}]7;file://x\u{07}__AGENTCUT_PATH__/Users/u/.nvm/versions/node/v20/bin:/usr/bin__END__\nbye"
        #expect(LoginShellPath.parse(output).map(\.path) == ["/Users/u/.nvm/versions/node/v20/bin", "/usr/bin"])
    }

    @Test func loginShellOutputWithoutMarkerIsEmpty() {
        #expect(LoginShellPath.parse("/usr/bin:/bin").isEmpty)
    }
}
