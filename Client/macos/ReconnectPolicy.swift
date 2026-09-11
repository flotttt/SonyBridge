import Foundation

// Delays between automatic reconnection attempts: 3 s, 10 s, 30 s, then every 60 s.
struct ReconnectPolicy {
    static let delays: [TimeInterval] = [3, 10, 30, 60]
    private(set) var attempt = 0

    // Delay before the next attempt; each call advances the schedule.
    mutating func nextDelay() -> TimeInterval {
        let delay = Self.delays[min(attempt, Self.delays.count - 1)]
        attempt += 1
        return delay
    }

    mutating func reset() {
        attempt = 0
    }
}
