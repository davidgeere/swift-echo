import Foundation

/// Logging levels for debugging.
public enum LogLevel: Int, Sendable {
    /// No logging.
    case none = 0

    /// Only errors.
    case error = 1

    /// Warnings and errors.
    case warning = 2

    /// Info, warnings, and errors.
    case info = 3

    /// Detailed debug information.
    case debug = 4

    /// Everything including verbose traces.
    case trace = 5
}
