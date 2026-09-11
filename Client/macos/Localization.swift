import Foundation

// Looks up a UI string in Localizable.strings. Every user-facing string goes through this (checked by make test).
func tr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
