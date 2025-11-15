import Foundation

// MARK: - Duration Extension

extension Duration {
    /// The duration in milliseconds.
    public var milliseconds: Int {
        let (seconds, attoseconds) = self.components
        return Int(seconds * 1000) + Int(attoseconds / 1_000_000_000_000_000)
    }

    /// The duration in seconds as Double.
    public var secondsAsDouble: Double {
        let (seconds, attoseconds) = self.components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }
}
