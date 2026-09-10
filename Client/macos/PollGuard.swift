import Foundation

// Ignores a polled value for a setting the user changed less than `window` seconds ago, so a read-back that
// raced the user's command doesn't briefly flip the menu back to the old state.
struct PollGuard<Key: Hashable> {
    let window: TimeInterval
    private var lastUserChange: [Key: Date] = [:]

    init(window: TimeInterval = 3) {
        self.window = window
    }

    mutating func userChanged(_ key: Key, at date: Date = Date()) {
        lastUserChange[key] = date
    }

    func shouldAcceptPoll(for key: Key, at date: Date = Date()) -> Bool {
        guard let changed = lastUserChange[key] else { return true }
        return date.timeIntervalSince(changed) >= window
    }
}
