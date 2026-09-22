import SwiftUI
import NookPluginSDK
import ArkCore

func arkDiagram(model: String?, volume: String, muted: Bool?, connected: Bool, remote: Bool) -> PluginDiagram {
    let accent = connected ? "#64D5F4" : "#8996AA"
    var elements: [PluginDiagramElement] = [
        .init(.box, x: 0, y: 0, w: 640, h: 360, fill: "#0D1521", radius: 18),
        .init(.text, x: 28, y: 20, w: 400, h: 30, fill: "#E6F4FF", text: "ODYSSEY ARK", font: 24),
        .init(.text, x: 28, y: 55, w: 450, h: 22, fill: "#899AAF", text: model ?? "Connect your monitor", font: 13),
        .init(.box, x: 38, y: 98, w: 350, h: 186, fill: "#080C13", stroke: "#465B75", radius: 18),
        .init(.box, x: 49, y: 110, w: 328, h: 161, fill: "#152E4A", radius: 12),
        .init(.box, x: 193, y: 285, w: 38, h: 31, fill: "#3D4A5B", radius: 4),
        .init(.box, x: 155, y: 315, w: 115, h: 10, fill: "#344254", radius: 5),
        .init(.text, x: 107, y: 163, w: 215, h: 43, fill: accent, text: "55\" · 4K", font: 35),
        .init(.text, x: 88, y: 215, w: 250, h: 20, fill: "#A5C4DD", text: connected ? "DIRECT LOCAL CONNECTION" : "WAITING FOR CONNECTION", font: 11),
        .init(.box, x: 413, y: 99, w: 199, h: 120, fill: "#182638", radius: 14),
        .init(.text, x: 431, y: 115, w: 165, h: 18, fill: "#899AAF", text: "MONITOR VOLUME", font: 11),
        .init(.text, x: 431, y: 144, w: 161, h: 45, fill: accent, text: volume, font: 38),
        .init(.text, x: 431, y: 194, w: 165, h: 18, fill: "#CCDDEC", text: muted.map { $0 ? "Muted" : "Sound on" } ?? "Audio unavailable", font: 12),
        .init(.box, x: 413, y: 233, w: 199, h: 89, fill: "#182638", radius: 14),
        .init(.text, x: 431, y: 247, w: 165, h: 18, fill: "#899AAF", text: "REMOTE", font: 11),
        .init(.text, x: 431, y: 276, w: 165, h: 23, fill: "#E6F4FF", text: remote ? "Connected" : "Pair to enable", font: 19)
    ]
    for i in 0..<4 { elements.append(.init(.line, x: 61, y: 121 + Double(i) * 7, w: 304, h: 0, stroke: "#1D3D5F", weight: 1)) }
    return .init(id: "ark", title: "Monitor overview", width: 640, height: 360, summary: "Odyssey Ark. \(connected ? "Connected" : "Disconnected"). Volume \(volume). Remote \(remote ? "connected" : "not connected").", elements: elements)
}
struct ArkSettings: View {
    @ObservedObject var model: ArkModule
    @State private var volume = 0.0
    @State private var muted = false
    private let blue = Color(red: 0.39, green: 0.83, blue: 0.96)
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "display").font(.system(size: 34)).foregroundStyle(blue)
                VStack(alignment: .leading) { Text("Odyssey Ark").font(.title.bold()); Text(model.info?.device.modelName ?? "Your monitor, directly connected").foregroundStyle(.secondary) }
                Spacer()
                Text(model.connected ? "Connected" : "Not connected").foregroundStyle(model.connected ? blue : .secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Monitor IP address", text: $model.draftHost)
                    Button("Find monitor") { model.discover() }
                    Button("Connect") { model.connect() }.buttonStyle(.borderedProminent).tint(blue).foregroundStyle(.black)
                }.disabled(model.busy)
                if !model.candidates.isEmpty { HStack { Text("Found:").foregroundStyle(.secondary); ForEach(model.candidates, id: \.self) { host in Button(host) { model.draftHost = host }.disabled(model.busy) } } }
                Text("Uses only your local network. No Samsung desktop app or cloud account required.").font(.caption).foregroundStyle(.secondary)
            }.padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Sound").font(.headline); Spacer(); Text(model.volume).font(.title2.monospacedDigit()).foregroundStyle(blue) }
                    Slider(value: $volume, in: 0...100, step: 1).disabled(!model.canVolume || model.busy)
                    HStack { Text("Volume · \(Int(volume))").font(.caption); Spacer(); Button("Apply volume") { model.apply(volume: Int(volume)) }.disabled(!model.canVolume || model.busy) }
                    Divider()
                    Toggle("Mute", isOn: $muted).disabled(!model.canMute || model.busy)
                    Button("Apply mute") { model.apply(muted: muted) }.disabled(!model.canMute || model.busy)
                    Text("Audio changes are checked against the monitor's live reading.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(16).frame(maxWidth: .infinity).frame(height: 290).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("Remote").font(.headline); Spacer(); Button(model.remoteReady ? "Reconnect" : "Pair remote") { model.pair() }.disabled(!model.connected || model.busy) }
                    Text(model.remoteStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .topLeading)
                    VStack(spacing: 6) {
                        remoteButton(.up, "chevron.up")
                        HStack(spacing: 8) { remoteButton(.left, "chevron.left"); remoteButton(.enter, "checkmark"); remoteButton(.right, "chevron.right") }
                        remoteButton(.down, "chevron.down")
                        HStack { Button("Back") { model.press(.back) }; Button("Settings") { model.press(.menu) }; Button("Sources") { model.press(.source) } }
                    }.frame(maxWidth: .infinity).disabled(!model.remoteReady || !model.connected || model.busy)
                    Text("Navigation keys are sent once. Use your physical remote if the monitor does not respond.").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity).frame(height: 290).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
            }
            if !model.certificateCandidate.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monitor certificate · SHA-256").font(.caption.bold())
                        Text(model.certificateCandidate).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    }
                    Button("Trust certificate & pair") { model.trustCertificate() }.disabled(model.busy)
                }.padding(10).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            Text(model.notice.isEmpty ? "Connect to read the monitor's status." : model.notice).font(.callout).lineLimit(3).frame(minHeight: 40, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 6) {
                Text("Direct brightness, picture mode, KVM and Multi View settings are not exposed by the verified HTTP interface. The remote can open the monitor's menus.")
                Text("Audio/status use local HTTP on your trusted network. The remote uses encrypted TLS pinned to your approved monitor certificate; tokens stay in Keychain.")
            }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Button("Refresh") { model.refresh() }.disabled(model.busy || model.settings.host.isEmpty)
                Button("Forget remote pairing") { model.forgetPairing() }.disabled(model.settings.deviceID.isEmpty || model.busy)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Text("Ark module · 0.1.0").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(24) }.frame(width: 740, height: 710).background(Color(red: 0.05, green: 0.077, blue: 0.12)).preferredColorScheme(.dark)
            .onChange(of: model.audio?.volume) { _, value in if let value { volume = Double(value) } }
            .onChange(of: model.audio?.muted) { _, value in if let value { muted = value } }
            .onAppear { if let v = model.audio?.volume { volume = Double(v) }; if let m = model.audio?.muted { muted = m } }
    }
    private func remoteButton(_ key: RemoteKey, _ symbol: String) -> some View {
        Button { model.press(key) } label: { Image(systemName: symbol).frame(width: 32, height: 24) }.help(key.title)
    }
}
