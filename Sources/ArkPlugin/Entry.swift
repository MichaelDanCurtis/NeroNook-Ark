import AppKit
@main struct ArkEntry {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = ArkModule()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
