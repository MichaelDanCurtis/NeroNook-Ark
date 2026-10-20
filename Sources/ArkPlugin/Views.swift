import SwiftUI
import NookPluginSDK
import ArkCore

@MainActor extension ArkModule {
    var surface: PluginCustomView {
        let target = [PluginParameter("device", .string), PluginParameter("host", .string)]
        var state: [String: PluginValue] = [
            "device": .string(settings.deviceID), "host": .string(settings.host),
            "model": .string(info?.device.modelName ?? "Odyssey Ark"),
            "resolution": .string(info?.device.resolution?.replacingOccurrences(of: "x", with: " × ") ?? ""),
            "connected": .boolean(connected), "busy": .boolean(busy), "refreshing": .boolean(refreshing), "can_volume": .boolean(canVolume), "can_mute": .boolean(canMute),
            "remote_ready": .boolean(remoteReady && connected), "remote_connecting": .boolean(remoteConnecting), "remote_status": .string(remoteStatus),
            "notice": .string(displayNotice), "last_read": .string(lastRead?.formatted(date: .omitted, time: .standard) ?? "Never"),
            "paired": .boolean(settings.certificate != nil)
        ]
        state["source_confirmed"] = .string(String(decoding: (try? JSONEncoder().encode(sourceMapping.confirmed.map(\.rawValue))) ?? Data("[]".utf8), as: UTF8.self))
        state["source_peers"] = .string(String(decoding: (try? JSONEncoder().encode(sourcePeers.map { ["id": $0.address.plugin, "name": sourcePeerNames[$0.address.plugin] ?? $0.channel?.title ?? "Keyboard"] })) ?? Data("[]".utf8), as: UTF8.self))
        state["source_provider"] = .string(keyboardLink.provider)
        state["source_link_active"] = .boolean(sourceLinkActive)
        state["source_link_status"] = .string(sourceLinkStatus)
        state["source_mapping"] = .string(String(decoding: (try? JSONEncoder().encode(sourceMapping.sources.map(\.rawValue))) ?? Data("[]".utf8), as: UTF8.self))
        if connected, let value = audio?.volume { state["volume"] = .number(Double(value)) }
        if connected, let value = audio?.muted { state["muted"] = .boolean(value) }
        return .init(entry: "monitor/index.html", revision: "ark_input1", state: state, events: [
            .init("map_source", input: .init(target + [.init("channel", .number, minimum: 1, maximum: 3), .init("source", .string)])),
            .init("test_source", input: .init(target + [.init("source", .string)])),
            .init("confirm_source", input: .init(target + [.init("source", .string)])),
            .init("source_link", input: .init(target + [.init("provider", .string), .init("enabled", .boolean)])),
            .init("volume", input: .init(target + [.init("value", .number, minimum: 0, maximum: 100)])),
            .init("adjust", input: .init(target + [.init("delta", .number, minimum: -1, maximum: 1)])),
            .init("mute", input: .init(target + [.init("value", .boolean)])),
            .init("key", input: .init(target + [.init("key", .string)])),
            .init("pair", input: .init(target)), .init("refresh"), .init("settings")
        ])
    }
    func handleView(_ event: PluginViewEvent) throws {
        guard event.panelID == "monitor" else { throw ArkError("Unknown monitor view.") }
        try surface.validate(event)
        if event.name == "settings" { showSetup = true; showWindow(); return }
        if event.name == "refresh" { refresh(); return }
        func text(_ key: String) -> String { if case .string(let s) = event.values[key] { return s }; return "" }
        func number(_ key: String) throws -> Int {
            guard case .number(let value) = event.values[key], value.isFinite, value.rounded() == value else { throw ArkError("Choose a whole-number value.") }
            return Int(value)
        }
        try ControlTarget.validate(device: text("device"), host: text("host"), selectedDevice: settings.deviceID, selectedHost: settings.host, connected: connected || event.name == "source_link" || event.name == "map_source")
        guard !busy else { throw ArkError("Wait for the monitor to finish. No command was queued.") }
        switch event.name {
        case "map_source":
            guard let source = InputSource(rawValue: text("source")) else { throw ArkError("Unknown input.") }
            try setSourceMapping(channel: number("channel"), source: source)
        case "confirm_source":
            guard let source = InputSource(rawValue: text("source")) else { throw ArkError("Unknown input.") }; try confirmSource(source)
        case "source_link":
            guard case .boolean(let enabled) = event.values["enabled"] else { throw ArkError("Choose the keyboard link state.") }
            try configureSourceLink(provider: text("provider"), enabled: enabled)
        case "test_source":
            guard let source = InputSource(rawValue: text("source")), remoteReady else { throw ArkError("Connect the paired remote before testing an input.") }
            testSource(source)
        case "volume", "adjust":
            guard canVolume else { throw ArkError("Volume control is unavailable on this connection.") }
            let command: AudioCommand = event.name == "volume" ? .volume(try number("value")) : .adjustVolume(try number("delta"))
            try command.validate(); apply(command)
        case "mute":
            guard canMute, case .boolean(let value) = event.values["value"] else { throw ArkError("Mute control is unavailable on this connection.") }
            apply(.mute(value))
        case "key":
            guard remoteReady, let key = RemoteKey(rawValue: text("key")) else { throw ArkError("Connect the remote before using navigation.") }
            press(key)
        case "pair":
            guard !remoteConnecting else { throw ArkError("Wait for the current remote connection to finish.") }
            if settings.certificate == nil { showSetup = true; showWindow() }
            pair()
        default: throw ArkError("Unknown monitor control.")
        }
    }
}
struct ArkWindow: View {
    @ObservedObject var model: ArkModule
    var body: some View {
        PluginWebSurface(root: Bundle.main.resourceURL!.appendingPathComponent("Views"), panelID: "monitor", definition: model.surface) { event in
            do { try model.handleView(event) } catch { model.notice = error.localizedDescription }
        }.frame(width: 800, height: 450)
            .sheet(isPresented: $model.showSetup) { ArkSetup(model: model) }
    }
}
struct ArkSetup: View {
    @ObservedObject var model: ArkModule
    var body: some View {
        PluginSettingsPage("Odyssey Ark", subtitle: "Connect directly on your network. No Samsung app or cloud account required.", symbol: "display", width: 680, height: 650, done: { model.showSetup = false }) {
            PluginSettingsSection("Monitor connection") {
            HStack {
                TextField("Monitor IP address", text: $model.draftHost)
                Button("Find monitor") { model.discover() }
                Button("Connect") { model.connect() }.pluginPrimaryAction()
            }.disabled(model.busy)
            if !model.candidates.isEmpty { HStack { Text("Found:").font(.caption); ForEach(model.candidates, id: \.self) { host in Button(host) { model.draftHost = host }.disabled(model.busy) } } }
            }
            PluginSettingsSection("Remote control", detail: "Pair once, then use volume, sources and navigation from the module.") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monitor remote").font(.headline)
                    Text(model.remoteStatus).font(.callout).pluginSecondaryText()
                }
                Spacer()
                Button(model.settings.certificate == nil ? "Pair remote" : "Reconnect remote") { model.pair() }.disabled(!model.connected || model.busy || model.remoteConnecting)
            }
            if !model.certificateCandidate.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review this monitor’s certificate").font(.headline)
                    Text(model.certificateCandidate).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("Trust only this fingerprint to pair over the encrypted local connection. Approve NeroNook Ark on the physical monitor if it asks.").font(.caption).pluginSecondaryText()
                    Button("Trust certificate & pair") { model.trustCertificate() }.disabled(model.busy)
                }.padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            }
            PluginAdvancedSection(detail: "Connection capabilities, transport details and pairing reset.") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Available on this connection").font(.headline)
                LabeledContent("Model", value: model.info?.device.modelName ?? "Not connected")
                LabeledContent("Volume & mute", value: model.canVolume && model.canMute ? "Direct, with read-back" : "Unavailable")
                LabeledContent("Home, Settings & Sources", value: "Paired remote menus")
                LabeledContent("Brightness & rear lighting", value: "No verified direct control")
                LabeledContent("Direct input selection", value: "Use tested source mappings in the module")
            }.font(.callout)
            Text("The illustration is not a live view of the monitor. Remote keys are sent once; the monitor does not acknowledge whether it applied them. ").font(.caption).pluginSecondaryText()
            HStack {
                Text("Audio uses local HTTP. The remote uses your approved certificate; pairing stays in Keychain.").font(.caption2).pluginSecondaryText()
                Spacer()
                Button("Forget pairing") { model.forgetPairing() }.disabled(model.settings.deviceID.isEmpty || model.busy)
            }
            }
        } footer: {
            Text(model.displayNotice.isEmpty ? model.status : model.displayNotice).font(.callout).pluginSecondaryText().fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
