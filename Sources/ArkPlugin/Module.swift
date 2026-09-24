import AppKit
import SwiftUI
import NookPluginSDK
import ArkCore

let moduleID = "cafe.nero.plugin.ark"
struct Settings: Codable { var host = ""; var deviceID = ""; var certificate: String? }
@MainActor final class ArkModule: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var settings = Settings()
    @Published var draftHost = ""
    @Published var candidates: [String] = []
    @Published var info: DeviceInfo?
    @Published var audio: AudioState?
    @Published var service: RenderingService?
    @Published var status = "Connect your Odyssey Ark"
    @Published var notice = ""
    @Published var busy = false
    @Published var connected = false
    @Published var remoteReady = false
    @Published var remoteConnecting = false
    @Published var certificateCandidate = ""
    @Published var remoteStatus = "Remote not connected"
    @Published var lastRead: Date?
    @Published var showSetup = false
    private var customViews = false
    private let client: ArkClient
    init(client: ArkClient = ArkClient()) { self.client = client; super.init() }
    private let remote = ArkRemote()
    private let input = InputReader()
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var timer: Timer?
    private var ticks = 0
    private var refreshTask: Task<Void, Never>?
    private var readGeneration = UUID()
    @Published var refreshing = false
    private var visible = true
    private var window: NSWindow?
    private var runs = Set<UUID>()
    let hosted = CommandLine.arguments.contains("--neronook-plugin")
    private var storage: URL? { try? PluginStorage.directory(id: moduleID).appendingPathComponent("settings.json") }
    var volume: String { audio?.volume.map(String.init) ?? "—" }
    var canVolume: Bool { connected && service?.actions.isSuperset(of: ["GetVolume", "SetVolume"]) == true && audio?.volume != nil }
    var canMute: Bool { connected && service?.actions.isSuperset(of: ["GetMute", "SetMute"]) == true && audio?.muted != nil }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let storage, let data = try? Data(contentsOf: storage), let value = try? JSONDecoder().decode(Settings.self, from: data) { settings = value; draftHost = value.host }
        remote.onCertificate = { [weak self] fingerprint in
            guard let self else { return }; self.certificateCandidate = fingerprint
            self.notice = "Review the monitor certificate below, then trust it to enable encrypted pairing."
            self.publish()
        }
        remote.onChange = { [weak self] text, token in
            guard let self else { return }; self.remoteStatus = text; self.remoteReady = self.remote.connected; self.remoteConnecting = self.remote.connecting
            if let token { do { try PairingStore.save(token, for: self.settings.deviceID) } catch { self.notice = "Remote connected, but its pairing token could not be saved in Keychain." } }
            self.publish()
        }
        if hosted { input.start { [weak self] message in Task { @MainActor in guard let message else { NSApp.terminate(nil); return }; self?.receive(message) } } }
        else { showWindow(); refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.publish(); self.ticks += 1
            if self.ticks % ((self.visible || self.window?.isVisible == true) ? 2 : 15) == 0 { self.refresh() }
        } }
    }
    private func receive(_ message: PluginMessage) {
        guard message.pluginID == moduleID else { NSApp.terminate(nil); return }
        if session == nil {
            guard message.type == "hello" else { NSApp.terminate(nil); return }; session = message.session
            customViews = message.features?.contains("custom-views-v1") == true
            emit("ready", features: ["actions-v1", "dashboard-v1", "panels-v1"] + (customViews ? ["custom-views-v1"] : []))
            let device = PluginParameter("device", .string)
            send(.init(.register, registration: .init(actions: [
                .init("read_status", title: "Read Ark status", output: statusSchema),
                .init("set_volume", title: "Set Ark volume", input: .init([device, .init("volume", .number, minimum: 0, maximum: 100)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60),
                .init("set_mute", title: "Set Ark mute", input: .init([device, .init("muted", .boolean)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60)
            ], channels: [.init("status", title: "Ark status", kind: .state, schema: statusSchema)])))
            refresh(); publish(); return
        }
        guard message.session == session else { NSApp.terminate(nil); return }
        if message.type == "visibility" { visible = message.visible ?? false }
        if message.type == "action" {
            switch message.action { case "configure": showSetup = true; showWindow(); case "controls": showWindow(); case "refresh": refresh(); default: break }
        }
        if message.type == "viewEvent", let event = message.viewEvent {
            do { try handleView(event) } catch { notice = error.localizedDescription }; publish(); return
        }
        if message.type == "bus", let bus = message.bus, bus.operation == .execute { execute(bus) }
    }
    private func execute(_ bus: PluginBusMessage) {
        guard bus.address?.plugin == moduleID, !runs.contains(bus.requestID), runs.count < 1000 else { finish("Duplicate request or session limit reached.", request: bus.requestID, failed: true); return }
        runs.insert(bus.requestID)
        if bus.address?.name == "read_status" { send(.init(.update, requestID: bus.requestID, update: .init(.succeeded, values: values))); return }
        guard !busy, connected, case .string(let id)? = bus.values?["device"], !id.isEmpty, id == settings.deviceID else { finish("Choose the connected monitor and wait for the current operation.", request: bus.requestID, failed: true); return }
        if bus.address?.name == "set_volume", case .number(let n)? = bus.values?["volume"], n.isFinite, n.rounded() == n, (0...100).contains(n) { apply(volume: Int(n), request: bus.requestID) }
        else if bus.address?.name == "set_mute", case .boolean(let value)? = bus.values?["muted"] { apply(muted: value, request: bus.requestID) }
        else { finish("Unsupported action or invalid setting.", request: bus.requestID, failed: true) }
    }
    var statusSchema: PluginValueSchema { .init([
        .init("connected", .boolean), .init("device", .string), .init("message", .string),
        .init("volume", .number, required: false, minimum: 0, maximum: 100), .init("muted", .boolean, required: false),
        .init("can_set_volume", .boolean), .init("can_set_mute", .boolean)
    ]) }
    var values: [String: PluginValue] {
        var value: [String: PluginValue] = ["connected": .boolean(connected), "device": .string(settings.deviceID), "message": .string(String(status.prefix(280))), "can_set_volume": .boolean(canVolume), "can_set_mute": .boolean(canMute)]
        if connected, let volume = audio?.volume { value["volume"] = .number(Double(volume)) }
        if connected, let muted = audio?.muted { value["muted"] = .boolean(muted) }
        return value
    }
    func discover() {
        guard !busy else { return }; cancelRefresh(); busy = true; notice = "Looking for Samsung displays on your network…"
        Task {
            var found: [String] = []
            for host in await Discovery.samsungHosts() {
                if let endpoint = try? Endpoint(host), (try? await client.info(endpoint)) != nil { found.append(host) }
            }
            candidates = found; if draftHost.isEmpty, found.count == 1 { draftHost = found[0] }
            notice = found.isEmpty ? "No Ark found. Enter its IP address from the monitor's Network settings." : "Found \(found.count) Ark monitor(s). Select an address and Connect."
            busy = false; publish()
        }
    }
    func connect() {
        guard !busy else { return }; cancelRefresh(); busy = true; remote.disconnect(); remoteReady = false; remoteConnecting = false; remoteStatus = "Remote not connected"
        connected = false; audio = nil; service = nil; notice = "Checking the monitor…"
        let host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false; publish() }
            do {
                let endpoint = try Endpoint(host), value = try await client.info(endpoint)
                settings = .init(host: endpoint.host, deviceID: value.id, certificate: settings.deviceID == value.id ? settings.certificate : nil); certificateCandidate = ""; info = value
                guard let storage else { throw ArkError("Could not open plugin settings storage.") }
                try JSONEncoder().encode(settings).write(to: storage, options: .atomic)
                try await read(endpoint); notice = "Connected to \(value.device.modelName)."
            } catch { fail(error) }
        }
    }
    private func cancelRefresh() {
        readGeneration = UUID(); refreshTask?.cancel(); refreshTask = nil; refreshing = false
    }
    func refresh() {
        guard !busy, refreshTask == nil, !settings.host.isEmpty, !settings.deviceID.isEmpty else { return }
        let generation = UUID(); readGeneration = generation; refreshing = true
        let host = settings.host
        refreshTask = Task {
            defer { if readGeneration == generation { refreshTask = nil; refreshing = false; publish() } }
            do { try await read(Endpoint(host), generation: generation) }
            catch { if readGeneration == generation { fail(error) } }
        }
    }
    private func read(_ endpoint: Endpoint, generation: UUID? = nil) async throws {
        let value = try await client.info(endpoint, expectedID: settings.deviceID)
        var found = service
        var state: AudioState?
        var audioError: String?
        do {
            if found == nil { found = try await client.service(endpoint) }
            if let found { state = try await client.audio(endpoint, service: found) }
        } catch { found = nil; audioError = error.localizedDescription }
        // A user command invalidates an older poll before it can overwrite the command result.
        guard generation == nil || generation == readGeneration else { throw CancellationError() }
        try Task.checkCancellation()
        info = value; connected = true; service = found; audio = state; lastRead = Date()
        if let audioError { status = "Ark connected · audio unavailable"; notice = audioError }
        else { status = "Ark · Volume \(volume)\(audio?.muted == true ? " · Muted" : "")" }
    }
    private func fail(_ error: Error) { connected = false; audio = nil; service = nil; remote.disconnect(); remoteReady = false; remoteConnecting = false; remoteStatus = "Remote not connected"; status = "Ark unavailable"; notice = String(error.localizedDescription.prefix(350)) }
    func apply(volume: Int? = nil, muted: Bool? = nil, request: UUID? = nil) {
        guard (volume != nil) != (muted != nil) else { finish("Choose one audio setting.", request: request, failed: true); return }
        apply(volume.map(AudioCommand.volume) ?? .mute(muted!), request: request)
    }
    func apply(_ command: AudioCommand, request: UUID? = nil) {
        guard !busy, connected, let service else { finish("Monitor unavailable or busy. No change sent.", request: request, failed: true); return }
        let host = settings.host, id = settings.deviceID
        cancelRefresh(); busy = true; notice = "Waiting for the monitor to confirm…"
        Task {
            defer { busy = false; publish() }
            do {
                audio = try await client.change(Endpoint(host), id: id, service: service, command: command)
                lastRead = Date(); status = "Ark · Volume \(self.volume)\(audio?.muted == true ? " · Muted" : "")"
                finish("Audio setting confirmed by the monitor.", request: request)
            } catch { connected = false; audio = nil; finish(error.localizedDescription, request: request, failed: true) }
        }
    }
    func pair() {
        guard !busy, connected, !remoteConnecting else { return }; cancelRefresh(); busy = true
        Task {
            defer { busy = false; publish() }
            do {
                let endpoint = try Endpoint(settings.host); _ = try await client.info(endpoint, expectedID: settings.deviceID)
                remote.connect(endpoint, token: settings.certificate == nil ? nil : try PairingStore.token(for: settings.deviceID), certificate: settings.certificate)
            } catch { remoteStatus = error.localizedDescription }
        }
    }
    func trustCertificate() {
        guard connected, !busy, certificateCandidate.count == 64, certificateCandidate.allSatisfy({ $0.isHexDigit }), let storage else { return }
        settings.certificate = certificateCandidate
        do { try JSONEncoder().encode(settings).write(to: storage, options: .atomic); certificateCandidate = ""; pair() }
        catch { notice = "Could not save the monitor certificate." }
    }
    func forgetPairing() {
        remote.disconnect(); remoteReady = false; remoteConnecting = false
        do { try PairingStore.remove(settings.deviceID); remoteStatus = "Pairing token removed from this Mac." } catch { remoteStatus = "Could not remove the pairing token." }
    }
    func press(_ key: RemoteKey) {
        guard !busy, connected, remoteReady else { return }; cancelRefresh(); busy = true
        Task {
            defer { busy = false; publish() }
            do {
                _ = try await client.info(Endpoint(settings.host), expectedID: settings.deviceID)
                try await remote.send(key); notice = "\(key.title) sent. The monitor does not report whether it applied the key."
            } catch { notice = "Remote command failed; no retry was sent." }
        }
    }
    private func finish(_ text: String, request: UUID?, failed: Bool = false) {
        notice = String(text.prefix(350))
        if let request { send(.init(.update, requestID: request, update: .init(failed ? .failed : .succeeded, message: String(text.prefix(280)), values: failed ? [:] : ["message": .string(String(text.prefix(280)))]))) }
    }
    private func send(_ bus: PluginBusMessage) { emit("bus", bus: bus) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: moduleID, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus).encoded()) } catch { NSApp.terminate(nil) }
    }
    func publish() {
        let snapshot = PluginSnapshot(title: "Odyssey Ark", status: status, activity: connected ? "Ark · Volume \(volume)\(audio?.muted == true ? " · Muted" : "")" : "Ark · offline",
            actions: customViews ? [] : [.init("controls", "Monitor controls", symbol: "slider.horizontal.3")], badge: connected ? "Connected" : "Setup needed",
            panels: [customViews ? .init("monitor", "Monitor", customView: surface) : .init("monitor", "Monitor", sections: [.init("Odyssey Ark", "Open Monitor controls for sound and remote navigation. Upgrade NeroNook for controls inside the Nook.")])])
        emit("snapshot", snapshot: snapshot); send(.init(.publish, address: .init(moduleID, "status"), values: values, lifetime: 8))
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 450), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Odyssey Ark controls"; w.contentView = NSHostingView(rootView: ArkWindow(model: self)); w.isReleasedWhenClosed = false; w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
private final class InputReader: @unchecked Sendable {
    private var lines = PluginLines(); private let queue = DispatchQueue(label: "ArkPlugin.input")
    func start(_ receive: @escaping @Sendable (PluginMessage?) -> Void) {
        FileHandle.standardInput.readabilityHandler = { [weak self] file in
            let data = file.availableData; guard !data.isEmpty else { receive(nil); return }
            self?.queue.async { [weak self] in guard let self else { return }; do { for message in try self.lines.append(data) { receive(message) } } catch { receive(nil) } }
        }
    }
}
