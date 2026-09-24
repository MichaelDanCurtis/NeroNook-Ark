import Foundation

/// Relative volume requests resolve against a fresh device reading, never a UI snapshot.
public enum AudioCommand: Equatable, Sendable {
    case volume(Int)
    case adjustVolume(Int)
    case mute(Bool)
    case toggleMute

    public var action: String { switch self { case .mute, .toggleMute: return "SetMute"; default: return "SetVolume" } }
    public var readAction: String { switch self { case .mute, .toggleMute: return "GetMute"; default: return "GetVolume" } }
    public func validate() throws {
        switch self {
        case .volume(let value): guard (0...100).contains(value) else { throw ArkError("Choose a volume from 0 to 100.") }
        case .adjustVolume(let delta): guard delta != 0 && (-25...25).contains(delta) else { throw ArkError("Choose a volume step from 1 to 25.") }
        case .mute, .toggleMute: break
        }
    }
    public func desiredValue(after reading: AudioState) throws -> Int {
        try validate()
        switch self {
        case .volume(let value): return value
        case .adjustVolume(let delta):
            guard let current = reading.volume, (0...100).contains(current) else { throw ArkError("Read the monitor volume before adjusting it.") }
            return min(100, max(0, current + delta))
        case .mute(let muted): return muted ? 1 : 0
        case .toggleMute:
            guard let muted = reading.muted else { throw ArkError("Read mute before toggling it.") }
            return muted ? 0 : 1
        }
    }
    public func matches(_ reading: AudioState, desired: Int) -> Bool {
        if action == "SetMute" { return reading.muted == (desired == 1) }
        return reading.volume == desired
    }
}

public enum ControlTarget {
    public static func validate(device: String, host: String, selectedDevice: String, selectedHost: String, connected: Bool) throws {
        guard connected, !device.isEmpty, device == selectedDevice, host == selectedHost else {
            throw ArkError("The selected monitor changed or disconnected. Refresh before using this control.")
        }
        _ = try Endpoint(host)
    }
}
