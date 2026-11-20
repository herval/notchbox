import Foundation

/// Tracks time inside one physical display's trigger, independent of event delivery or pointer jitter.
public struct HoverActivation {
    public let delay: TimeInterval
    private var target: UInt32?
    private var enteredAt: TimeInterval?
    private var activated = false
    private var suppressed = false

    public init(delay: TimeInterval = 0.12) { self.delay = delay }

    public mutating func update(target: UInt32?, at time: TimeInterval) -> Bool {
        guard let target else { reset(); return false }
        guard !suppressed else { return false }
        if self.target != target {
            self.target = target
            enteredAt = time
            activated = false
        }
        guard !activated, let enteredAt, time - enteredAt >= delay else { return false }
        activated = true
        return true
    }

    public mutating func suppressUntilExit() {
        reset()
        suppressed = true
    }

    public mutating func reset() {
        target = nil
        enteredAt = nil
        activated = false
        suppressed = false
    }
}
