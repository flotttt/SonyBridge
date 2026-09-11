import Foundation

// Minimal test runner (XCTest isn't available without Xcode). Exit code 1 on any failure.
var failures = 0
func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

// ReconnectPolicy: 3 s, 10 s, 30 s, then every 60 s; reset restarts.
do {
    var policy = ReconnectPolicy()
    let delays = (0..<6).map { _ in policy.nextDelay() }
    check(delays == [3, 10, 30, 60, 60, 60], "reconnect schedule was \(delays)")
    policy.reset()
    check(policy.nextDelay() == 3, "reset restarts the schedule")
}

// PollGuard: a poll is ignored for 3 s after the user changed that setting.
do {
    var pollGuard = PollGuard<String>(window: 3)
    let t0 = Date(timeIntervalSince1970: 1_000)
    check(pollGuard.shouldAcceptPoll(for: "ambient", at: t0), "no user change: accept")
    pollGuard.userChanged("ambient", at: t0)
    check(!pollGuard.shouldAcceptPoll(for: "ambient", at: t0.addingTimeInterval(2.9)), "inside the window: reject")
    check(pollGuard.shouldAcceptPoll(for: "ambient", at: t0.addingTimeInterval(3)), "after the window: accept")
    check(pollGuard.shouldAcceptPoll(for: "eq", at: t0.addingTimeInterval(1)), "other keys are unaffected")
}

// SendThrottle: at most one send per 150 ms while dragging; the final value always goes out.
do {
    var throttle = SendThrottle(interval: 0.15)
    let t0 = Date(timeIntervalSince1970: 1_000)
    check(throttle.shouldSend(at: t0, final: false), "first drag event sends")
    check(!throttle.shouldSend(at: t0.addingTimeInterval(0.10), final: false), "too soon: skip")
    check(throttle.shouldSend(at: t0.addingTimeInterval(0.16), final: false), "after the interval: send")
    check(throttle.shouldSend(at: t0.addingTimeInterval(0.17), final: true), "final value always sends")
}

if failures > 0 {
    print("LogicTests: \(failures) failure(s)")
    exit(1)
}
print("LogicTests: all passed")
