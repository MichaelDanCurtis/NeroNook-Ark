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
            "notice": .string(notice), "last_read": .string(lastRead?.formatted(date: .omitted, time: .standard) ?? "Never"),
            "paired": .boolean(settings.certificate != nil)
        ]
        if connected, let value = audio?.volume { state["volume"] = .number(Double(value)) }
        if connected, let value = audio?.muted { state["muted"] = .boolean(value) }
        return .init(entry: "monitor/index.html", revision: "ark2", state: state, events: [
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
        try ControlTarget.validate(device: text("device"), host: text("host"), selectedDevice: settings.deviceID, selectedHost: settings.host, connected: connected)
        guard !busy else { throw ArkError("Wait for the monitor to finish. No command was queued.") }
        switch event.name {
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
        }.frame(width: 800, height: 450).preferredColorScheme(.dark)
            .sheet(isPresented: $model.showSetup) { ArkSetup(model: model) }
    }
}
struct ArkSetup: View {
    @ObservedObject var model: ArkModule
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Label("Odyssey Ark setup", systemImage: "display").font(.title2.bold()); Spacer(); Button("Done") { model.showSetup = false }.keyboardShortcut(.defaultAction) }
            Text("Connect directly to your monitor on this network. No Samsung app or cloud account is needed.").foregroundStyle(.secondary)
            HStack {
                TextField("Monitor IP address", text: $model.draftHost)
                Button("Find monitor") { model.discover() }
                Button("Connect") { model.connect() }.buttonStyle(.borderedProminent)
            }.disabled(model.busy)
            if !model.candidates.isEmpty { HStack { Text("Found:").font(.caption); ForEach(model.candidates, id: \.self) { host in Button(host) { model.draftHost = host }.disabled(model.busy) } } }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monitor remote").font(.headline)
                    Text(model.remoteStatus).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.settings.certificate == nil ? "Pair remote" : "Reconnect remote") { model.pair() }.disabled(!model.connected || model.busy || model.remoteConnecting)
            }
            if !model.certificateCandidate.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review this monitor’s certificate").font(.headline)
                    Text(model.certificateCandidate).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text("Trust only this fingerprint to pair over the encrypted local connection. Approve NeroNook Ark on the physical monitor if it asks.").font(.caption).foregroundStyle(.secondary)
                    Button("Trust certificate & pair") { model.trustCertificate() }.disabled(model.busy)
                }.padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Available on this connection").font(.headline)
                LabeledContent("Model", value: model.info?.device.modelName ?? "Not connected")
                LabeledContent("Volume & mute", value: model.canVolume && model.canMute ? "Direct, with read-back" : "Unavailable")
                LabeledContent("Home, Settings & Sources", value: "Paired remote menus")
                LabeledContent("Brightness & rear lighting", value: "No verified direct control")
                LabeledContent("Direct input selection", value: "No verified direct control")
            }.font(.callout)
            Text("The illustration is not a live view of the monitor. Remote keys are sent once; the monitor does not acknowledge whether it applied them. Mac volume-key routing is a separate upcoming SDK feature.").font(.caption).foregroundStyle(.secondary)
            Text(model.notice.isEmpty ? model.status : model.notice).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Audio uses local HTTP. The remote uses your approved certificate; pairing stays in Keychain.").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Forget pairing") { model.forgetPairing() }.disabled(model.settings.deviceID.isEmpty || model.busy)
            }
        }.padding(24).frame(width: 620).preferredColorScheme(.dark)
    }
}
