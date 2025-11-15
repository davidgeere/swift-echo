// Logger.swift

import Foundation

/// Simple logging infrastructure for Echo
public actor Logger {
    public enum Level: Int, Comparable, Sendable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var prefix: String {
            switch self {
            case .debug: return "[DEBUG]"
            case .info: return "[INFO]"
            case .warning: return "[WARNING]"
            case .error: return "[ERROR]"
            }
        }
    }

    private var currentLevel: Level = .info

    public init(level: Level = .info) {
        self.currentLevel = level
    }

    public func setLevel(_ level: Level) {
        currentLevel = level
    }

    public func debug(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .debug, file: file, line: line)
    }

    public func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    public func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warning, file: file, line: line)
    }

    public func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }

    private func log(_ message: String, level: Level, file: String, line: Int) {
        guard level >= currentLevel else { return }

        let fileName = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())

        print("\(timestamp) \(level.prefix) [\(fileName):\(line)] \(message)")
    }
}

/// Global logger instance
public let logger = Logger()
