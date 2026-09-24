import XCTest
@testable import ArkPlugin
import ArkCore
import NookPluginSDK

private actor DelayedMonitor: HTTPTransport {
    private var volume = 50
    private var holdFirstReading = true
    private var pending: CheckedContinuation<Data, Never>?
    var waiting: Bool { pending != nil }
    private func volumeReply(_ value: Int) -> Data { Data("<GetVolumeResponse><CurrentVolume>\(value)</CurrentVolume></GetVolumeResponse>".utf8) }
    func releaseOldPoll() { pending?.resume(returning: volumeReply(10)); pending = nil }
    func send(_ request: URLRequest) async throws -> Data {
        let action = request.value(forHTTPHeaderField: "SOAPAction") ?? ""
        if request.httpMethod == "GET" {
            return Data(#"{"id":"fixture-monitor","device":{"name":"Ark","modelName":"LS55CG970NNXGO"}}"#.utf8)
        }
        if action.contains("#GetVolume") {
            if holdFirstReading { holdFirstReading = false; return await withCheckedContinuation { pending = $0 } }
            return volumeReply(volume)
        }
        if action.contains("#GetMute") { return Data("<GetMuteResponse><CurrentMute>0</CurrentMute></GetMuteResponse>".utf8) }
        if action.contains("#SetVolume") {
            let xml = try XMLTree(request.httpBody!)
            volume = Int(xml.nodes(named: "DesiredVolume").first!.text)!
            return Data("<SetVolumeResponse/>".utf8)
        }
        throw ArkError("Unexpected fixture request")
    }
}
final class RefreshTests: XCTestCase {
    @MainActor func testSDKVolumeQuantizationAndBounds() throws {
        XCTAssertEqual(try ArkModule.audioCommand(.adjustVolume(1.0/16)), .adjustVolume(6))
        XCTAssertEqual(try ArkModule.audioCommand(.adjustVolume(-1.0/64)), .adjustVolume(-2))
        XCTAssertEqual(try ArkModule.audioCommand(.setVolume(0.16)), .volume(16))
        XCTAssertEqual(try ArkModule.audioCommand(.toggleMute), .toggleMute)
        XCTAssertThrowsError(try ArkModule.audioCommand(.setVolume(2)))
    }

    @MainActor func testLatePollCannotOverwriteConfirmedUserCommand() async throws {
        let transport = DelayedMonitor()
        let module = ArkModule(client: ArkClient(transport: transport))
        module.settings = .init(host: "192.168.1.153", deviceID: "fixture-monitor")
        module.connected = true
        module.audio = .init(volume: 50, muted: false)
        module.service = .init(port: 9197, controlPath: "/control", descriptionPath: "/description", actions: ["GetVolume", "SetVolume", "GetMute", "SetMute"])
        module.refresh()
        for _ in 0..<100 { if await transport.waiting { break }; try await Task.sleep(for: .milliseconds(5)) }
        let waiting = await transport.waiting; XCTAssertTrue(waiting)
        XCTAssertFalse(module.busy, "Background refresh must not lock out user controls")
        module.apply(.volume(16))
        for _ in 0..<100 { if !module.busy { break }; try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(module.busy); XCTAssertEqual(module.audio?.volume, 16)
        await transport.releaseOldPoll()
        // Let the stale request finish, including its remaining mute read.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(module.audio?.volume, 16)
        XCTAssertTrue(module.connected); XCTAssertFalse(module.refreshing)
        XCTAssertEqual(module.notice, "Audio setting confirmed by the monitor.")
    }
}
