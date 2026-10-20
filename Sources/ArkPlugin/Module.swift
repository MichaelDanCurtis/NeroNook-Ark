import AppKit
import SwiftUI
import NookPluginSDK
import ArkCore

let moduleID = "cafe.nero.plugin.ark"
struct Settings: Codable { var host = ""; var deviceID = ""; var certificate: String?; var sourceMapping: KeyboardSourceMapping?; var keyboardLink: KeyboardSourceLink? }
@MainActor final class ArkModule: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var settings = Settings()
    @Published var draftHost = ""
    @Published var candidates: [String] = []
    @Published var info: DeviceInfo?
    @Published var audio: AudioState?
    @Published var service: RenderingService?
    @Published var status = "Connect your Odyssey Ark"
    @Published var notice = ""
    // A poll's transient problem must not replace a command outcome or pairing
    // review. Recovery removes only this read issue, revealing the saved notice.
    @Published private var readIssue = ""
    var displayNotice: String { readIssue.isEmpty ? notice : readIssue }
    @Published var busy = false
    @Published var connected = false
    @Published var remoteReady = false
    @Published var remoteConnecting = false
    @Published var certificateCandidate = ""
    @Published var remoteStatus = "Remote not connected"
    @Published var lastRead: Date?
    @Published var showSetup = false
    private var customViews = false
    private var volumeInterface = false
    private var recentVolumeRequests: [UUID: Double] = [:]
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
    private var catalogDraft: [PluginCatalogEntry] = []
    var sourcePeers: [PluginCatalogEntry] = []
    var sourcePeerNames: [String: String] = [:]
    private var sourceDevices: [String: String] = [:]
    private var sourceGate = KeyboardSourceGate()
    @Published var sourceLinkStatus = "Source following is off"
    private var subscribedSources = Set<PluginActionAddress>()
    private var sourceTest: InputSource?
    var sourceLinkActive: Bool { sourceGate.isArmed }
    var keyboardLink: KeyboardSourceLink { settings.keyboardLink ?? .init() }
    var sourceMapping: KeyboardSourceMapping { settings.sourceMapping ?? .init() }
    func setSourceMapping(channel: Int, source: InputSource) throws {
        var mapping = sourceMapping; try mapping.set(channel: channel, source: source)
        settings.sourceMapping = mapping; sourceGate.disarm(); sourceLinkStatus = "Mapping changed; enable following again."; try saveSourceMapping(); publish()
    }
    private func saveSourceMapping() throws {
        guard let storage else { throw ArkError("Plugin settings storage is unavailable.") }
        try JSONEncoder().encode(settings).write(to: storage, options: .atomic)
    }
    func testSource(_ source: InputSource) {
        press(source.remoteKey, onSent: { [weak self] in self?.sourceTest = source })
    }
    func confirmSource(_ source: InputSource) throws {
        guard sourceTest == source else { throw ArkError("Test this input on the physical monitor before confirming it.") }
        var mapping = sourceMapping; mapping.confirmed.insert(source); settings.sourceMapping = mapping
        try saveSourceMapping(); sourceTest = nil; notice = "You verified \(source.title) on this monitor."; publish()
    }
    func configureSourceLink(provider: String, enabled: Bool) throws {
        guard !busy else { throw ArkError("Wait for the current monitor command.") }
        var link = keyboardLink
        if enabled {
            guard sourcePeers.contains(where: { $0.address.plugin == provider }), let keyboard = sourceDevices[provider], !keyboard.isEmpty,
                  connected, remoteReady, sourceMapping.sources.allSatisfy(sourceMapping.confirmed.contains) else {
                throw ArkError("Allow keyboard status and choice channels in Module settings, enable its watch, and verify all mapped inputs first.")
            }
            link.provider = provider; link.keyboard = keyboard; link.name = sourcePeerNames[provider] ?? "Selected keyboard"
        }
        link.enabled = enabled; settings.keyboardLink = link; try saveSourceMapping()
        sourceGate.disarm(); if enabled { sourceGate.arm(at: Date().timeIntervalSince1970) }
        sourceLinkStatus = enabled ? "Following \(link.name) · fresh choices only" : "Source following is off"
        publish()
    }
    private func receiveSourceBus(_ bus: PluginBusMessage) {
        switch bus.operation {
        case .catalog:
            if let entries = bus.catalog {
                if entries.isEmpty { catalogDraft = [] }; catalogDraft += entries
            }
            if bus.complete == true {
                sourcePeers = catalogDraft.filter { $0.channel?.kind == .event && $0.address.name == "host_switch_choices" }
                let desired = Set(catalogDraft.filter { entry in
                    sourcePeers.contains(where: { peer in peer.address.plugin == entry.address.plugin }) && ["host_switch_status", "host_switch_choices"].contains(entry.address.name)
                }.map(\.address))
                for address in subscribedSources.subtracting(desired) { send(.init(.unsubscribe, address: address)) }
                for address in desired.subtracting(subscribedSources) { send(.init(.subscribe, address: address)) }
                subscribedSources = desired
                if keyboardLink.enabled, !sourcePeers.contains(where: { $0.address.plugin == keyboardLink.provider }) {
                    sourceGate.disarm(); sourceLinkStatus = "Keyboard access changed; enable this link again after reconnecting."
                }
                publish()
            }
        case .event where bus.address?.name == "host_switch_status":
            guard let address = bus.address, address.name == "host_switch_status", sourcePeers.contains(where: { $0.address.plugin == address.plugin }),
                  case .string(let device)? = bus.values?["device"], case .string(let name)? = bus.values?["name"],
                  case .boolean(let watching)? = bus.values?["watching"] else { return }
            sourcePeerNames[address.plugin] = name
            if watching { sourceDevices[address.plugin] = device } else { sourceDevices[address.plugin] = nil }
            if keyboardLink.enabled, keyboardLink.provider == address.plugin, (!watching || keyboardLink.keyboard != device) {
                sourceGate.disarm(); sourceLinkStatus = "Keyboard watch or selection changed; enable this link again."
            }
            publish()
        case .event:
            guard keyboardLink.enabled, sourceGate.isArmed else { return }
            guard let address = bus.address, address.name == "host_switch_choices", case .string(let event)? = bus.values?["event_id"],
                  UUID(uuidString: event) == bus.requestID, case .string(let keyboard)? = bus.values?["device"],
                  case .number(let channel)? = bus.values?["channel"], case .number(let observedAt)? = bus.values?["observed_at"] else { return }
            do {
                let source = try sourceGate.accept(id: bus.requestID, provider: address.plugin, keyboard: keyboard, channel: channel, observedAt: observedAt,
                                                  now: Date().timeIntervalSince1970, link: keyboardLink, mapping: sourceMapping, available: connected && remoteReady && !busy)
                sourceLinkStatus = "Channel \(Int(channel)) → \(source.title) requested"; press(source.remoteKey)
            } catch { sourceLinkStatus = error.localizedDescription; publish() }
        default: break
        }
    }
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
            guard message.type == "hello" else { NSApp.terminate(nil); return }; session = message.session; PluginAppearanceStore.shared.beginSession(pluginID:moduleID,session:message.session)
            volumeInterface = message.features?.contains("volume-v1") == true
            customViews = message.features?.contains("custom-views-v1") == true
            emit("ready", features: ["appearance-v1", "actions-v1", "dashboard-v1", "panels-v1"] + (customViews ? ["custom-views-v1"] : []) + (volumeInterface ? ["volume-v1"] : []))
            let device = PluginParameter("device", .string)
            send(.init(.register, registration: .init(actions: [
                .init("read_status", title: "Read Ark status", output: statusSchema),
                .init("set_volume", title: "Set Ark volume", input: .init([device, .init("volume", .number, minimum: 0, maximum: 100)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60),
                .init("set_mute", title: "Set Ark mute", input: .init([device, .init("muted", .boolean)]), output: .init([.init("message", .string)]), effect: .externalChange, timeoutSeconds: 60)
            ], channels: [.init("status", title: "Ark status", kind: .state, schema: statusSchema)])))
            send(.init(.discover)); refresh(); publish(); return
        }
        guard message.session == session else { NSApp.terminate(nil); return }; if message.type == "appearance" { _ = PluginAppearanceStore.shared.receive(message); return }
        if message.type == "volumeCommand", let command = message.volumeCommand {
            handleVolume(command); return
        }
        if message.type == "visibility" { visible = message.visible ?? false }
        if message.type == "action" {
            switch message.action { case "configure": showSetup = true; showWindow(); case "controls": showWindow(); case "refresh": refresh(); default: break }
        }
        if message.type == "viewEvent", let event = message.viewEvent {
            do { try handleView(event) } catch { notice = error.localizedDescription }; publish(); return
        }
        if message.type == "bus", let bus = message.bus { if bus.operation == .execute { execute(bus) } else { receiveSourceBus(bus) } }
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
    var volumeEndpoint: PluginVolumeEndpoint? {
        guard !settings.deviceID.isEmpty else { return nil }
        return .init(id: settings.deviceID, name: "Odyssey Ark", available: connected,
            volume: audio?.volume.map { Double($0) / 100 }, muted: audio?.muted,
            canSetVolume: canVolume, canMute: canMute, observedAt: lastRead?.timeIntervalSince1970 ?? 0)
    }
    static func audioCommand(_ operation: PluginVolumeOperation) throws -> AudioCommand {
        try operation.validate()
        switch operation {
        case .setVolume(let n): return .volume(Int((n * 100).rounded()))
        case .adjustVolume(let n): return .adjustVolume(n > 0 ? max(1, Int((n * 100).rounded())) : min(-1, Int((n * 100).rounded())))
        case .setMuted(let n): return .mute(n)
        case .toggleMute: return .toggleMute
        }
    }
    private func handleVolume(_ command: PluginVolumeCommand) {
        let reply: (Error?) -> Void = { [weak self] error in
            guard let self else { return }
            self.emit("volumeResult", volumeResult: .init(requestID: command.requestID, endpointID: command.endpointID,
                state: error == nil ? self.volumeEndpoint : nil, error: error.map { String($0.localizedDescription.prefix(350)) }))
        }
        do {
            guard volumeInterface else { throw ArkError("Volume interface was not negotiated.") }
            try command.validate()
            let now = Date().timeIntervalSince1970
            recentVolumeRequests = recentVolumeRequests.filter { $0.value > now }
            guard recentVolumeRequests[command.requestID] == nil, recentVolumeRequests.count < 256 else { throw ArkError("Repeated volume gesture refused.") }
            recentVolumeRequests[command.requestID] = command.expiresAt
            guard command.endpointID == settings.deviceID else { throw ArkError("The selected monitor changed. No change sent.") }
            apply(try Self.audioCommand(command.operation), expiresAt: command.expiresAt, completed: reply)
        } catch { reply(error) }
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
        connected = false; audio = nil; service = nil; readIssue = ""; notice = "Checking the monitor…"
        let host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { busy = false; publish() }
            do {
                let endpoint = try Endpoint(host), value = try await client.info(endpoint)
                settings = .init(host: endpoint.host, deviceID: value.id, certificate: settings.deviceID == value.id ? settings.certificate : nil, sourceMapping: settings.deviceID == value.id ? settings.sourceMapping : nil, keyboardLink: settings.deviceID == value.id ? settings.keyboardLink : nil); certificateCandidate = ""; info = value
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
            catch { if readGeneration == generation { fail(error, fromRead: true) } }
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
        readIssue = audioError ?? ""
        if audioError != nil { status = "Ark connected · audio unavailable" }
        else { status = "Ark · Volume \(volume)\(audio?.muted == true ? " · Muted" : "")" }
    }
    private func fail(_ error: Error, fromRead: Bool = false) {
        connected = false; audio = nil; service = nil; remote.disconnect(); remoteReady = false; remoteConnecting = false; remoteStatus = "Remote not connected"; status = "Ark unavailable"
        let message = String(error.localizedDescription.prefix(350))
        if fromRead { readIssue = message } else { readIssue = ""; notice = message }
    }
    func apply(volume: Int? = nil, muted: Bool? = nil, request: UUID? = nil) {
        guard (volume != nil) != (muted != nil) else { finish("Choose one audio setting.", request: request, failed: true); return }
        apply(volume.map(AudioCommand.volume) ?? .mute(muted!), request: request)
    }
    func apply(_ command: AudioCommand, request: UUID? = nil, expiresAt: Double? = nil, completed: ((Error?) -> Void)? = nil) {
        guard !busy, connected, let service else { let error = ArkError("Monitor unavailable or busy. No change sent."); finish(error.localizedDescription, request: request, failed: true); completed?(error); return }
        let host = settings.host, id = settings.deviceID
        cancelRefresh(); busy = true; notice = "Waiting for the monitor to confirm…"
        Task {
            defer { busy = false; publish() }
            do {
                audio = try await client.change(Endpoint(host), id: id, service: service, command: command, expiresAt: expiresAt)
                lastRead = Date(); status = "Ark · Volume \(self.volume)\(audio?.muted == true ? " · Muted" : "")"
                finish("Audio setting confirmed by the monitor.", request: request); completed?(nil)
            } catch { connected = false; audio = nil; finish(error.localizedDescription, request: request, failed: true); completed?(error) }
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
    func press(_ key: RemoteKey, onSent: (() -> Void)? = nil) {
        guard !busy, connected, remoteReady else { return }; cancelRefresh(); busy = true
        Task {
            defer { busy = false; publish() }
            do {
                _ = try await client.info(Endpoint(settings.host), expectedID: settings.deviceID)
                try await remote.send(key); onSent?(); notice = "\(key.title) sent. The monitor does not report whether it applied the key."
            } catch { notice = "Remote command failed; no retry was sent." }
        }
    }
    private func finish(_ text: String, request: UUID?, failed: Bool = false) {
        notice = String(text.prefix(350))
        if let request { send(.init(.update, requestID: request, update: .init(failed ? .failed : .succeeded, message: String(text.prefix(280)), values: failed ? [:] : ["message": .string(String(text.prefix(280)))]))) }
    }
    private func send(_ bus: PluginBusMessage) { emit("bus", bus: bus) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil, volumeResult: PluginVolumeResult? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: moduleID, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus, volumeResult: volumeResult).encoded()) } catch { NSApp.terminate(nil) }
    }
    func publish() {
        var snapshot = PluginSnapshot(title: "Odyssey Ark", status: status, activity: connected ? "Ark · Volume \(volume)\(audio?.muted == true ? " · Muted" : "")" : "Ark · offline",
            actions: customViews ? [] : [.init("controls", "Monitor controls", symbol: "slider.horizontal.3")], badge: connected ? "Connected" : "Setup needed",
            panels: [customViews ? .init("monitor", "Monitor", customView: surface) : .init("monitor", "Monitor", sections: [.init("Odyssey Ark", "Open Monitor controls for sound and remote navigation. Upgrade NeroNook for controls inside the Nook.")])])
        if volumeInterface { snapshot.volumeEndpoints = volumeEndpoint.map { [$0] } ?? [] }
        emit("snapshot", snapshot: snapshot); send(.init(.publish, address: .init(moduleID, "status"), values: values, lifetime: 8))
    }
    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 450), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Odyssey Ark controls"; w.contentView = NSHostingView(rootView: ArkWindow(model: self).pluginThemed()); w.isReleasedWhenClosed = false; w.center(); window = w
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
