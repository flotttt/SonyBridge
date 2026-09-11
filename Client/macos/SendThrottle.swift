import Foundation

// Rate-limits slider commands: at most one every `interval` while dragging; the final value always goes out.
struct SendThrottle {
    let interval: TimeInterval
    private var lastSend: Date?

    init(interval: TimeInterval = 0.15) {
        self.interval = interval
    }

    mutating func shouldSend(at date: Date = Date(), final: Bool) -> Bool {
        if !final, let last = lastSend, date.timeIntervalSince(last) < interval {
            return false
        }
        lastSend = date
        return true
    }
}
