import Foundation

public struct KeyboardSourceLink: Codable, Equatable, Sendable {
    public var provider = ""
    public var keyboard = ""
    public var name = ""
    public var enabled = false
    public init() {}
}
/// One explicit link, with fresh unique choices and no queued/replayed actions.
public struct KeyboardSourceGate: Sendable {
    private var seen = Set<UUID>()
    private var armedAt: Double?
    public var isArmed: Bool { armedAt != nil }
    public init() {}
    public mutating func arm(at date: Double) { seen.removeAll(); armedAt = date }
    public mutating func disarm() { armedAt = nil; seen.removeAll() }
    public mutating func accept(id: UUID, provider: String, keyboard: String, channel: Double, observedAt: Double,
                                now: Double, link: KeyboardSourceLink, mapping: KeyboardSourceMapping, available: Bool) throws -> InputSource {
        guard let armedAt, link.enabled, !link.provider.isEmpty, !link.keyboard.isEmpty,
              provider == link.provider, keyboard == link.keyboard,
              channel.isFinite, channel.rounded() == channel, (1...3).contains(channel),
              observedAt.isFinite, now.isFinite, observedAt >= armedAt, observedAt <= now + 0.25,
              now - observedAt <= 2, !seen.contains(id), seen.count < 4096 else { throw ArkError("Keyboard choice is stale, repeated or belongs to another link.") }
        seen.insert(id)
        let source = try mapping.source(for: Int(channel))
        guard available, mapping.confirmed.contains(source) else { throw ArkError("Input unavailable or unverified. Nothing was queued.") }
        return source
    }
}
