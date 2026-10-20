import XCTest
@testable import ArkPlugin
import ArkCore
import NookPluginSDK

private actor RecoveringMonitor: HTTPTransport {
    enum Failure { case identity, audio, none }
    private var failure: Failure
    private(set) var writes = 0
    init(_ failure: Failure) { self.failure = failure }
    func recover() { failure = .none }
    func send(_ request: URLRequest) async throws -> Data {
        let action = request.value(forHTTPHeaderField: "SOAPAction") ?? ""
        if action.contains("#Set") { writes += 1; throw ArkError("No writes belong in this read fixture") }
        if request.url?.path.hasPrefix("/api/v2") == true {
            if failure == .identity { throw URLError(.notConnectedToInternet) }
            return Data(#"{"id":"fixture-monitor","device":{"name":"Ark","modelName":"LS55CG970NNXGO"}}"#.utf8)
        }
        if request.url?.path == "/dmr" {
            return Data("<root><device><manufacturer>Samsung</manufacturer><serviceList><service><serviceType>\(SOAP.service)</serviceType><controlURL>/control</controlURL><SCPDURL>/description</SCPDURL></service></serviceList></device></root>".utf8)
        }
        if request.url?.path == "/description" {
            return Data("<scpd><actionList><action><name>GetVolume</name></action><action><name>GetMute</name></action><action><name>SetVolume</name></action><action><name>SetMute</name></action></actionList></scpd>".utf8)
        }
        if action.contains("#GetVolume") {
            if failure == .audio { throw ArkError("Fixture audio temporarily unavailable") }
            return Data("<GetVolumeResponse><CurrentVolume>17</CurrentVolume></GetVolumeResponse>".utf8)
        }
        if action.contains("#GetMute") { return Data("<GetMuteResponse><CurrentMute>0</CurrentMute></GetMuteResponse>".utf8) }
        throw ArkError("Unexpected fixture request")
    }
}

final class RecoveryTests: XCTestCase {
    @MainActor private func visibleNotice(_ module: ArkModule) -> String {
        if case .string(let value)? = module.surface.state["notice"] { return value }
        XCTFail("Missing presented notice"); return ""
    }
    @MainActor private func refresh(_ module: ArkModule) async throws {
        module.refresh()
        for _ in 0..<200 {
            if !module.refreshing { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(module.refreshing)
    }
    @MainActor func testNetworkRecoveryClearsPresentedConnectionIssue() async throws {
        let transport = RecoveringMonitor(.identity)
        let module = ArkModule(client: ArkClient(transport: transport))
        module.settings = .init(host: "192.168.1.153", deviceID: "fixture-monitor")
        try await refresh(module)
        XCTAssertFalse(module.connected)
        XCTAssertFalse(visibleNotice(module).isEmpty)
        await transport.recover()
        try await refresh(module)
        XCTAssertTrue(module.connected)
        XCTAssertEqual(module.audio?.volume, 17)
        XCTAssertEqual(visibleNotice(module), "", "Recovered monitor must not keep the old offline notice")
        let writes = await transport.writes; XCTAssertEqual(writes, 0)
    }
    @MainActor func testAudioRecoveryRestoresUnrelatedCommandAndPairingNotices() async throws {
        for original in ["", "Could not confirm the change. It may have applied; no retry was sent.", "Review the monitor certificate before pairing."] {
            let transport = RecoveringMonitor(.audio)
            let module = ArkModule(client: ArkClient(transport: transport))
            module.settings = .init(host: "192.168.1.153", deviceID: "fixture-monitor")
            module.notice = original
            try await refresh(module)
            XCTAssertTrue(module.connected)
            XCTAssertNil(module.audio)
            XCTAssertEqual(visibleNotice(module), "Fixture audio temporarily unavailable")
            await transport.recover()
            try await refresh(module)
            XCTAssertTrue(module.canVolume)
            XCTAssertEqual(visibleNotice(module), original, "Recovery must preserve a separate command/pairing notice")
            let writes = await transport.writes; XCTAssertEqual(writes, 0)
        }
    }
}
