import XCTest
@testable import ArkCore

private actor StubHTTP: HTTPTransport {
    var responses: [Data]
    var requests: [URLRequest] = []
    init(_ responses: [String]) { self.responses = responses.map { Data($0.utf8) } }
    func send(_ request: URLRequest) async throws -> Data {
        requests.append(request); guard !responses.isEmpty else { throw ArkError("Unexpected request") }; return responses.removeFirst()
    }
}
final class ArkTests: XCTestCase {
    let info = #"{"id":"fixture-monitor","device":{"name":"55&quot; Odyssey Ark","modelName":"LS55CG970NNXGO","PowerState":"on","resolution":"3840x2160"}}"#
    let volume = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:GetVolumeResponse xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\"><CurrentVolume>23</CurrentVolume></u:GetVolumeResponse></s:Body></s:Envelope>"
    let mute = "<GetMuteResponse><CurrentMute>0</CurrentMute></GetMuteResponse>"
    let service = RenderingService(port: 9197, controlPath: "/upnp/control/RenderingControl1", descriptionPath: "/RenderingControl_1.xml", actions: ["GetVolume", "SetVolume", "GetMute", "SetMute"])
    func testPrivateAddressBoundary() throws {
        for host in ["192.168.1.153", "10.1.2.3", "172.16.1.2"] { XCTAssertEqual(try Endpoint(host).host, host) }
        for host in ["127.0.0.1", "8.8.8.8", "169.254.169.254", "192.168.1.153:80", "host.local", "192.168.1.256", "192.168.1.0", "192.168.1.153/path"] { XCTAssertThrowsError(try Endpoint(host)) }
        XCTAssertThrowsError(try Endpoint("192.168.1.153").url(port: 9197, path: "//other/path"))
        XCTAssertThrowsError(try Endpoint("192.168.1.153").url(port: 9197, path: "http://other/path"))
    }
    func testIdentityAndHTMLName() throws {
        let value = try JSONDecoder().decode(DeviceInfo.self, from: Data(info.utf8))
        XCTAssertEqual(value.name, "55\" Odyssey Ark"); try value.verify(expectedID: "fixture-monitor")
        XCTAssertThrowsError(try value.verify(expectedID: "different-device"))
        let tv = try JSONDecoder().decode(DeviceInfo.self, from: Data(info.replacingOccurrences(of: "LS55CG970NNXGO", with: "QN55TV").utf8))
        XCTAssertThrowsError(try tv.verify())
    }
    func testSOAPReadsAndValidation() throws {
        XCTAssertEqual(try SOAP.reading(Data(volume.utf8), action: "GetVolume"), 23)
        XCTAssertEqual(try SOAP.reading(Data(mute.utf8), action: "GetMute"), 0)
        XCTAssertThrowsError(try SOAP.reading(Data(volume.replacingOccurrences(of: ">23<", with: ">123<").utf8), action: "GetVolume"))
        XCTAssertThrowsError(try SOAP.reading(Data("<Fault/>".utf8), action: "GetMute"))
        XCTAssertThrowsError(try XMLTree(Data("<!DOCTYPE x [<!ENTITY a SYSTEM 'file:///etc/passwd'>]><x>&a;</x>".utf8)))
        XCTAssertThrowsError(try SOAP.body("SetVolume", value: -1))
        XCTAssertThrowsError(try SOAP.body("SetMute", value: 2))
        XCTAssertThrowsError(try SOAP.body("GetVolume", value: 23))
        XCTAssertThrowsError(try SOAP.body("SetBrightness", value: 40))
    }
    func testAdvertisedServiceAndActions() throws {
        let xml = "<root xmlns='urn:schemas-upnp-org:device-1-0'><device><manufacturer>Samsung Electronics</manufacturer><serviceList><service><serviceType>\(SOAP.service)</serviceType><controlURL>/upnp/control/RenderingControl1</controlURL><SCPDURL>/RenderingControl_1.xml</SCPDURL></service></serviceList></device></root>"
        let found = try SOAP.renderingService(Data(xml.utf8), host: "192.168.1.153", port: 9197)
        XCTAssertEqual(found.controlPath, service.controlPath)
        XCTAssertThrowsError(try SOAP.renderingService(Data(xml.replacingOccurrences(of: "/upnp/control/RenderingControl1", with: "http://evil.invalid/control").utf8), host: "192.168.1.153", port: 9197))
        let actions = try SOAP.actions(Data("<scpd><actionList><action><name>GetVolume</name></action><action><name>SetVolume</name></action></actionList></scpd>".utf8))
        XCTAssertEqual(actions, ["GetVolume", "SetVolume"])
    }
    func testWrongMonitorPreventsAnyWrite() async throws {
        let transport = StubHTTP([info]); let client = ArkClient(transport: transport)
        do { _ = try await client.set(Endpoint("192.168.1.153"), id: "other", service: service, volume: 23); XCTFail("wrong monitor") } catch {}
        let calls = await transport.requests; XCTAssertEqual(calls.count, 1); XCTAssertEqual(calls[0].httpMethod, "GET")
    }
    func testSameValueWriteReadbackAndNoRetryOnMismatch() async throws {
        for result in [volume, volume.replacingOccurrences(of: ">23<", with: ">24<")] {
            let transport = StubHTTP([info, volume, mute, "<SetVolumeResponse/>", result, mute])
            do {
                let after = try await ArkClient(transport: transport).set(Endpoint("192.168.1.153"), id: "fixture-monitor", service: service, volume: 23)
                XCTAssertEqual(after.volume, 23); XCTAssertEqual(result, volume)
            } catch { XCTAssertNotEqual(result, volume) }
            let calls = await transport.requests
            XCTAssertEqual(calls.count, 6)
            XCTAssertEqual(calls.filter { $0.value(forHTTPHeaderField: "SOAPAction")?.contains("#SetVolume") == true }.count, 1)
        }
    }
    func testUnsupportedWriteStopsBeforeSetting() async throws {
        let transport = StubHTTP([info]); let readOnly = service.withActions(["GetVolume", "GetMute"])
        do { _ = try await ArkClient(transport: transport).set(Endpoint("192.168.1.153"), id: "fixture-monitor", service: readOnly, volume: 23); XCTFail("unsupported") } catch {}
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
    func testCertificatePinsRequireExplicitExactApproval() {
        let fingerprint = CertificatePin.fingerprint(Data("fixture certificate".utf8))
        XCTAssertEqual(fingerprint.count, 64)
        XCTAssertFalse(CertificatePin.matches(fingerprint, nil))
        XCTAssertFalse(CertificatePin.matches(fingerprint, ""))
        XCTAssertFalse(CertificatePin.matches(fingerprint, String(repeating: "a", count: 64)))
        XCTAssertTrue(CertificatePin.matches(fingerprint, fingerprint))
        XCTAssertTrue(CertificatePin.matches(fingerprint, fingerprint.uppercased()))
    }
    func testPairingAndRemoteAllowlist() throws {
        let reply = try PairingReply(Data(#"{"event":"ms.channel.connect","data":{"token":"fixture-token"}}"#.utf8))
        XCTAssertTrue(reply.connected); XCTAssertEqual(reply.token, "fixture-token")
        XCTAssertThrowsError(try PairingReply(Data(#"{"event":"ms.channel.unauthorized"}"#.utf8)))
        XCTAssertNil(RemoteKey(rawValue: "KEY_FACTORY")); XCTAssertNil(RemoteKey(rawValue: "KEY_POWEROFF"))
        let command = try JSONSerialization.jsonObject(with: RemoteKey.back.payload) as! [String: Any]
        XCTAssertEqual((command["params"] as? [String:String])?["DataOfCmd"], "KEY_RETURN")
    }
    func testRelativeVolumeUsesFreshReadingAndOnlyOneWrite() async throws {
        let before = volume.replacingOccurrences(of: ">23<", with: ">52<")
        let after = volume.replacingOccurrences(of: ">23<", with: ">53<")
        let transport = StubHTTP([info, before, mute, "<SetVolumeResponse/>", after, mute])
        let result = try await ArkClient(transport: transport).change(Endpoint("192.168.1.153"), id: "fixture-monitor", service: service, command: .adjustVolume(1))
        XCTAssertEqual(result.volume, 53)
        let requests = await transport.requests
        let writes = requests.filter { $0.value(forHTTPHeaderField: "SOAPAction")?.contains("#Set") == true }
        XCTAssertEqual(writes.count, 1)
        XCTAssertTrue(String(decoding: writes[0].httpBody!, as: UTF8.self).contains("<DesiredVolume>53</DesiredVolume>"))
    }
    func testRelativeBoundsAndInvalidCommands() throws {
        XCTAssertEqual(try AudioCommand.adjustVolume(1).desiredValue(after: .init(volume: 100, muted: false)), 100)
        XCTAssertEqual(try AudioCommand.adjustVolume(-1).desiredValue(after: .init(volume: 0, muted: false)), 0)
        XCTAssertThrowsError(try AudioCommand.adjustVolume(1).desiredValue(after: .init(volume: nil, muted: false)))
        XCTAssertThrowsError(try AudioCommand.adjustVolume(0).validate())
        XCTAssertThrowsError(try AudioCommand.adjustVolume(10).validate())
        XCTAssertThrowsError(try AudioCommand.volume(101).validate())
    }
    func testInvalidStepDoesNotContactMonitor() async throws {
        let transport = StubHTTP([])
        do { _ = try await ArkClient(transport: transport).change(Endpoint("192.168.1.153"), id: "fixture-monitor", service: service, command: .adjustVolume(0)); XCTFail("invalid step") } catch {}
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    func testSameValueMuteHasReadbackAndDoesNotWriteVolume() async throws {
        let transport = StubHTTP([info, volume, mute, "<SetMuteResponse/>", volume, mute])
        let result = try await ArkClient(transport: transport).change(Endpoint("192.168.1.153"), id: "fixture-monitor", service: service, command: .mute(false))
        XCTAssertEqual(result.muted, false); XCTAssertEqual(result.volume, 23)
        let requests = await transport.requests
        XCTAssertEqual(requests.filter { $0.value(forHTTPHeaderField: "SOAPAction")?.contains("#SetMute") == true }.count, 1)
        XCTAssertFalse(requests.contains { $0.value(forHTTPHeaderField: "SOAPAction")?.contains("#SetVolume") == true })
    }
    func testStaleViewTargetIsRejectedBeforeDispatch() throws {
        XCTAssertNoThrow(try ControlTarget.validate(device: "ark", host: "192.168.1.153", selectedDevice: "ark", selectedHost: "192.168.1.153", connected: true))
        for (id, host, connected) in [("other", "192.168.1.153", true), ("ark", "192.168.1.154", true), ("ark", "192.168.1.153", false), ("", "192.168.1.153", true)] {
            XCTAssertThrowsError(try ControlTarget.validate(device: id, host: host, selectedDevice: "ark", selectedHost: "192.168.1.153", connected: connected))
        }
    }

}
