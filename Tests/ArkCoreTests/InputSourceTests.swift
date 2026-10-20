import XCTest
import ArkCore
@testable import ArkPlugin

final class InputSourceTests: XCTestCase {
    func testUserMappingIsConfigurableBoundedAndRoundTrips() throws {
        var mapping = KeyboardSourceMapping()
        XCTAssertEqual(try mapping.source(for: 1), .hdmi1)
        XCTAssertEqual(try mapping.source(for: 2), .displayPort)
        XCTAssertEqual(try mapping.source(for: 3), .hdmi2)
        XCTAssertThrowsError(try mapping.source(for: 0))
        XCTAssertThrowsError(try mapping.set(channel: 4, source: .hdmi1))
        try mapping.set(channel: 2, source: .hdmi2)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardSourceMapping.self, from: JSONEncoder().encode(mapping)), mapping)
        XCTAssertTrue(mapping.confirmed.isEmpty)
        XCTAssertEqual(InputSource.displayPort.remoteKey.rawValue, "KEY_DP")
    }
    @MainActor func testSourceCardConformsToPackagedSDKAndRejectsStaleMonitor() throws {
        let module = ArkModule()
        XCTAssertNoThrow(try module.surface.validate())
        XCTAssertThrowsError(try module.handleView(.init(panelID: "monitor", revision: module.surface.revision, name: "test_source", values: ["device": .string("wrong"), "host": .string("192.168.1.1"), "source": .string("hdmi1")])))
    }
}

final class KeyboardSourceGateTests: XCTestCase {
    func testExactVerifiedMappingAndNoRepeatOrStartupReplay() throws {
        var link = KeyboardSourceLink(); link.provider = "fixture.keyboard"; link.keyboard = "fixture-device"; link.enabled = true
        var map = KeyboardSourceMapping(); map.confirmed = Set(InputSource.allCases)
        var gate = KeyboardSourceGate(); gate.arm(at: 100)
        let id = UUID()
        XCTAssertThrowsError(try gate.accept(id: id, provider: link.provider, keyboard: link.keyboard, channel: 2, observedAt: 99, now: 100, link: link, mapping: map, available: true))
        XCTAssertThrowsError(try gate.accept(id: id, provider: "wrong", keyboard: link.keyboard, channel: 2, observedAt: 101, now: 101, link: link, mapping: map, available: true))
        XCTAssertEqual(try gate.accept(id: id, provider: link.provider, keyboard: link.keyboard, channel: 2, observedAt: 101, now: 101, link: link, mapping: map, available: true), .displayPort)
        XCTAssertThrowsError(try gate.accept(id: id, provider: link.provider, keyboard: link.keyboard, channel: 2, observedAt: 101, now: 101, link: link, mapping: map, available: true))
        gate.disarm()
        XCTAssertThrowsError(try gate.accept(id: UUID(), provider: link.provider, keyboard: link.keyboard, channel: 1, observedAt: 102, now: 102, link: link, mapping: map, available: true))
    }
    func testUnavailableChoiceIsConsumedAndUnverifiedInputsCannotRun() throws {
        var link = KeyboardSourceLink(); link.provider = "fixture.keyboard"; link.keyboard = "fixture-device"; link.enabled = true
        var map = KeyboardSourceMapping(); map.confirmed = [.hdmi1]
        var gate = KeyboardSourceGate(); gate.arm(at: 100)
        let id = UUID()
        XCTAssertThrowsError(try gate.accept(id: id, provider: link.provider, keyboard: link.keyboard, channel: 1, observedAt: 101, now: 101, link: link, mapping: map, available: false))
        XCTAssertThrowsError(try gate.accept(id: id, provider: link.provider, keyboard: link.keyboard, channel: 1, observedAt: 101, now: 101, link: link, mapping: map, available: true))
        XCTAssertThrowsError(try gate.accept(id: UUID(), provider: link.provider, keyboard: link.keyboard, channel: 2, observedAt: 101, now: 101, link: link, mapping: map, available: true))
        for n in [Double.nan, 0, 4, 1.5] { XCTAssertThrowsError(try gate.accept(id: UUID(), provider: link.provider, keyboard: link.keyboard, channel: n, observedAt: 101, now: 101, link: link, mapping: map, available: true)) }
    }
}
