// Version.swift
// Echo - Version Information
//
// Semantic Versioning: MAJOR.MINOR.PATCH
// - MAJOR: Incompatible API changes
// - MINOR: Backwards-compatible functionality additions  
// - PATCH: Backwards-compatible bug fixes

import Foundation

/// Echo library version information
public enum EchoVersion {
    /// Current version of the Echo library
    public static let current = Version(major: 1, minor: 1, patch: 0)
    
    /// Version string (e.g., "1.0.0")
    public static var string: String {
        current.description
    }
    
    /// Full version string with library name
    public static var full: String {
        "Echo \(string)"
    }
    
    /// Build information
    public static let build = BuildInfo(
        date: "2025-11-23",
        commit: "main"
    )
}

/// Represents a semantic version
public struct Version: CustomStringConvertible, Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    
    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }
    
    public var description: String {
        let base = "\(major).\(minor).\(patch)"
        if let pre = prerelease {
            return "\(base)-\(pre)"
        }
        return base
    }
    
    public static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        
        // Pre-release versions have lower precedence
        if lhs.prerelease != nil && rhs.prerelease == nil { return true }
        if lhs.prerelease == nil && rhs.prerelease != nil { return false }
        
        // Compare pre-release versions lexically
        if let lhsPre = lhs.prerelease, let rhsPre = rhs.prerelease {
            return lhsPre < rhsPre
        }
        
        return false
    }
}

/// Build information
public struct BuildInfo: Sendable {
    public let date: String
    public let commit: String
}

// MARK: - Version History

extension EchoVersion {
    /// Version history with release notes
    public static let history: [(version: Version, date: String, notes: String)] = [
        (
            version: Version(major: 1, minor: 1, patch: 0),
            date: "2025-11-23",
            notes: """
            🎯 All Events Handler & Stream
            
            New Features:
            • Listen to all events: echo.when { event in ... }
            • Async stream: for await event in echo.events { ... }
            • Sequential event processing with break support
            • Automatic handler cleanup on deallocation
            
            Memory Safety:
            • Handlers automatically cleaned up to prevent leaks
            • Proper deinit cleanup in EventEmitter
            
            Testing:
            • 5 new comprehensive tests for all-events functionality
            • Full coverage of handler and stream patterns
            """
        ),
        (
            version: Version(major: 1, minor: 0, patch: 2),
            date: "2025-11-23",
            notes: """
            📚 Enhanced Event System
            
            Event Features:
            • Multiple event listeners with array syntax: echo.when([.event1, .event2])
            • Multiple event listeners with variadic syntax: echo.when(.event1, .event2)
            • Comprehensive event documentation (EVENTS.md)
            • Complete test coverage for event system
            
            Documentation:
            • Added EVENTS.md with complete event reference
            • Examples for all 25 event types
            • Usage patterns and best practices
            """
        ),
        (
            version: Version(major: 1, minor: 0, patch: 1),
            date: "2025-11-23",
            notes: """
            🔊 Dynamic Speaker Routing
            
            Audio Features:
            • Runtime control of audio output routing
            • Switch between speaker and earpiece at any time
            • Proper Bluetooth device handling
            • Consistent API pattern with setMuted()
            """
        ),
        (
            version: Version(major: 1, minor: 0, patch: 0),
            date: "2024-11-15",
            notes: """
            🚀 Initial Release
            
            Core Features:
            • Unified API for Realtime (voice) and Responses (text) APIs
            • Seamless mode switching with context preservation
            • Message queue architecture for proper sequencing
            • Event-driven system with expressive syntax
            
            Voice Features:
            • Real-time voice conversations via WebSocket
            • Voice Activity Detection (automatic/manual/disabled)
            • Audio level monitoring for UI animations
            • Automatic transcription of all interactions
            
            Text Features:
            • Traditional text conversations with streaming
            • Server-Sent Events (SSE) support
            • Full context preservation
            
            Embeddings API:
            • Single and batch embedding generation
            • Semantic similarity search
            • Multiple model support with dimension control
            
            Structured Output:
            • Type-safe JSON generation
            • Codable schema support
            • Complex nested structures
            
            Tool Calling:
            • Function calling for both APIs
            • Automatic tool execution
            • MCP server support
            
            Technical:
            • Swift 6.0 with strict concurrency
            • Actor-based architecture
            • AsyncStream for data flow
            • @Observable for SwiftUI
            • iOS 18+ / macOS 14+
            """
        )
    ]
}

// MARK: - Version Checking

extension Echo {
    /// Current Echo version
    public static var version: String {
        EchoVersion.string
    }
    
    /// Check if library meets minimum version requirement
    public static func meetsMinimumVersion(_ required: String) -> Bool {
        guard let requiredVersion = parseVersion(required) else { return false }
        return EchoVersion.current >= requiredVersion
    }
    
    private static func parseVersion(_ string: String) -> Version? {
        let components = string.split(separator: ".")
        guard components.count >= 2 else { return nil }
        
        let major = Int(components[0]) ?? 0
        let minor = Int(components[1]) ?? 0
        let patch = components.count > 2 ? (Int(components[2]) ?? 0) : 0
        
        return Version(major: major, minor: minor, patch: patch)
    }
}