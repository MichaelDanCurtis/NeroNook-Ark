import Foundation

/// Candidate discrete commands. A source is usable automatically only after
/// the owner has verified its physical effect on this exact monitor.
public enum InputSource: String, CaseIterable, Codable, Sendable {
    case hdmi1, displayPort, hdmi2
    public var title: String { switch self { case .hdmi1: "HDMI 1"; case .displayPort: "DisplayPort"; case .hdmi2: "HDMI 2" } }
    public var remoteKey: RemoteKey { switch self { case .hdmi1: .hdmi1; case .displayPort: .displayPort; case .hdmi2: .hdmi2 } }
}

public struct KeyboardSourceMapping: Codable, Equatable, Sendable {
    public var sources: [InputSource] = [.hdmi1, .displayPort, .hdmi2]
    public var confirmed: Set<InputSource> = []
    public init() {}
    public func source(for channel: Int) throws -> InputSource {
        guard sources.count == 3, (1...3).contains(channel) else { throw ArkError("Choose one input for each of the three keyboard channels.") }
        return sources[channel - 1]
    }
    public mutating func set(channel: Int, source: InputSource) throws {
        guard sources.count == 3, (1...3).contains(channel) else { throw ArkError("Unknown keyboard channel.") }
        sources[channel - 1] = source
    }
}
